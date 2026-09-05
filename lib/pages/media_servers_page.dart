import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../services/media_server_client.dart';
import '../mpvplayer.dart';

String _serverError(Object error) {
  if (error is DioException) {
    if (error.response?.statusCode == 401 || error.response?.statusCode == 403) return '登录失败或会话已过期，请检查账户并重新登录';
    return '服务器连接失败，请检查地址、网络和证书';
  }
  return error.toString();
}
class MediaServersPage extends StatefulWidget {
  const MediaServersPage({super.key});
  @override State<MediaServersPage> createState() => _MediaServersPageState();
}
class _MediaServersPageState extends State<MediaServersPage> {
  List<MediaServerConnection> _connections = [];
  String? _error;
  @override void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try { final list = await MediaServerStore.load(); if (mounted) setState(() { _connections = list; _error = null; }); }
    catch (e) { if (mounted) setState(() => _error = _serverError(e)); }
  }
  Future<void> _login([MediaServerConnection? connection]) async {
    final result = await showDialog<MediaServerConnection>(context: context, builder: (_) => _LoginDialog(existing: connection));
    if (result == null) return;
    try { await MediaServerStore.save(result); await _load(); }
    catch (e) { if (mounted) setState(() => _error = _serverError(e)); }
  }
  @override Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Jellyfin / Emby')),
    floatingActionButton: FloatingActionButton.extended(onPressed: _login, label: const Text('添加媒体服务器'), icon: const Icon(Icons.add)),
    body: Column(children: [if (_error != null) Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
      Expanded(child: _connections.isEmpty ? const Center(child: Text('添加自己的 Jellyfin 或 Emby 服务器')) : ListView.builder(itemCount: _connections.length, itemBuilder: (_, index) {
        final connection = _connections[index];
        return ListTile(leading: const Icon(Icons.dns_outlined), title: Text(connection.name), subtitle: Text(connection.url),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MediaServerBrowser(connection: connection))),
          trailing: PopupMenuButton<String>(onSelected: (value) async {
            if (value == 'login') { await _login(connection); }
            if (value == 'remove') {
              final remove = await showDialog<bool>(context: context, builder: (context) => AlertDialog(title: const Text('移除服务器？'), content: Text(connection.name), actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')), TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('移除'))]));
              if (remove == true) { await MediaServerStore.remove(connection.id); await _load(); }
            }
          }, itemBuilder: (_) => const [PopupMenuItem(value: 'login', child: Text('重新登录 / 编辑')), PopupMenuItem(value: 'remove', child: Text('移除'))]));
      })),
    ]));
}
class _LoginDialog extends StatefulWidget {
  final MediaServerConnection? existing;
  const _LoginDialog({this.existing});
  @override State<_LoginDialog> createState() => _LoginDialogState();
}
class _LoginDialogState extends State<_LoginDialog> {
  late final TextEditingController _url = TextEditingController(text: widget.existing?.url ?? '');
  late final TextEditingController _user = TextEditingController(text: widget.existing?.username ?? '');
  final _password = TextEditingController();
  late String _kind = widget.existing?.kind ?? 'Jellyfin';
  bool _busy = false;
  String? _error;
  @override void dispose() { _url.dispose(); _user.dispose(); _password.dispose(); super.dispose(); }
  Future<void> _login() async {
    setState(() { _busy = true; _error = null; });
    try {
      final result = await MediaServerClient.login(url: _url.text, username: _user.text.trim(), password: _password.text, kind: _kind, id: widget.existing?.id);
      if (mounted) Navigator.pop(context, result);
    } catch (e) { if (mounted) setState(() { _busy = false; _error = _serverError(e); }); }
  }
  @override Widget build(BuildContext context) => AlertDialog(title: const Text('登录媒体服务器'), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
    DropdownButtonFormField<String>(initialValue: _kind, items: ['Jellyfin', 'Emby'].map((k) => DropdownMenuItem(value: k, child: Text(k))).toList(), onChanged: _busy ? null : (value) => setState(() => _kind = value!)),
    TextField(controller: _url, enabled: !_busy, decoration: const InputDecoration(labelText: '服务器地址', hintText: 'https://server.example.com')),
    TextField(controller: _user, enabled: !_busy, decoration: const InputDecoration(labelText: '用户名')),
    TextField(controller: _password, enabled: !_busy, obscureText: true, decoration: const InputDecoration(labelText: '密码')),
    if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red)),
    if (_busy) const LinearProgressIndicator(),
  ])), actions: [TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('取消')), FilledButton(onPressed: _busy ? null : _login, child: const Text('登录'))]);
}
class MediaServerBrowser extends StatefulWidget {
  final MediaServerConnection connection;
  const MediaServerBrowser({super.key, required this.connection});
  @override State<MediaServerBrowser> createState() => _MediaServerBrowserState();
}
class _MediaServerBrowserState extends State<MediaServerBrowser> {
  late final MediaServerClient _client = MediaServerClient(widget.connection);
  final List<String> _parents = [];
  List<MediaServerItem> _items = [];
  String _search = '';
  bool _busy = false, _more = true;
  String? _error;
  @override void initState() { super.initState(); _load(); }
  @override void dispose() { _client.close(); super.dispose(); }
  Future<void> _load({bool more = false}) async {
    if (_busy) return;
    setState(() { _busy = true; _error = null; });
    try {
      final items = await _client.items(parent: _parents.lastOrNull, search: _search, start: more ? _items.length : 0);
      if (mounted) setState(() { _items = more ? [..._items, ...items] : items; _more = items.length == 100; });
    } catch (e) { if (mounted) setState(() => _error = _serverError(e)); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  Future<void> _open(MediaServerItem item) async {
    if (_busy) return;
    if (item.isFolder) { _parents.add(item.id); _search = ''; await _load(); return; }
    if (!['Movie', 'Episode', 'Video', 'MusicVideo', 'Audio'].contains(item.type)) {
      setState(() => _error = '此项目不是可直接播放的音视频'); return;
    }
    setState(() => _busy = true);
    try {
      final media = await _client.playback(item);
      if (!mounted) return;
      await Navigator.push(context, MaterialPageRoute(builder: (_) => MPVPlayer(filePath: media.url, mediaQueue: [media], onPlayback: _client.report)));
    } catch (e) { if (mounted) setState(() => _error = _serverError(e)); }
    finally { if (mounted) setState(() => _busy = false); }
  }
  @override Widget build(BuildContext context) => PopScope(canPop: _parents.isEmpty,
    onPopInvokedWithResult: (didPop, _) { if (!didPop && !_busy && _parents.isNotEmpty) { _parents.removeLast(); _load(); } },
    child: Scaffold(appBar: AppBar(title: Text(widget.connection.name), actions: [IconButton(onPressed: _busy ? null : _load, icon: const Icon(Icons.refresh))]),
      body: Column(children: [Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: TextField(decoration: const InputDecoration(hintText: '搜索媒体，回车确认', prefixIcon: Icon(Icons.search)), onSubmitted: (text) { _search = text.trim(); _load(); })),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null) Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
        Expanded(child: GridView.builder(padding: const EdgeInsets.all(12), gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 190, childAspectRatio: 0.65, crossAxisSpacing: 10, mainAxisSpacing: 10), itemCount: _items.length, itemBuilder: (_, index) {
          final item = _items[index];
          return Card(clipBehavior: Clip.antiAlias, child: InkWell(onTap: () => _open(item), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: Image.network(_client.imageUrl(item.id), headers: _client.headers, cacheWidth: 360, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Icon(item.isFolder ? Icons.folder : Icons.movie_outlined, size: 48))),
            Padding(padding: const EdgeInsets.all(8), child: Text(item.name, maxLines: 2, overflow: TextOverflow.ellipsis)),
            if (item.resumeMs > 0) Padding(padding: const EdgeInsets.only(left: 8, bottom: 8), child: Text('续播 ${(item.resumeMs / 60000).floor()} 分钟', style: Theme.of(context).textTheme.bodySmall)),
          ])));
        })),
        if (_more && _items.isNotEmpty) TextButton(onPressed: _busy ? null : () => _load(more: true), child: const Text('加载更多')),
      ])));
}
