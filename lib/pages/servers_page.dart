import 'media_servers_page.dart';
import 'catalog_page.dart';
import 'downloads_page.dart';
import 'continue_watching_page.dart';
// lib/pages/servers_page.dart
import 'package:flutter/material.dart';
import '../models/server_config.dart';
import '../services/server_config_service.dart';
import 'browser_page.dart';
import 'package:uuid/uuid.dart';

class ServersPage extends StatefulWidget {
  const ServersPage({Key? key}) : super(key: key);

  @override
  State<ServersPage> createState() => _ServersPageState();
}

class _ServersPageState extends State<ServersPage> {
  final ServerConfigService _configService = ServerConfigService();
  List<ServerConfig> _servers = [];
  bool _isLoading = true;
  String? _activeConfigId;

  @override
  void initState() {
    super.initState();
    _loadServers();
  }

  Future<void> _loadServers() async {
    setState(() => _isLoading = true);
    try {
      final servers = await _configService.getAllConfigs();
      final activeId = await _configService.getActiveConfigId();
      setState(() {
        _servers = servers;
        _activeConfigId = activeId;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('加载服务器配置失败: $e');
    }
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

  Future<void> _addOrEditServer([ServerConfig? existing]) async {
    final result = await showDialog<ServerConfig>(
      context: context,
      builder: (context) => _ServerConfigDialog(existing: existing),
    );

    if (result != null) {
      try {
        await _configService.saveConfig(result);
        _showSuccess(existing == null ? '服务器添加成功' : '服务器更新成功');
        await _loadServers();
      } catch (e) {
        _showError('保存服务器配置失败: $e');
      }
    }
  }

  Future<void> _deleteServer(ServerConfig config) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除服务器 "${config.name}" 吗?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _configService.deleteConfig(config.id);
        _showSuccess('服务器已删除');
        await _loadServers();
      } catch (e) {
        _showError('删除服务器失败: $e');
      }
    }
  }

  Future<void> _connectToServer(ServerConfig config) async {
    // 设置为活动配置
    await _configService.setActiveConfigId(config.id);

    // 导航到文件浏览器
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => BrowserPage(serverConfig: config),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('媒体库'),
        actions: [IconButton(tooltip: 'Jellyfin / Emby', icon: const Icon(Icons.dns), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const MediaServersPage()))), IconButton(tooltip: '海报媒体库', icon: const Icon(Icons.movie_outlined), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const CatalogPage()))), IconButton(tooltip: '继续观看', icon: const Icon(Icons.play_circle_outline), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ContinueWatchingPage()))), IconButton(tooltip: '下载任务', icon: const Icon(Icons.download), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DownloadsPage())))],
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _servers.isEmpty
              ? _buildEmptyState()
              : _buildServerList(),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _addOrEditServer(),
        icon: const Icon(Icons.add),
        label: const Text('添加服务器'),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.storage_outlined, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            '还没有添加服务器',
            style: TextStyle(fontSize: 18, color: Colors.grey[600]),
          ),
          const SizedBox(height: 8),
          Text(
            '支持 SMB 和 WebDAV 协议(推荐WebDAV)',
            style: TextStyle(fontSize: 14, color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildServerList() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _servers.length,
      itemBuilder: (context, index) {
        final server = _servers[index];
        final isActive = server.id == _activeConfigId;

        return Card(
          elevation: 2,
          margin: const EdgeInsets.only(bottom: 12),
          child: InkWell(
            onTap: () => _connectToServer(server),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: isActive
                              ? Theme.of(context).primaryColor
                              : server.type == ServerType.smb
                                  ? Colors.blue[300]
                                  : Colors.purple[300],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          server.type == ServerType.smb
                              ? Icons.folder_shared
                              : Icons.cloud,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    server.name,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: server.type == ServerType.smb
                                        ? Colors.blue
                                        : Colors.purple,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    server.type == ServerType.smb ? 'SMB' : 'WebDAV',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                if (isActive) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Theme.of(context).primaryColor,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Text(
                                      '当前',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              server.type == ServerType.webdav
                                  ? server.webdavUrl
                                  : server.host,
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuButton<String>(
                        onSelected: (value) {
                          if (value == 'edit') {
                            _addOrEditServer(server);
                          } else if (value == 'delete') {
                            _deleteServer(server);
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(Icons.edit, size: 20),
                                SizedBox(width: 8),
                                Text('编辑'),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete, size: 20, color: Colors.red),
                                SizedBox(width: 8),
                                Text('删除', style: TextStyle(color: Colors.red)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(Icons.person, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(
                        server.username,
                        style: TextStyle(color: Colors.grey[700], fontSize: 12),
                      ),
                      const SizedBox(width: 16),
                      Icon(Icons.folder, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          server.initialPath,
                          style: TextStyle(color: Colors.grey[700], fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (server.lastConnected != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.access_time, size: 16, color: Colors.grey[600]),
                        const SizedBox(width: 4),
                        Text(
                          '最后连接: ${_formatDateTime(server.lastConnected!)}',
                          style: TextStyle(color: Colors.grey[600], fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  String _formatDateTime(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inMinutes < 1) {
      return '刚刚';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}分钟前';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}小时前';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}天前';
    } else {
      return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
    }
  }
}

// 服务器配置对话框
class _ServerConfigDialog extends StatefulWidget {
  final ServerConfig? existing;

  const _ServerConfigDialog({this.existing});

  @override
  State<_ServerConfigDialog> createState() => _ServerConfigDialogState();
}

class _ServerConfigDialogState extends State<_ServerConfigDialog> {
  late ServerType _serverType;
  late final TextEditingController _nameController;
  late final TextEditingController _hostController;
  late final TextEditingController _portController;
  late final TextEditingController _usernameController;
  late final TextEditingController _passwordController;
  late final TextEditingController _domainController;
  late final TextEditingController _initialPathController;
  bool _obscurePassword = true;
  bool _useHttps = false;

  // SMB高级选项
  bool _smbSigningRequired = false;
  bool _smbAnonymousLogin = false;
  bool _smbEncryption = false;
  bool _showAdvancedOptions = false;

  @override
  void initState() {
    super.initState();
    _serverType = widget.existing?.type ?? ServerType.smb;
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    _hostController = TextEditingController(text: widget.existing?.host ?? '');
    _portController = TextEditingController(
        text: widget.existing?.port?.toString() ?? '');
    _usernameController =
        TextEditingController(text: widget.existing?.username ?? '');
    _passwordController =
        TextEditingController(text: widget.existing?.password ?? '');
    _domainController =
        TextEditingController(text: widget.existing?.domain ?? '');
    _initialPathController =
        TextEditingController(text: widget.existing?.initialPath ?? '/');
    _useHttps = widget.existing?.useHttps ?? false;

    // 初始化SMB高级选项
    _smbSigningRequired = widget.existing?.smbSigningRequired ?? false;
    _smbAnonymousLogin = widget.existing?.smbAnonymousLogin ?? false;
    _smbEncryption = widget.existing?.smbEncryption ?? false;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _hostController.dispose();
    _portController.dispose();
    _usernameController.dispose();
    _passwordController.dispose();
    _domainController.dispose();
    _initialPathController.dispose();
    super.dispose();
  }

  void _save() {
    if (_nameController.text.trim().isEmpty ||
        _hostController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请填写服务器名称和主机地址'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // 如果不是匿名登录，检查用户名
    if (!_smbAnonymousLogin && _usernameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请填写用户名或启用匿名登录'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    int? port;
    if (_portController.text.trim().isNotEmpty) {
      port = int.tryParse(_portController.text.trim());
      if (port == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('端口号格式不正确'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    final config = ServerConfig(
      id: widget.existing?.id ?? const Uuid().v4(),
      name: _nameController.text.trim(),
      type: _serverType,
      host: _hostController.text.trim(),
      username: _smbAnonymousLogin ? 'guest' : _usernameController.text.trim(),
      password: _smbAnonymousLogin ? '' : _passwordController.text.trim(),
      domain: _domainController.text.trim(),
      initialPath: _initialPathController.text.trim(),
      createdAt: widget.existing?.createdAt ?? DateTime.now(),
      lastConnected: widget.existing?.lastConnected,
      port: port,
      useHttps: _useHttps,
      smbSigningRequired: _smbSigningRequired,
      smbAnonymousLogin: _smbAnonymousLogin,
      smbEncryption: _smbEncryption,
    );

    Navigator.pop(context, config);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? '添加服务器' : '编辑服务器'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 服务器类型选择
            if (widget.existing == null)
              SegmentedButton<ServerType>(
                segments: const [
                  ButtonSegment(
                    value: ServerType.smb,
                    label: Text('SMB'),
                    icon: Icon(Icons.folder_shared),
                  ),
                  ButtonSegment(
                    value: ServerType.webdav,
                    label: Text('WebDAV'),
                    icon: Icon(Icons.cloud),
                  ),
                ],
                selected: {_serverType},
                onSelectionChanged: (Set<ServerType> newSelection) {
                  setState(() => _serverType = newSelection.first);
                },
              ),
            const SizedBox(height: 12),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '服务器名称',
                hintText: '例如: 家庭NAS',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.label),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _hostController,
              decoration: InputDecoration(
                labelText: _serverType == ServerType.smb ? '主机地址' : '主机地址或URL',
                hintText: _serverType == ServerType.smb
                    ? '例如: 192.168.1.100'
                    : '例如: nas.example.com 或 192.168.1.100',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.computer),
              ),
            ),
            const SizedBox(height: 12),
            // WebDAV 特有字段
            if (_serverType == ServerType.webdav) ...[
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _portController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: '端口 (可选)',
                        hintText: 'HTTP:80 / HTTPS:443',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.numbers),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SwitchListTile(
                      title: const Text('HTTPS'),
                      value: _useHttps,
                      onChanged: (value) {
                        setState(() => _useHttps = value);
                      },
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _usernameController,
              decoration: const InputDecoration(
                labelText: '用户名',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.person),
              ),
              enabled: !_smbAnonymousLogin,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              decoration: InputDecoration(
                labelText: '密码',
                border: const OutlineInputBorder(),
                prefixIcon: const Icon(Icons.lock),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword ? Icons.visibility : Icons.visibility_off,
                  ),
                  onPressed: () {
                    setState(() => _obscurePassword = !_obscurePassword);
                  },
                ),
              ),
              enabled: !_smbAnonymousLogin,
            ),
            const SizedBox(height: 12),
            // SMB 特有字段
            if (_serverType == ServerType.smb) ...[
              TextField(
                controller: _domainController,
                decoration: const InputDecoration(
                  labelText: '域 (可选)',
                  hintText: 'WORKGROUP',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.domain),
                ),
              ),
              const SizedBox(height: 12),
              // SMB 高级选项折叠面板
              Card(
                elevation: 1,
                child: ExpansionTile(
                  leading: const Icon(Icons.settings_outlined, color: Colors.blue),
                  title: const Text(
                    'SMB 高级选项',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                  subtitle: Text(
                    _showAdvancedOptions ? '点击收起' : '点击展开',
                    style: const TextStyle(fontSize: 12),
                  ),
                  initiallyExpanded: _showAdvancedOptions,
                  onExpansionChanged: (expanded) {
                    setState(() => _showAdvancedOptions = expanded);
                  },
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Column(
                        children: [
                          SwitchListTile(
                            title: const Text('匿名登录'),
                            subtitle: const Text('使用访客模式连接'),
                            value: _smbAnonymousLogin,
                            onChanged: (value) {
                              setState(() => _smbAnonymousLogin = value);
                            },
                            activeColor: Colors.blue,
                          ),
                          const Divider(height: 1),
                          SwitchListTile(
                            title: const Text('要求签名'),
                            subtitle: const Text('启用SMB签名验证（推荐）'),
                            value: _smbSigningRequired,
                            onChanged: (value) {
                              setState(() => _smbSigningRequired = value);
                            },
                            activeColor: Colors.blue,
                          ),
                          const Divider(height: 1),
                          SwitchListTile(
                            title: const Text('启用加密'),
                            subtitle: const Text('使用SMB3加密传输'),
                            value: _smbEncryption,
                            onChanged: (value) {
                              setState(() => _smbEncryption = value);
                            },
                            activeColor: Colors.blue,
                          ),
                          const SizedBox(height: 8),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.blue.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.info_outline, size: 18, color: Colors.blue),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '提示：某些服务器可能需要特定配置才能连接',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.blue.shade700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _initialPathController,
              decoration: const InputDecoration(
                labelText: '初始路径',
                hintText: '/(根目录可能不受支持)',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.folder),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        ElevatedButton(
          onPressed: _save,
          child: const Text('保存'),
        ),
      ],
    );
  }
}
