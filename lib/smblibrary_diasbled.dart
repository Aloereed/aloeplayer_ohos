import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smb_connect/smb_connect.dart';

class MediaLibraryPage extends StatefulWidget {
  final Function(String url) getopenfile;
  final Function(BuildContext context) startPlayerPage;

  const MediaLibraryPage({
    Key? key,
    required this.getopenfile,
    required this.startPlayerPage,
  }) : super(key: key);

  @override
  _MediaLibraryPageState createState() => _MediaLibraryPageState();
}

class _MediaLibraryPageState extends State<MediaLibraryPage>
    with SingleTickerProviderStateMixin {
  final _secureStorage = const FlutterSecureStorage();
  final _dio = Dio();

  late TabController _tabController;
  bool _isConnected = false;
  bool _isLoading = false;
  SmbConnect? _connect;

  List<SmbFile> _currentFiles = [];
  List<String> _navigationPath = [];
  String _currentPath = "";

  // 存储最近播放的媒体文件作为背景
  String? _backgroundImageUrl;

  // 服务器登录信息
  final TextEditingController _hostController = TextEditingController();
  final TextEditingController _domainController = TextEditingController();
  final TextEditingController _usernameController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  List<Map<String, String>> _savedServers = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadSavedServers();
    _loadRecentBackground();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _connect?.close();
    super.dispose();
  }

  // 加载保存的背景图
  Future<void> _loadRecentBackground() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _backgroundImageUrl = prefs.getString('recent_background');
    });
  }

  // 保存背景图
  Future<void> _saveRecentBackground(String url) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('recent_background', url);
    setState(() {
      _backgroundImageUrl = url;
    });
  }

  // 加载保存的服务器信息
  Future<void> _loadSavedServers() async {
    try {
      final serversString = await _secureStorage.read(key: 'saved_servers');
      if (serversString != null && serversString.isNotEmpty) {
        List<dynamic> decodedList = serversString
            .split('|||')
            .map((server) {
              List<String> parts = server.split(':::');
              if (parts.length == 4) {
                return {
                  'host': parts[0],
                  'domain': parts[1],
                  'username': parts[2],
                  'password': parts[3],
                };
              }
              return null;
            })
            .where((item) => item != null)
            .toList();

        setState(() {
          _savedServers = List<Map<String, String>>.from(
              decodedList.map((e) => Map<String, String>.from(e as Map)));
        });
      }
    } catch (e) {
      print('Error loading saved servers: $e');
    }
  }

  // 保存服务器信息
  Future<void> _saveServer(
      String host, String domain, String username, String password) async {
    try {
      // 检查是否已保存
      bool exists = _savedServers.any(
          (server) => server['host'] == host && server['username'] == username);

      if (!exists) {
        setState(() {
          _savedServers.add({
            'host': host,
            'domain': domain,
            'username': username,
            'password': password,
          });
        });

        // 保存到安全存储
        String serversString = _savedServers.map((server) {
          return '${server['host']}:::${server['domain']}:::${server['username']}:::${server['password']}';
        }).join('|||');

        await _secureStorage.write(key: 'saved_servers', value: serversString);
      }
    } catch (e) {
      print('Error saving server: $e');
    }
  }

  // 连接到SMB服务器
  Future<void> _connectToServer(
      String host, String domain, String username, String password) async {
    setState(() {
      _isLoading = true;
    });

    try {
      final connect = await SmbConnect.connectAuth(
          host: host,
          domain: domain,
          username: username,
          password: password,
          debugPrint: true,
          debugPrintLowLevel: true);

      setState(() {
        _connect = connect;
        _isConnected = true;
        _navigationPath = [];
        _currentPath = "";
        _isLoading = false;
      });

      // 保存服务器信息
      await _saveServer(host, domain, username, password);

      // 加载根目录
      _listRoot();
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('连接失败: $e'), backgroundColor: Colors.red));
    }
  }

  // 列出共享文件夹
  Future<void> _listRoot() async {
    if (_connect == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      var shares = await _connect!.listShares();
      setState(() {
        _currentFiles = shares;
        _navigationPath = [];
        _currentPath = "";
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('获取共享文件夹失败: $e'), backgroundColor: Colors.red));
    }
  }

  // 列出文件夹内容
  Future<void> _listFiles(SmbFile folder) async {
    if (_connect == null) return;

    setState(() {
      _isLoading = true;
    });

    try {
      List<SmbFile> files = await _connect!.listFiles(folder);
      setState(() {
        _currentFiles = files;
        if (_navigationPath.isEmpty || _navigationPath.last != folder.path) {
          _navigationPath.add(folder.path);
        }
        _currentPath = folder.path;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('获取文件列表失败: $e'), backgroundColor: Colors.red));
    }
  }

  // 返回上一级目录
  Future<void> _navigateUp() async {
    if (_navigationPath.length > 1) {
      _navigationPath.removeLast();
      String parentPath = _navigationPath.last;
      SmbFile parentFolder = await _connect!.file(parentPath);
      await _listFiles(parentFolder);
    } else if (_navigationPath.length == 1) {
      _listRoot();
    }
  }

  // 创建临时文件并获取URL
  Future<String> _createStreamUrl(SmbFile file) async {
    // 创建临时目录路径
    final tempDir = await getTemporaryDirectory();
    final String tempPath =
        '${tempDir.path}/temp_stream_${DateTime.now().millisecondsSinceEpoch}.${_getFileExtension(file.path)}';

    // 创建临时目录
    await Directory(tempDir.path).create(recursive: true);

    // 打开SMB文件流
    Stream<List<int>> fileStream = await _connect!.openRead(file);

    // 将流写入到临时文件
    final tempFile = File(tempPath);
    IOSink sink = tempFile.openWrite();

    // 临时使用一个状态管理进度更新
    final completer = Completer<void>();

    // 使用transform处理流
    fileStream.listen(
      (chunk) {
        sink.add(chunk);
      },
      onDone: () async {
        await sink.flush();
        await sink.close();
        completer.complete();
      },
      onError: (e) {
        completer.completeError(e);
      },
    );

    // 等待完成
    await completer.future;

    // 返回文件URL
    return 'file://$tempPath';
  }

  // 获取文件扩展名
  String _getFileExtension(String path) {
    return path.split('.').last;
  }

  // 检查文件是否是媒体文件
  bool _isMediaFile(String path) {
    final ext = _getFileExtension(path).toLowerCase();
    final videoExts = ['mp4', 'mkv', 'avi', 'mov', 'wmv', 'flv', 'webm', 'm4v'];
    final audioExts = ['mp3', 'wav', 'ogg', 'flac', 'm4a', 'aac'];

    return videoExts.contains(ext) || audioExts.contains(ext);
  }

  // 处理文件点击
  Future<void> _handleFileClick(SmbFile file) async {
    if (file.isDirectory()) {
      await _listFiles(file);
    } else if (_isMediaFile(file.path)) {
      setState(() {
        _isLoading = true;
      });

      try {
        // 获取流URL
        final url = await _createStreamUrl(file);

        final mediaExts = [
          'mp4',
          'mkv',
          'avi',
          'mov',
          'wmv',
          'flv',
          'webm',
          'm4v'
        ];
        // 如果是视频文件，保存为背景
        if (mediaExts.contains(_getFileExtension(file.path).toLowerCase())) {
          await _saveRecentBackground(url);
        }

        // 使用父组件的方法打开文件
        widget.getopenfile(url);
        widget.startPlayerPage(context);

        setState(() {
          _isLoading = false;
        });
      } catch (e) {
        setState(() {
          _isLoading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('打开文件失败: $e'), backgroundColor: Colors.red));
      }
    } else {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('不支持的文件格式')));
    }
  }

  // 登录表单
  Widget _buildLoginForm() {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Column(
        children: [
          Text(
            '连接到SMB服务器',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          SizedBox(height: 20),
          ClipRRect(
            borderRadius: BorderRadius.circular(15),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
              child: Container(
                padding: EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.2),
                    width: 1.5,
                  ),
                ),
                child: Column(
                  children: [
                    TextField(
                      controller: _hostController,
                      decoration: InputDecoration(
                        labelText: '服务器地址',
                        labelStyle: TextStyle(color: Colors.white),
                        enabledBorder: OutlineInputBorder(
                          borderSide:
                              BorderSide(color: Colors.white.withOpacity(0.3)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide:
                              BorderSide(color: Colors.white.withOpacity(0.6)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        prefixIcon: Icon(Icons.computer, color: Colors.white70),
                      ),
                      style: TextStyle(color: Colors.white),
                    ),
                    SizedBox(height: 15),
                    TextField(
                      controller: _domainController,
                      decoration: InputDecoration(
                        labelText: '域（可选）',
                        labelStyle: TextStyle(color: Colors.white),
                        enabledBorder: OutlineInputBorder(
                          borderSide:
                              BorderSide(color: Colors.white.withOpacity(0.3)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide:
                              BorderSide(color: Colors.white.withOpacity(0.6)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        prefixIcon: Icon(Icons.domain, color: Colors.white70),
                      ),
                      style: TextStyle(color: Colors.white),
                    ),
                    SizedBox(height: 15),
                    TextField(
                      controller: _usernameController,
                      decoration: InputDecoration(
                        labelText: '用户名',
                        labelStyle: TextStyle(color: Colors.white),
                        enabledBorder: OutlineInputBorder(
                          borderSide:
                              BorderSide(color: Colors.white.withOpacity(0.3)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide:
                              BorderSide(color: Colors.white.withOpacity(0.6)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        prefixIcon: Icon(Icons.person, color: Colors.white70),
                      ),
                      style: TextStyle(color: Colors.white),
                    ),
                    SizedBox(height: 15),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: '密码',
                        labelStyle: TextStyle(color: Colors.white),
                        enabledBorder: OutlineInputBorder(
                          borderSide:
                              BorderSide(color: Colors.white.withOpacity(0.3)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide:
                              BorderSide(color: Colors.white.withOpacity(0.6)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        prefixIcon: Icon(Icons.lock, color: Colors.white70),
                      ),
                      style: TextStyle(color: Colors.white),
                    ),
                    SizedBox(height: 20),
                    ElevatedButton.icon(
                      onPressed: _isLoading
                          ? null
                          : () => _connectToServer(
                                _hostController.text,
                                _domainController.text,
                                _usernameController.text,
                                _passwordController.text,
                              ),
                      icon: Icon(
                          _isLoading ? Icons.hourglass_empty : Icons.login),
                      label: Text(_isLoading ? '连接中...' : '连接'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent.withOpacity(0.8),
                        foregroundColor: Colors.white,
                        padding:
                            EdgeInsets.symmetric(horizontal: 30, vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          SizedBox(height: 30),
          if (_savedServers.isNotEmpty) ...[
            Text(
              '已保存的服务器',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w500,
                color: Colors.white,
              ),
            ),
            SizedBox(height: 15),
            Expanded(
              child: ListView.builder(
                itemCount: _savedServers.length,
                itemBuilder: (context, index) {
                  final server = _savedServers[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 10.0),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.2),
                            ),
                          ),
                          child: ListTile(
                            leading: Icon(Icons.storage, color: Colors.white70),
                            title: Text(
                              '${server['host']}',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              '${server['username']}',
                              style: TextStyle(color: Colors.white70),
                            ),
                            trailing: Icon(Icons.login, color: Colors.white70),
                            onTap: () => _connectToServer(
                              server['host']!,
                              server['domain']!,
                              server['username']!,
                              server['password']!,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  // 文件浏览视图
  Widget _buildFileExplorer() {
    return Column(
      children: [
        // 导航栏
        Container(
          height: 50,
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(10),
          ),
          margin: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back, color: Colors.white),
                onPressed: _navigationPath.isEmpty ? null : _navigateUp,
              ),
              IconButton(
                icon: Icon(Icons.home, color: Colors.white),
                onPressed: _listRoot,
              ),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: Text(
                      _currentPath.isEmpty ? '根目录' : _currentPath,
                      style: TextStyle(color: Colors.white, fontSize: 16),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.refresh, color: Colors.white),
                onPressed: () {
                  if (_currentPath.isEmpty) {
                    _listRoot();
                  } else {
                    _connect!.file(_currentPath).then(_listFiles);
                  }
                },
              ),
            ],
          ),
        ),

        // 文件列表
        Expanded(
          child: _isLoading
              ? Center(child: CircularProgressIndicator(color: Colors.white))
              : _currentFiles.isEmpty
                  ? Center(
                      child:
                          Text('没有文件', style: TextStyle(color: Colors.white70)))
                  : GridView.builder(
                      padding: EdgeInsets.all(10),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: 1.0,
                        crossAxisSpacing: 10,
                        mainAxisSpacing: 10,
                      ),
                      itemCount: _currentFiles.length,
                      itemBuilder: (context, index) {
                        final file = _currentFiles[index];
                        final isMedia = _isMediaFile(file.path);
                        final fileName = file.path.split('/').last;
                        final mediaExts = [
                          'mp4',
                          'mkv',
                          'avi',
                          'mov',
                          'wmv',
                          'flv',
                          'webm',
                          'm4v'
                        ];
                        return InkWell(
                          onTap: () => _handleFileClick(file),
                          borderRadius: BorderRadius.circular(15),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(15),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(15),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.2),
                                    width: 1.5,
                                  ),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      file.isDirectory()
                                          ? Icons.folder
                                          : isMedia
                                              ? mediaExts.contains(
                                                      _getFileExtension(
                                                              file.path)
                                                          .toLowerCase())
                                                  ? Icons.video_file
                                                  : Icons.audio_file
                                              : Icons.insert_drive_file,
                                      size: 50,
                                      color: file.isDirectory()
                                          ? Colors.amber
                                          : isMedia
                                              ? Colors.greenAccent
                                              : Colors.white70,
                                    ),
                                    SizedBox(height: 10),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8.0),
                                      child: Text(
                                        fileName,
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.w500,
                                        ),
                                        textAlign: TextAlign.center,
                                        overflow: TextOverflow.ellipsis,
                                        maxLines: 2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  // 收藏夹视图（针对常用媒体文件的快捷访问）
  Widget _buildFavorites() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.star,
            color: Colors.white.withOpacity(0.7),
            size: 80,
          ),
          SizedBox(height: 20),
          Text(
            '收藏夹功能即将推出',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
            ),
          ),
          SizedBox(height: 10),
          Text(
            '在此处可收藏你常用的媒体文件',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 16,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 背景
          if (_backgroundImageUrl != null)
            Positioned.fill(
              child: Image.network(
                _backgroundImageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) {
                  return Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Colors.blueGrey.shade900,
                          Colors.black87,
                        ],
                      ),
                    ),
                  );
                },
              ),
            )
          else
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.blueGrey.shade900,
                      Colors.black87,
                    ],
                  ),
                ),
              ),
            ),

          // 主内容
          BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
            child: SafeArea(
              child: Column(
                children: [
                  // 标题
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      '媒体资源库',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        shadows: [
                          Shadow(
                            offset: Offset(1, 1),
                            blurRadius: 3.0,
                            color: Colors.black.withOpacity(0.5),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Tab Bar
                  Container(
                    margin: EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.black26,
                      borderRadius: BorderRadius.circular(25),
                    ),
                    child: TabBar(
                      controller: _tabController,
                      indicator: BoxDecoration(
                        borderRadius: BorderRadius.circular(25),
                        color: Colors.white24,
                      ),
                      labelColor: Colors.white,
                      unselectedLabelColor: Colors.white70,
                      tabs: [
                        Tab(
                          icon: Icon(Icons.login),
                          text: '登录',
                        ),
                        Tab(
                          icon: Icon(Icons.folder),
                          text: '浏览',
                        ),
                        Tab(
                          icon: Icon(Icons.star),
                          text: '收藏',
                        ),
                      ],
                    ),
                  ),

                  // Tab Bar View
                  Expanded(
                    child: TabBarView(
                      controller: _tabController,
                      children: [
                        _buildLoginForm(),
                        _buildFileExplorer(),
                        _buildFavorites(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
