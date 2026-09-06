import '../services/media_server_client.dart';
import '../widgets/media_source_card.dart';
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
  List<MediaServerConnection> _mediaServers = [];
  bool _isLoading = true;
  String? _activeConfigId, _error;

  @override
  void initState() {
    super.initState();
    _loadServers();
  }

  Future<void> _loadServers() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final servers = await _configService.getAllConfigs();
      final media = await MediaServerStore.load();
      final active = await _configService.getActiveConfigId();
      if (mounted)
        setState(() {
          _servers = servers;
          _mediaServers = media;
          _activeConfigId = active;
        });
    } catch (_) {
      if (mounted) setState(() => _error = '暂时无法读取媒体来源，请重试');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showError(String text) {
    if (mounted)
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _addFileServer(
      {ServerConfig? existing, ServerType type = ServerType.webdav}) async {
    final result = await showDialog<ServerConfig>(
        context: context,
        builder: (_) =>
            _ServerConfigDialog(existing: existing, initialType: type));
    if (result == null) return;
    try {
      await _configService.saveConfig(result);
      await _loadServers();
    } catch (_) {
      _showError('保存失败，请检查存储权限后重试');
    }
  }

  Future<void> _addMediaServer(
      {MediaServerConnection? existing, String kind = 'Jellyfin'}) async {
    final result =
        await showMediaServerLogin(context, existing: existing, kind: kind);
    if (result == null) return;
    try {
      await MediaServerStore.save(result);
      await _loadServers();
    } catch (_) {
      _showError('保存媒体服务器失败，请重试');
    }
  }

  Future<void> _remove(String name, Future<void> Function() remove) async {
    final yes = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: const Text('移除媒体来源？'),
                content: Text('从 AloePlayer 移除“$name”，服务器上的文件会保留。'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('取消')),
                  FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('移除'))
                ]));
    if (yes != true) return;
    try {
      await remove();
      await _loadServers();
    } catch (_) {
      _showError('移除失败，请重试');
    }
  }

  Future<void> _connect(ServerConfig server) async {
    try {
      await _configService.setActiveConfigId(server.id);
      if (!mounted) return;
      setState(() => _activeConfigId = server.id);
      await Navigator.push(context,
          MaterialPageRoute(builder: (_) => BrowserPage(serverConfig: server)));
    } catch (_) {
      _showError('无法打开此来源，请检查配置');
    }
  }

  Future<void> _chooseSource() async {
    final kind = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        constraints: const BoxConstraints(maxWidth: 620),
        builder: (ctx) => SafeArea(
            child: SingleChildScrollView(
                child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('添加媒体来源',
                              style: Theme.of(ctx).textTheme.headlineSmall),
                          const SizedBox(height: 8),
                          const Text('连接家中的 NAS，或登录自己的影视服务器。'),
                          const SizedBox(height: 20),
                          for (final source in _sourceTypes)
                            ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 6),
                                leading: Icon(source.icon),
                                title: Text(source.name),
                                subtitle: Text(source.description),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () => Navigator.pop(ctx, source.name)),
                        ])))));
    if (!mounted || kind == null) return;
    if (kind == 'SMB' || kind == 'WebDAV')
      await _addFileServer(
          type: kind == 'SMB' ? ServerType.smb : ServerType.webdav);
    else
      await _addMediaServer(kind: kind);
  }

  static const _sourceTypes = [
    (name: 'WebDAV', description: 'NAS、网盘与远程文件夹', icon: Icons.cloud_outlined),
    (name: 'SMB', description: '局域网共享文件夹', icon: Icons.folder_shared_outlined),
    (
      name: 'Jellyfin',
      description: '海报、分类与观看进度',
      icon: Icons.video_library_outlined
    ),
    (name: 'Emby', description: '连接个人影视媒体库', icon: Icons.movie_filter_outlined),
  ];
  Widget _quickAction(IconData icon, String title, Widget page) => SizedBox(width: 90, child: TextButton(
      style: TextButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest.withValues(alpha: .8),
        foregroundColor: Theme.of(context).colorScheme.primary,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22))),
      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => page)),
      child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(icon, size: 24), const SizedBox(height: 7),
        Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))])));
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = Theme.of(context).colorScheme;
    final cards = <Widget>[
      for (final server in _servers)
        MediaSourceCard(
            name: server.name,
            address:
                '${server.host}${server.initialPath == '/' ? '' : server.initialPath}',
            protocol: server.type == ServerType.smb ? 'SMB' : 'WebDAV',
            icon: server.type == ServerType.smb
                ? Icons.folder_shared_outlined
                : Icons.cloud_outlined,
            active: server.id == _activeConfigId,
            onOpen: () => _connect(server),
            onEdit: () => _addFileServer(existing: server),
            onRemove: () => _remove(
                server.name, () => _configService.deleteConfig(server.id))),
      for (final server in _mediaServers)
        MediaSourceCard(
            name: server.name,
            address: server.url,
            protocol: server.kind,
            icon: Icons.video_library_outlined,
            onOpen: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => MediaServerBrowser(connection: server))),
            onEdit: () => _addMediaServer(existing: server),
            onRemove: () =>
                _remove(server.name, () => MediaServerStore.remove(server.id))),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('媒体库'), actions: [
        IconButton(
            tooltip: '刷新媒体来源',
            onPressed: _isLoading ? null : _loadServers,
            icon: const Icon(Icons.refresh_rounded))
      ]),
      body: RefreshIndicator(
          onRefresh: _loadServers,
          child: LayoutBuilder(builder: (context, constraints) {
            final inset = constraints.maxWidth < 600 ? 16.0 : 32.0;
            return ListView(
                padding: EdgeInsets.fromLTRB(inset, 8, inset, 100),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  Center(
                      child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1200),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                    width: double.infinity,
                                    padding: const EdgeInsets.all(24),
                                    decoration: BoxDecoration(
                                        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                                          colors: theme.brightness == Brightness.dark
                                            ? const [Color(0xFF123C71), Color(0xFF24254F), Color(0xFF163D49)]
                                            : const [Color(0xFFD6EDFF), Color(0xFFEEE8FF), Color(0xFFDAF8F4)]),
                                        border: Border.all(color: Colors.white.withValues(alpha: theme.brightness == Brightness.dark ? .12 : .9)),
                                        boxShadow: [BoxShadow(color: colors.primary.withValues(alpha: .07), blurRadius: 28, offset: const Offset(0, 8))],
                                        borderRadius:
                                            BorderRadius.circular(30)),
                                    child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text('我的媒体空间',
                                              style: theme
                                                  .textTheme.headlineSmall
                                                  ?.copyWith(
                                                      fontWeight:
                                                          FontWeight.w700)),
                                          const SizedBox(height: 10),
                                          Text('本地收藏与远程片库，都在这里。',
                                              style: theme.textTheme.bodyMedium
                                                  ?.copyWith(
                                                      color: colors
                                                          .onSurfaceVariant)),
                                          const SizedBox(height: 20),
                                          Wrap(
                                              spacing: 10,
                                              runSpacing: 10,
                                              children: [
                                                _quickAction(
                                                    Icons.play_circle_outline,
                                                    '继续观看',
                                                    const ContinueWatchingPage()),
                                                _quickAction(
                                                    Icons.movie_outlined,
                              '海报库',
                                                    const CatalogPage()),
                                                _quickAction(
                                                    Icons.download_outlined,
                                                    '下载任务',
                                                    const DownloadsPage()),
                                              ]),
                                        ])),
                                const SizedBox(height: 28),
                                Wrap(
                                    alignment: WrapAlignment.spaceBetween,
                                    spacing: 16,
                                    runSpacing: 12,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    children: [
                                      Text(
                                          '媒体来源${cards.isEmpty ? '' : ' · ${cards.length}'}',
                                          style: theme.textTheme.titleLarge
                                              ?.copyWith(
                                                  fontWeight: FontWeight.w700)),
                                      FilledButton.icon(
                                          onPressed: _chooseSource,
                                          icon: const Icon(Icons.add),
                                          label: const Text('添加来源')),
                                    ]),
                                const SizedBox(height: 16),
                                if (_isLoading) const LinearProgressIndicator(),
                                if (_error != null)
                                  Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 16),
                                      child: Text(_error!,
                                          style:
                                              TextStyle(color: colors.error))),
                                if (!_isLoading &&
                                    _error == null &&
                                    cards.isEmpty)
                                  Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 16),
                                      child: Text('还没有连接媒体来源。选择一种方式开始：',
                                          style: theme.textTheme.bodyMedium)),
                                LayoutBuilder(builder: (_, box) {
                                  final columns = box.maxWidth >= 1000
                                      ? 3
                                      : box.maxWidth >= 650
                                          ? 2
                                          : 1;
                                  final width =
                                      (box.maxWidth - 16 * (columns - 1)) /
                                          columns;
                                  return Wrap(
                                      spacing: 16,
                                      runSpacing: 16,
                                      children: [
                                        for (final card in cards)
                                          SizedBox(width: width, child: card),
                                        if (!_isLoading &&
                                            _error == null &&
                                            cards.isEmpty)
                                          for (final source in _sourceTypes)
                                            SizedBox(
                                                width: width,
                                                child: MediaSourceCard(
                                                    name: '添加 ${source.name}',
                                                    address: source.description,
                                                    protocol: source.name,
                                                    icon: source.icon,
                                                    onOpen: () {
                                                      if (source.name ==
                                                              'SMB' ||
                                                          source.name ==
                                                              'WebDAV')
                                                        _addFileServer(
                                                            type: source.name ==
                                                                    'SMB'
                                                                ? ServerType.smb
                                                                : ServerType
                                                                    .webdav);
                                                      else
                                                        _addMediaServer(
                                                            kind: source.name);
                                                    })),
                                      ]);
                                }),
                                if (cards.isNotEmpty)
                                  Padding(
                                      padding: const EdgeInsets.only(top: 20),
                                      child: Text(
                                          '支持 WebDAV、SMB、Jellyfin 和 Emby',
                                          style: theme.textTheme.bodySmall
                                              ?.copyWith(
                                                  color: colors
                                                      .onSurfaceVariant))),
                              ]))),
                ]);
          })),
    );
  }
}

// 服务器配置对话框
class _ServerConfigDialog extends StatefulWidget {
  final ServerConfig? existing;

  final ServerType initialType;
  const _ServerConfigDialog(
      {this.existing, this.initialType = ServerType.webdav});

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
    _serverType = widget.existing?.type ?? widget.initialType;
    _nameController = TextEditingController(text: widget.existing?.name ?? '');
    _hostController = TextEditingController(text: widget.existing?.host ?? '');
    _portController =
        TextEditingController(text: widget.existing?.port?.toString() ?? '');
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
                  leading:
                      const Icon(Icons.settings_outlined, color: Colors.blue),
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
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
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
                                const Icon(Icons.info_outline,
                                    size: 18, color: Colors.blue),
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
