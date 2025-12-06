// lib/pages/smb_browser_page.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../libsmb2_service/smb_file.dart';
import '../services/smb_service.dart';
import '../services/http_service.dart';

class SmbBrowserPage extends StatefulWidget {
  const SmbBrowserPage({Key? key}) : super(key: key);

  @override
  State<SmbBrowserPage> createState() => _SmbBrowserPageState();
}

class _SmbBrowserPageState extends State<SmbBrowserPage> {
  final SmbService _smbService = SmbService();
  final HttpService _httpService = HttpService.instance;
  
  final _hostController = TextEditingController();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _domainController = TextEditingController();

  bool _isLoading = false;
  bool _isConnected = false;
  bool _rememberCredentials = true;
  
  List<SmbFile> _currentFiles = [];
  String _currentPath = '/';

  @override
  void initState() {
    super.initState();
    _loadSavedCredentials();
    _httpService.startServer();
  }

  @override
  void dispose() {
    _smbService.disconnect();
    _hostController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _domainController.dispose();
    super.dispose();
  }

  // 加载保存的登录信息
  Future<void> _loadSavedCredentials() async {
    final credentials = await _smbService.getSavedCredentials();
    setState(() {
      _hostController.text = credentials['host']!;
      _usernameController.text = credentials['username']!;
      _passwordController.text = credentials['password']!;
      _domainController.text = credentials['domain']!;
    });
  }

  // 连接SMB
  Future<void> _connectSmb() async {
    if (_hostController.text.isEmpty || _usernameController.text.isEmpty) {
      _showError('请填写主机地址和用户名');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final success = await _smbService.connect(
        host: _hostController.text.trim(),
        username: _usernameController.text.trim(),
        password: _passwordController.text.trim(),
        domain: _domainController.text.trim(),
      );

      if (success) {
        if (_rememberCredentials) {
          await _smbService.saveCredentials(
            host: _hostController.text.trim(),
            username: _usernameController.text.trim(),
            password: _passwordController.text.trim(),
            domain: _domainController.text.trim(),
          );
        }

        setState(() => _isConnected = true);

        // 将SMB服务实例传递给HTTP服务
        _httpService.setSmbService(_smbService);

        await _loadFiles('/Bangumi');
        _showSuccess('连接成功');
      } else {
        _showError('连接失败，请检查登录信息');
      }
    } catch (e) {
      _showError('连接失败: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // 断开连接
  Future<void> _disconnect() async {
    await _smbService.disconnect();
    setState(() {
      _isConnected = false;
      _currentFiles.clear();
      _currentPath = '/';
    });
  }

  // 加载文件列表
  Future<void> _loadFiles(String path) async {
    if (!_smbService.isConnected) return;

    setState(() => _isLoading = true);

    try {
      final files = await _smbService.listFiles(path);
      setState(() {
        _currentFiles = files;
        _currentPath = path;
      });
    } catch (e) {
      _showError('加载文件失败: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

 // 处理文件点击 - 修改这个方法
  void _onFileSelected(SmbFile file) {
    if (file.isDirectory()) {
      _loadFiles(file.path);
    } else {
      // 生成HTTP链接并显示所有可用地址
      final httpUrl = _httpService.getFileUrl(file.path);
      final accessUrls = _httpService.getAccessUrls();
      
      // 复制主要链接到剪贴板
      Clipboard.setData(ClipboardData(text: httpUrl));
      
      // 显示所有可用的访问地址
      _showFileUrlDialog(file, accessUrls);
    }
  }

  // 显示文件URL对话框
  void _showFileUrlDialog(SmbFile file, List<String> accessUrls) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('文件链接已生成'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('文件: ${file.name}'),
            const SizedBox(height: 16),
            const Text('可用访问地址:', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...accessUrls.map((baseUrl) {
              final cleanPath = file.path.startsWith('/') ? file.path.substring(1) : file.path;
              final fullUrl = '$baseUrl/file/$cleanPath';
              final isLocal = baseUrl.contains('localhost');
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isLocal ? '本机访问:' : '局域网访问:',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(height: 4),
                    SelectableText(
                      fullUrl,
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () {
                            Clipboard.setData(ClipboardData(text: fullUrl));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('链接已复制到剪贴板')),
                            );
                          },
                          child: const Text('复制'),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }).toList(),
            const SizedBox(height: 8),
            const Text(
              '提示: 局域网内的其他设备可以使用局域网访问地址来访问此文件',
              style: TextStyle(fontSize: 12, color: Colors.orange),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }


  // 返回上级目录
  void _goBack() {
    if (_currentPath == '/' || _currentPath.isEmpty) return;
    
    final parentPath = _currentPath.substring(0, _currentPath.lastIndexOf('/'));
    _loadFiles(parentPath.isEmpty ? '/' : parentPath);
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.green),
    );
  }

  void _showDialog(String title, String content) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SMB文件浏览器'),
        actions: [
          if (_isConnected)
            IconButton(
              icon: const Icon(Icons.logout),
              onPressed: _disconnect,
              tooltip: '断开连接',
            ),
        ],
      ),
      body: Column(
        children: [
          if (!_isConnected) _buildLoginForm(),
          if (_isConnected) _buildFileExplorer(),
        ],
      ),
    );
  }

  Widget _buildLoginForm() {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'SMB服务器登录',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _hostController,
              decoration: const InputDecoration(
                labelText: '主机地址',
                hintText: '例如: 192.168.1.100',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: '用户名',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: '密码',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _domainController,
              decoration: const InputDecoration(
                labelText: '域 (可选)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            CheckboxListTile(
              title: const Text('记住登录信息'),
              value: _rememberCredentials,
              onChanged: (value) {
                setState(() => _rememberCredentials = value ?? true);
              },
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _isLoading ? null : _connectSmb,
              child: _isLoading
                  ? const CircularProgressIndicator()
                  : const Text('连接'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileExplorer() {
    return Expanded(
      child: Column(
        children: [
          // 当前路径和返回按钮
          Container(
            padding: const EdgeInsets.all(8),
            color: Colors.grey[100],
            child: Row(
              children: [
                if (_currentPath != '/')
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    onPressed: _goBack,
                  ),
                Expanded(
                  child: Text(
                    '当前路径: $_currentPath',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
                Text(
                  'HTTP服务: ${_httpService.isRunning ? "运行中" : "已停止"}',
                  style: TextStyle(
                    color: _httpService.isRunning ? Colors.green : Colors.red,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          // 文件列表
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : ListView.builder(
                    itemCount: _currentFiles.length,
                    itemBuilder: (context, index) {
                      final file = _currentFiles[index];
                      return ListTile(
                        leading: Icon(
                          file.isDirectory() ? Icons.folder : Icons.insert_drive_file,
                          color: file.isDirectory() ? Colors.blue : Colors.grey,
                        ),
                        title: Text(file.name),
                        subtitle: file.isDirectory() 
                            ? const Text('文件夹')
                            : Text('文件 • }'),
                        onTap: () => _onFileSelected(file),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }
}