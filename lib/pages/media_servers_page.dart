import 'dart:async';
import '../services/media_server_browser.dart';
import '../services/media_server_query.dart';
import '../widgets/media_server_filter_dialog.dart';
import '../services/member_access.dart';
import '../widgets/member_feature_prompt.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../services/media_server_client.dart';
import 'media_server_home_page.dart';
import 'media_server_detail_page.dart';
import '../services/media_server_catalog.dart';

String _serverError(Object error) {
  if (error is DioException) {
    if (error.response?.statusCode == 401 ||
        error.response?.statusCode == 403) {
      return '登录失败或会话已过期，请检查账户并重新登录';
    }
    return '服务器连接失败，请检查地址、网络和证书';
  }
  return error.toString();
}

class MediaServersPage extends StatefulWidget {
  const MediaServersPage({super.key});
  @override
  State<MediaServersPage> createState() => _MediaServersPageState();
}

class _MediaServersPageState extends State<MediaServersPage> {
  List<MediaServerConnection> _connections = [];
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await MediaServerStore.load();
      if (mounted)
        setState(() {
          _connections = list;
          _error = null;
        });
    } catch (e) {
      if (mounted) setState(() => _error = _serverError(e));
    }
  }

  Future<void> _login([MediaServerConnection? connection]) async {
    final result = await showMediaServerLogin(context, existing: connection);
    if (result == null) return;
    try {
      await MediaServerStore.save(result);
      await _load();
    } catch (e) {
      if (mounted) setState(() => _error = _serverError(e));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Jellyfin / Emby')),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: _login,
          label: const Text('添加媒体服务器'),
          icon: const Icon(Icons.add)),
      body: Column(children: [
        if (_error != null)
          Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
        Expanded(
            child: _connections.isEmpty
                ? const Center(child: Text('添加自己的 Jellyfin 或 Emby 服务器'))
                : ListView.builder(
                    itemCount: _connections.length,
                    itemBuilder: (_, index) {
                      final connection = _connections[index];
                      return ListTile(
                          leading: const Icon(Icons.dns_outlined),
                          title: Text(connection.name),
                          subtitle: Text(connection.url),
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => MediaServerHomePage(
                                      connection: connection))),
                          trailing: PopupMenuButton<String>(
                              onSelected: (value) async {
                                if (value == 'login') {
                                  await _login(connection);
                                }
                                if (value == 'remove') {
                                  if (!context.mounted) return;
                                  final remove = await showDialog<bool>(
                                      context: context,
                                      builder: (context) => AlertDialog(
                                              title: const Text('移除服务器？'),
                                              content: Text(connection.name),
                                              actions: [
                                                TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                            context, false),
                                                    child: const Text('取消')),
                                                TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                            context, true),
                                                    child: const Text('移除'))
                                              ]));
                                  if (remove == true) {
                                    await MediaServerStore.remove(
                                        connection.id);
                                    await _load();
                                  }
                                }
                              },
                              itemBuilder: (_) => const [
                                    PopupMenuItem(
                                        value: 'login',
                                        child: Text('重新登录 / 编辑')),
                                    PopupMenuItem(
                                        value: 'remove', child: Text('移除'))
                                  ]));
                    })),
      ]));
}

Future<MediaServerConnection?> showMediaServerLogin(BuildContext context,
        {MediaServerConnection? existing, String kind = 'Jellyfin'}) =>
    showDialog<MediaServerConnection>(
        context: context,
        builder: (_) => _LoginDialog(existing: existing, kind: kind));

class _LoginDialog extends StatefulWidget {
  final MediaServerConnection? existing;
  final String kind;
  const _LoginDialog({this.existing, this.kind = 'Jellyfin'});
  @override
  State<_LoginDialog> createState() => _LoginDialogState();
}

class _LoginDialogState extends State<_LoginDialog> {
  late final TextEditingController _url =
      TextEditingController(text: widget.existing?.url ?? '');
  late final TextEditingController _user =
      TextEditingController(text: widget.existing?.username ?? '');
  final _password = TextEditingController();
  late String _kind = widget.existing?.kind ?? widget.kind;
  bool _busy = false;
  String? _error;
  @override
  void dispose() {
    _url.dispose();
    _user.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!await MemberAccess.instance
          .canAddSource(kind: _kind, existingId: widget.existing?.id)) {
        if (!mounted) return;
        if (!await requestMemberFeature(
            context, MemberFeature.multipleSources)) {
          if (mounted) setState(() => _busy = false);
          return;
        }
      }
      if (!mounted) return;
      final result = await MediaServerClient.login(
          url: _url.text,
          username: _user.text.trim(),
          password: _password.text,
          kind: _kind,
          id: widget.existing?.id);
      if (mounted) Navigator.pop(context, result);
    } catch (e) {
      if (mounted)
        setState(() {
          _busy = false;
          _error = _serverError(e);
        });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('登录媒体服务器'),
          content: SingleChildScrollView(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('免费版可添加 1 个 Jellyfin 和 1 个 Emby，已有来源继续保留。'),
            DropdownButtonFormField<String>(
                initialValue: _kind,
                items: ['Jellyfin', 'Emby']
                    .map((k) => DropdownMenuItem(value: k, child: Text(k)))
                    .toList(),
                onChanged:
                    _busy ? null : (value) => setState(() => _kind = value!)),
            TextField(
                controller: _url,
                enabled: !_busy,
                decoration: const InputDecoration(
                    labelText: '服务器地址',
                    hintText: 'https://server.example.com')),
            TextField(
                controller: _user,
                enabled: !_busy,
                decoration: const InputDecoration(labelText: '用户名')),
            TextField(
                controller: _password,
                enabled: !_busy,
                obscureText: true,
                decoration: const InputDecoration(labelText: '密码')),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            if (_busy) const LinearProgressIndicator(),
          ])),
          actions: [
            TextButton(
                onPressed: _busy ? null : () => Navigator.pop(context),
                child: const Text('取消')),
            FilledButton(
                onPressed: _busy ? null : _login, child: const Text('登录'))
          ]);
}

class MediaServerBrowser extends StatefulWidget {
  final MediaServerConnection connection;
  final MediaServerClient? client;
  final MediaServerItem? initialParent;
  const MediaServerBrowser(
      {super.key, required this.connection, this.client, this.initialParent});
  @override
  State<MediaServerBrowser> createState() => _MediaServerBrowserState();
}

class _MediaServerBrowserState extends State<MediaServerBrowser> {
  late final MediaServerClient _client =
      widget.client ?? MediaServerClient(widget.connection);
  late final MediaServerBrowserController _browser =
      MediaServerBrowserController(_client);
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _searchDelay;
  bool _playing = false;
  int _interactionGeneration = 0;
  CancelToken? _itemRefreshCancel;
  String? _playError;
  @override
  void initState() {
    super.initState();
    _browser.addListener(_changed);
    _scroll.addListener(_nearEnd);
    if (widget.initialParent != null)
      _browser.parents.add(widget.initialParent!);
    _browser.load();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _nearEnd() {
    if (_scroll.hasClients &&
        _scroll.position.extentAfter < 500 &&
        _browser.error == null) _browser.load(more: true);
  }

  @override
  void dispose() {
    _cancelPlayback();
    _searchDelay?.cancel();
    _browser.removeListener(_changed);
    _browser.dispose();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _query(String text, {bool now = false}) {
    _cancelPlayback();
    setState(() {});
    _searchDelay?.cancel();
    if (now) {
      _browser.query(text);
    } else {
      _searchDelay =
          Timer(const Duration(milliseconds: 300), () => _browser.query(text));
    }
  }

  void _back() {
    _cancelPlayback();
    _searchDelay?.cancel();
    _search.clear();
    _browser.back();
  }

  Future<void> _filter() async {
    _searchDelay?.cancel();
    final selected = await showDialog<MediaServerQuery>(
        context: context,
        builder: (_) => MediaServerFilterDialog(initial: _browser.filters));
    if (!mounted) return;
    if (selected == null) {
      if (_browser.search != _search.text.trim())
        _query(_search.text, now: true);
      return;
    }
    await _applyFilters(selected);
  }

  Future<void> _applyFilters(MediaServerQuery selected) async {
    _cancelPlayback();
    _searchDelay?.cancel();
    _browser.search = _search.text.trim();
    if (_scroll.hasClients) _scroll.jumpTo(0);
    await _browser.setFilters(selected);
  }

  void _cancelPlayback() {
    _interactionGeneration++;
    _itemRefreshCancel?.cancel('Browser interaction changed');
    _playing = false;
    _playError = null;
  }

  Future<void> _open(MediaServerItem item) async {
    if (_playing) return;
    if (item.isFolder && !['Series', 'Season'].contains(item.type)) {
      _cancelPlayback();
      _searchDelay?.cancel();
      _search.clear();
      await _browser.enter(item);
      return;
    }
    setState(() {
      _playing = true;
      _playError = null;
    });
    final generation = ++_interactionGeneration;
    try {
      _searchDelay?.cancel();
      await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => MediaServerDetailPage(
                  connection: widget.connection, item: item)));
      if (!mounted || generation != _interactionGeneration) return;
      // Refresh only the changed tile; keep the large library and scroll position.
      final cancel = _itemRefreshCancel = CancelToken();
      final updated = await _client.details(item.id, cancelToken: cancel);
      if (mounted && generation == _interactionGeneration)
        _browser.updateItem(updated);
    } catch (e) {
      if (mounted && generation == _interactionGeneration) {
        setState(() => _playError = _serverError(e));
      }
    } finally {
      if (mounted && generation == _interactionGeneration) {
        setState(() => _playing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: _browser.parents.length <= (widget.initialParent == null ? 0 : 1),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _browser.parents.isNotEmpty) _back();
      },
      child: Scaffold(
          appBar: AppBar(
              title: Text(
                  _browser.parents.lastOrNull?.name ?? widget.connection.name),
              actions: [
                IconButton(
                    tooltip: '筛选与排序',
                    onPressed: _playing ? null : _filter,
                    icon: Icon(Icons.filter_list,
                        color: _browser.filters.changed
                            ? Theme.of(context).colorScheme.primary
                            : null)),
                IconButton(
                    tooltip: '刷新媒体',
                    onPressed: _playing ? null : () => _browser.load(),
                    icon: const Icon(Icons.refresh))
              ]),
          body: Column(children: [
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                    controller: _search,
                    decoration: InputDecoration(
                        hintText: '搜索当前媒体库',
                        prefixIcon: const Icon(Icons.search),
                        suffixIcon: IconButton(
                            tooltip: '清除搜索',
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _search.clear();
                              _query('', now: true);
                            })),
                    onChanged: (text) => _query(text),
                    onSubmitted: (text) => _query(text, now: true))),
            if (_browser.filters.changed)
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(children: [
                    Expanded(child: Text(_browser.filters.summary)),
                    TextButton(
                        onPressed: () =>
                            _applyFilters(const MediaServerQuery()),
                        child: const Text('清除筛选'))
                  ])),
            if (_browser.busy || _playing) const LinearProgressIndicator(),
            if (_browser.error != null || _playError != null)
              Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(children: [
                    Text(_playError ?? _serverError(_browser.error!)),
                    if (_browser.error != null)
                      TextButton(
                          onPressed: () =>
                              _browser.load(more: _browser.items.isNotEmpty),
                          child: const Text('重试加载')),
                  ])),
            if (_browser.total != null)
              Align(
                  alignment: Alignment.centerLeft,
                  child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      child: Text(
                          '已加载 ${_browser.items.length} / ${_browser.total} 项'))),
            Expanded(
                child: !_browser.busy &&
                        _browser.items.isEmpty &&
                        _browser.error == null
                    ? Center(
                        child: Text(_browser.search.isEmpty &&
                                !_browser.filters.filtered
                            ? '此媒体库暂无内容'
                            : '没有匹配的媒体'))
                    : GridView.builder(
                        controller: _scroll,
                        padding: const EdgeInsets.all(12),
                        gridDelegate:
                            const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 190,
                                childAspectRatio: 0.65,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10),
                        itemCount: _browser.items.length,
                        itemBuilder: (_, index) {
                          final item = _browser.items[index];
                          return Card(
                              clipBehavior: Clip.antiAlias,
                              child: InkWell(
                                  onTap: _playing ? null : () => _open(item),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Expanded(
                                            child: Image.network(
                                                _client.imageUrl(item.id),
                                                headers: _client.headers,
                                                cacheWidth: 360,
                                                fit: BoxFit.cover,
                                                errorBuilder: (_, __, ___) =>
                                                    Icon(
                                                        item.isFolder
                                                            ? Icons.folder
                                                            : Icons
                                                                .movie_outlined,
                                                        size: 48))),
                                        Padding(
                                            padding: const EdgeInsets.all(8),
                                            child: Text(item.name,
                                                maxLines: 2,
                                                overflow:
                                                    TextOverflow.ellipsis)),
                                        if (item.resumeMs > 0)
                                          Padding(
                                              padding: const EdgeInsets.only(
                                                  left: 8, bottom: 8),
                                              child: Text(
                                                  '续播 ${(item.resumeMs / 60000).floor()} 分钟',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall)),
                                      ])));
                        })),
            if (_browser.hasMore && _browser.items.isNotEmpty)
              TextButton(
                  onPressed:
                      _browser.busy ? null : () => _browser.load(more: true),
                  child: const Text('加载更多')),
          ])));
}
