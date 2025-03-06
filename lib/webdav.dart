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
      final localPath = '/storage/Users/currentUser/Download/com.aloereed.aloeplayer/$mediaType/${file.name}';
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
    return AlertDialog(
      title: Text('WebDAV 文件下载'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_client == null) ...[
              TextField(
                controller: _urlController,
                decoration: InputDecoration(labelText: 'WebDAV URL（请包含http://或https://）'),
              ),
              TextField(
                controller: _usernameController,
                decoration: InputDecoration(labelText: '用户名'),
              ),
              TextField(
                controller: _passwordController,
                decoration: InputDecoration(labelText: '密码'),
                obscureText: true,
              ),
              SizedBox(height: 16),
              ElevatedButton(
                onPressed: _connectToWebDAV,
                child: Text('连接',style: TextStyle(color: Colors.lightBlue)),
              ),
            ] else ...[
              _isLoading
                  ? CircularProgressIndicator()
                  : _errorMessage != null
                      ? Text(_errorMessage!,
                          style: TextStyle(color: Colors.red))
                      : Column(
                          children: [
                            // 显示当前路径
                            Text('当前路径: $_currentPath'),
                            SizedBox(height: 8),
                            // 返回上一级按钮
                            if (_currentPath != '/')
                              ElevatedButton(
                                onPressed: _navigateBack,
                                child: Text('返回'),
                              ),
                            TextField(
                              controller: _searchController,
                              decoration: InputDecoration(
                                labelText: '搜索',
                                prefixIcon: Icon(Icons.search),
                              ),
                            ),
                            SizedBox(height: 8),
                            // 文件列表
                            ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight: MediaQuery.of(context).size.height *
                                    0.5, // 限制最大高度
                              ),
                              child: ListView.builder(
                                shrinkWrap: true,
                                itemCount: _getFilteredFiles().length,
                                itemBuilder: (context, index) {
                                  final file = _getFilteredFiles()[index];
                                  return ListTile(
                                    leading: Icon(file.isDir!
                                        ? Icons.folder
                                        : Icons.file_copy),
                                    title: Text(file.name!),
                                    trailing: file.isDir!
                                        ? null
                                        : IconButton(
                                            icon: Icon(Icons.download),
                                            onPressed: () =>
                                                _downloadFile(file),
                                          ),
                                    onTap: file.isDir!
                                        ? () => _loadFiles(file.path!)
                                        : null,
                                  );
                                },
                              ),
                            ),
                            if (_downloadProgress > 0.0)
                              LinearProgressIndicator(
                                value: _downloadProgress,
                                minHeight: 4,
                              ),
                          ],
                        ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () {
            widget.onLoadFiles();
            Navigator.of(context).pop();
          },
          child: Text('关闭'),
        ),
      ],
    );
  }
}
