import 'package:flutter/material.dart';
import 'package:webdav_client/webdav_client.dart' as webdav;
import 'package:shared_preferences/shared_preferences.dart';

class WebDAVDialog extends StatefulWidget {
  final Function() onLoadFiles;
  final List<String> fileExts;
  // 构造函数
  WebDAVDialog({required this.onLoadFiles, required this.fileExts});
  @override
  _WebDAVDialogState createState() => _WebDAVDialogState();
}

class _WebDAVDialogState extends State<WebDAVDialog> {
  final _urlController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();

  webdav.Client? _client;
  List<webdav.File> _files = [];
  bool _isLoading = false;
  String? _errorMessage;
  double _downloadProgress = 0.0;
  String _currentPath = '/'; // 当前路径
  final List<String> _pathHistory = ['/']; // 路径历史记录

  final _searchController = TextEditingController();
  String _searchKeyword = ''; // 当前搜索关键字

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
    // 监听搜索框的输入变化
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  // 搜索框输入变化时的回调
  void _onSearchChanged() {
    setState(() {
      _searchKeyword = _searchController.text;
    });
  }

  // 根据搜索关键字过滤文件列表
  List<webdav.File> _getFilteredFiles() {
    if (_searchKeyword.isEmpty) {
      return _files;
    }
    return _files.where((file) {
      return file.name!.toLowerCase().contains(_searchKeyword.toLowerCase());
    }).toList();
  }

  // 加载保存的凭据
  Future<void> _loadSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _urlController.text = prefs.getString('webdav_url') ?? '';
      _usernameController.text = prefs.getString('webdav_username') ?? '';
      _passwordController.text = prefs.getString('webdav_password') ?? '';
    });
  }

  // 保存凭据
  Future<void> _saveCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('webdav_url', _urlController.text);
    await prefs.setString('webdav_username', _usernameController.text);
    await prefs.setString('webdav_password', _passwordController.text);
  }

  // 连接WebDAV服务器
  Future<void> _connectToWebDAV() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      _client = webdav.newClient(
        _urlController.text,
        user: _usernameController.text,
        password: _passwordController.text,
        debug: true,
      );

      // 测试连接
      await _client!.ping();

      // 保存凭据
      await _saveCredentials();

      // 读取当前路径的内容
      await _loadFiles(_currentPath);
    } catch (e) {
      setState(() {
        _errorMessage = '连接失败: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 加载指定路径的文件和文件夹
  Future<void> _loadFiles(String path) async {
    if (_client == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      _files = await _client!.readDir(path);
      // 根据widget.fileExts过滤文件
      _files = _files.where((file) {
        if (file.isDir!) return true; // 文件夹
        final ext = file.name!.split('.').last;
        return widget.fileExts.contains(ext);
      }).toList();
      _currentPath = path;
      _pathHistory.add(path); // 添加到路径历史记录
    } catch (e) {
      setState(() {
        _errorMessage = '加载文件失败: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 下载文件
  Future<void> _downloadFile(webdav.File file) async {
    if (_client == null || file.isDir!) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _downloadProgress = 0.0;
    });

    try {
      final mediaType = widget.fileExts.contains('mp3')
          ? 'Audios'
          : widget.fileExts.contains('mp4')
              ? 'Videos'
              : 'Others';
      final localPath =
          '/storage/Users/currentUser/Download/com.aloereed.aloeplayer/$mediaType/${file.name}';
      await _client!.read2File(
        file.path!,
        localPath,
        onProgress: (current, total) {
          setState(() {
            _downloadProgress = current / total;
          });
        },
      );

      // 显示下载成功消息
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已下载 ${file.name} 到 $localPath')),
      );
    } catch (e) {
      setState(() {
        _errorMessage = '下载失败: $e';
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  // 返回上一级目录
  void _navigateBack() {
    if (_pathHistory.length > 1) {
      _pathHistory.removeLast(); // 移除当前路径
      final previousPath = _pathHistory.last;
      _loadFiles(previousPath);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20.0),
      ),
      elevation: 0,
      backgroundColor: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: isDarkMode ? Color(0xFF2C2C2C) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 10,
              offset: Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 头部标题区域
            Container(
              decoration: BoxDecoration(
                color: Colors.lightBlue,
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(20),
                  topRight: Radius.circular(20),
                ),
              ),
              padding: EdgeInsets.symmetric(vertical: 16, horizontal: 24),
              child: Row(
                children: [
                  Icon(
                    Icons.cloud_download_rounded,
                    color: Colors.white,
                    size: 28,
                  ),
                  SizedBox(width: 12),
                  Text(
                    'WebDAV 文件下载',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            ),

            // 内容区域
            Container(
              padding: EdgeInsets.all(24),
              child: SingleChildScrollView(
                child: _client == null
                    ? _buildLoginForm(context)
                    : _buildFileExplorer(context),
              ),
            ),

            // 底部按钮区域
            Container(
              padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              decoration: BoxDecoration(
                color: isDarkMode ? Color(0xFF222222) : Colors.grey[50],
                borderRadius: BorderRadius.only(
                  bottomLeft: Radius.circular(20),
                  bottomRight: Radius.circular(20),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      widget.onLoadFiles();
                      Navigator.of(context).pop();
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.grey,
                      padding:
                          EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text('关闭'),
                  ),
                  SizedBox(width: 8),
                  if (_client != null)
                    ElevatedButton(
                      onPressed: () {
                        // 断开连接
                        setState(() {
                          _client = null;
                          _currentPath = '/';
                          _files.clear();
                        });
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        foregroundColor: Colors.white,
                        padding:
                            EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      child: Text('断开连接'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

// 登录表单部分
  Widget _buildLoginForm(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '连接到 WebDAV 服务器',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Colors.lightBlue,
          ),
        ),
        SizedBox(height: 20),
        _buildInputField(
          controller: _urlController,
          label: 'WebDAV URL',
          hintText: '请输入完整地址，例如 https://example.com/webdav',
          icon: Icons.link_rounded,
          keyboardType: TextInputType.url,
        ),
        SizedBox(height: 16),
        _buildInputField(
          controller: _usernameController,
          label: '用户名',
          hintText: '输入WebDAV账号用户名',
          icon: Icons.person_rounded,
        ),
        SizedBox(height: 16),
        _buildInputField(
          controller: _passwordController,
          label: '密码',
          hintText: '输入WebDAV账号密码',
          icon: Icons.lock_rounded,
          isPassword: true,
        ),
        SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: _connectToWebDAV,
            icon: Icon(Icons.login_rounded),
            label: Text('连接服务器'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.lightBlue,
              foregroundColor: Colors.white,
              padding: EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
        ),
      ],
    );
  }

// 文件浏览器部分
  Widget _buildFileExplorer(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_isLoading)
          Center(
            child: Column(
              children: [
                CircularProgressIndicator(),
                SizedBox(height: 16),
                Text('正在加载文件...', style: TextStyle(color: Colors.grey)),
              ],
            ),
          )
        else if (_errorMessage != null)
          Container(
            padding: EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.red[50],
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.red[200]!),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(color: Colors.red[700]),
                  ),
                ),
              ],
            ),
          )
        else
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 面包屑导航
              Container(
                padding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey[800]
                      : Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.folder_open,
                        size: 18, color: Colors.lightBlue),
                    SizedBox(width: 8),
                    Expanded(
                      child: _buildBreadcrumbPath(),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 16),

              // 返回上级按钮和搜索框
              Row(
                children: [
                  if (_currentPath != '/')
                    IconButton(
                      onPressed: _navigateBack,
                      icon: Icon(Icons.arrow_back),
                      tooltip: "返回上级",
                      style: IconButton.styleFrom(
                        backgroundColor:
                            Theme.of(context).brightness == Brightness.dark
                                ? Colors.grey[800]
                                : Colors.grey[200],
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  SizedBox(width: _currentPath != '/' ? 8 : 0),
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.grey[800]
                            : Colors.grey[200],
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: TextField(
                        controller: _searchController,
                        onChanged: (value) => setState(() {}),
                        decoration: InputDecoration(
                          hintText: '搜索文件...',
                          prefixIcon: Icon(Icons.search),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              SizedBox(height: 16),

              // 文件列表
              Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.grey[850]
                      : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey[700]!
                        : Colors.grey[300]!,
                  ),
                ),
                height: MediaQuery.of(context).size.height * 0.37,
                child: _files.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.folder_off,
                              size: 48,
                              color: Colors.grey[400],
                            ),
                            SizedBox(height: 16),
                            Text(
                              '此文件夹为空',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : ListView.separated(
                        padding: EdgeInsets.all(8),
                        itemCount: _getFilteredFiles().length,
                        separatorBuilder: (context, index) =>
                            Divider(height: 1),
                        itemBuilder: (context, index) {
                          final file = _getFilteredFiles()[index];
                          final fileExt = file.isDir!
                              ? '目录'
                              : _getFileExtension(file.name!);
                          final showDownload = !file.isDir! &&
                                  widget.fileExts.isEmpty ||
                              widget.fileExts.contains(
                                  _getFileExtension(file.name!).toLowerCase());

                          return ListTile(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            leading: _getFileIcon(file),
                            title: Text(
                              file.name!,
                              style: TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            subtitle: Text(
                              file.isDir! ? '文件夹' : _formatFileInfo(file),
                              style: TextStyle(fontSize: 12),
                            ),
                            trailing: file.isDir!
                                ? Icon(Icons.arrow_forward_ios, size: 14)
                                : showDownload
                                    ? IconButton(
                                        icon: Icon(
                                          Icons.file_download_outlined,
                                          color: Colors.lightBlue,
                                        ),
                                        tooltip: '下载文件',
                                        onPressed: () => _downloadFile(file),
                                      )
                                    : Text(
                                        '不支持的格式',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey,
                                        ),
                                      ),
                            onTap: file.isDir!
                                ? () => _loadFiles(file.path!)
                                : null,
                          );
                        },
                      ),
              ),

              // 下载进度条
              if (_downloadProgress > 0.0)
                Padding(
                  padding: const EdgeInsets.only(top: 16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '下载进度：',
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          Text(
                            '${(_downloadProgress * 100).toStringAsFixed(1)}%',
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              color: Colors.lightBlue,
                            ),
                          ),
                        ],
                      ),
                      SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: LinearProgressIndicator(
                          value: _downloadProgress,
                          minHeight: 8,
                          backgroundColor: Colors.grey[200],
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.lightBlue,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
      ],
    );
  }

// 构建输入框的辅助方法
  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hintText,
    required IconData icon,
    bool isPassword = false,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Colors.grey[700],
          ),
        ),
        SizedBox(height: 6),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).brightness == Brightness.dark
                ? Colors.grey[800]
                : Colors.grey[100],
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey[700]!
                  : Colors.grey[300]!,
            ),
          ),
          child: TextField(
            controller: controller,
            obscureText: isPassword,
            keyboardType: keyboardType,
            style: TextStyle(fontSize: 15),
            decoration: InputDecoration(
              hintText: hintText,
              prefixIcon: Icon(icon),
              border: InputBorder.none,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ),
      ],
    );
  }

// 构建面包屑导航
  Widget _buildBreadcrumbPath() {
    List<String> pathParts = _currentPath.split('/')
      ..removeWhere((part) => part.isEmpty);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          InkWell(
            onTap: () => _loadFiles('/'),
            child: Text(
              'Root',
              style: TextStyle(color: Colors.lightBlue),
            ),
          ),
          ...pathParts.asMap().entries.map((entry) {
            int idx = entry.key;
            String part = entry.value;
            String pathToHere = '/' + pathParts.sublist(0, idx + 1).join('/');

            return Row(
              children: [
                Text(' / ', style: TextStyle(color: Colors.grey)),
                InkWell(
                  onTap: () => _loadFiles(pathToHere),
                  child: Text(
                    part,
                    style: TextStyle(color: Colors.lightBlue),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            );
          }).toList(),
        ],
      ),
    );
  }

// 获取文件图标
  Widget _getFileIcon(webdav.File file) {
    if (file.isDir!) {
      return Container(
        padding: EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.blue[50],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.folder, color: Colors.blue),
      );
    }

    final ext = _getFileExtension(file.name!).toLowerCase();

    // 图像文件
    if (['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(ext)) {
      return Container(
        padding: EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.green[50],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.image, color: Colors.green),
      );
    }

    // 视频文件
    if (['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(ext)) {
      return Container(
        padding: EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.red[50],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.movie, color: Colors.red),
      );
    }

    // 音频文件
    if (['mp3', 'wav', 'flac', 'ogg', 'm4a'].contains(ext)) {
      return Container(
        padding: EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.purple[50],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.music_note, color: Colors.purple),
      );
    }

    // 文档文件
    if (['pdf', 'doc', 'docx', 'xls', 'xlsx', 'txt'].contains(ext)) {
      return Container(
        padding: EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.orange[50],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(Icons.description, color: Colors.orange),
      );
    }

    // 其他文件
    return Container(
      padding: EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(Icons.insert_drive_file, color: Colors.grey[700]),
    );
  }

// 格式化文件信息
  String _formatFileInfo(webdav.File file) {
    final ext = _getFileExtension(file.name!);
    final size = file.size != null ? _formatFileSize(file.size!) : '未知大小';
    final modified = file.mTime != null
        ? '${file.mTime!.year}-${file.mTime!.month}-${file.mTime!.day}'
        : '未知时间';

    return '$ext • $size • $modified';
  }

// 格式化文件大小
  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024)
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

// 获取文件扩展名
  String _getFileExtension(String fileName) {
    final lastDotIndex = fileName.lastIndexOf('.');
    if (lastDotIndex == -1 || lastDotIndex == fileName.length - 1) {
      return '未知';
    }
    return fileName.substring(lastDotIndex + 1).toUpperCase();
  }
}
