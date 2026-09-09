import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import '../services/media_server_client.dart';
import '../services/media_server_catalog.dart';
import '../widgets/media_server_poster.dart';
import 'media_server_detail_page.dart';
import 'media_servers_page.dart';

String shelfTitle(MediaServerShelf shelf) => switch (shelf) {
      MediaServerShelf.libraries => '媒体库',
      MediaServerShelf.resume => '继续观看',
      MediaServerShelf.nextUp => '接着看下一集',
      MediaServerShelf.latest => '最新入库',
      MediaServerShelf.favorites => '我的收藏',
    };

Future<void> openServerItem(BuildContext context,
    MediaServerConnection connection, MediaServerItem item) async {
  final folder = item.isFolder && !['Series', 'Season'].contains(item.type);
  await Navigator.push(
      context,
      MaterialPageRoute(
          builder: (_) => folder
              ? MediaServerBrowser(connection: connection, initialParent: item)
              : MediaServerDetailPage(connection: connection, item: item)));
}

class MediaServerHomePage extends StatefulWidget {
  final MediaServerConnection connection;
  final MediaServerClient? client;
  const MediaServerHomePage({super.key, required this.connection, this.client});
  @override
  State<MediaServerHomePage> createState() => _MediaServerHomePageState();
}

class _MediaServerHomePageState extends State<MediaServerHomePage> {
  late final _client = widget.client ?? MediaServerClient(widget.connection);
  final _items = <MediaServerShelf, List<MediaServerItem>>{};
  final _errors = <MediaServerShelf, String>{};
  final _requests = <MediaServerShelf, CancelToken>{};
  final _busy = <MediaServerShelf>{};
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    for (final request in _requests.values) {
      request.cancel();
    }
    if (widget.client == null) unawaited(_client.close());
    super.dispose();
  }

  Future<void> _refresh() => Future.wait(MediaServerShelf.values.map(_load));
  Future<void> _load(MediaServerShelf shelf) async {
    _requests[shelf]?.cancel();
    final token = _requests[shelf] = CancelToken();
    setState(() {
      _busy.add(shelf);
      _errors.remove(shelf);
    });
    try {
      final page = await _client.shelf(shelf, cancelToken: token);
      if (!mounted || token != _requests[shelf]) return;
      setState(() => _items[shelf] = page.items);
    } catch (error) {
      if (mounted &&
          token == _requests[shelf] &&
          !(error is DioException && CancelToken.isCancel(error))) {
        setState(() => _errors[shelf] = mediaServerError(error));
      }
    } finally {
      if (mounted && token == _requests[shelf])
        setState(() => _busy.remove(shelf));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(widget.connection.name), actions: [
        IconButton(
            tooltip: '搜索与浏览全部媒体',
            icon: const Icon(Icons.search),
            onPressed: () async {
              await Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) =>
                          MediaServerBrowser(connection: widget.connection)));
              if (mounted) _refresh();
            }),
        IconButton(
            tooltip: '刷新首页',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh)),
      ]),
      body: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                for (final shelf in MediaServerShelf.values) ...[
                  ListTile(
                      title: Text(shelfTitle(shelf),
                          style: Theme.of(context).textTheme.titleLarge),
                      trailing: shelf == MediaServerShelf.libraries
                          ? null
                          : TextButton(
                              child: const Text('查看全部'),
                              onPressed: () async {
                                await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) => MediaServerShelfPage(
                                            connection: widget.connection,
                                            shelf: shelf)));
                                if (mounted) _refresh();
                              })),
                  if (_busy.contains(shelf)) const LinearProgressIndicator(),
                  if (_errors[shelf] != null)
                    Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: TextButton(
                            onPressed: () => _load(shelf),
                            child: Text('${_errors[shelf]} · 重试'))),
                  if ((_items[shelf] ?? []).isEmpty &&
                      !_busy.contains(shelf) &&
                      !_errors.containsKey(shelf))
                    const Padding(
                        padding: EdgeInsets.fromLTRB(16, 0, 16, 20),
                        child: Text('暂无内容')),
                  if ((_items[shelf] ?? []).isNotEmpty)
                    SizedBox(
                        height: 260,
                        child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            itemCount: _items[shelf]!.length,
                            itemBuilder: (_, i) => SizedBox(
                                width: 160,
                                child: MediaServerPoster(
                                    client: _client,
                                    item: _items[shelf]![i],
                                    onTap: () async {
                                      await openServerItem(context,
                                          widget.connection, _items[shelf]![i]);
                                      if (mounted) _refresh();
                                    })))),
                ],
              ])));
}

class MediaServerShelfPage extends StatefulWidget {
  final MediaServerConnection connection;
  final MediaServerShelf shelf;
  final MediaServerClient? client;
  const MediaServerShelfPage(
      {super.key, required this.connection, required this.shelf, this.client});
  @override
  State<MediaServerShelfPage> createState() => _MediaServerShelfPageState();
}

class _MediaServerShelfPageState extends State<MediaServerShelfPage> {
  late final _client = widget.client ?? MediaServerClient(widget.connection);
  final _scroll = ScrollController();
  CancelToken? _cancel;
  List<MediaServerItem> _items = [];
  int _start = 0;
  bool _busy = false, _more = true;
  String? _error;
  @override
  void initState() {
    super.initState();
    _load();
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 500 && _error == null)
        _load(more: true);
    });
  }

  @override
  void dispose() {
    _cancel?.cancel();
    _scroll.dispose();
    if (widget.client == null) unawaited(_client.close());
    super.dispose();
  }

  Future<void> _load({bool more = false}) async {
    if (more && (_busy || !_more)) return;
    _cancel?.cancel();
    final token = _cancel = CancelToken();
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final page = await _client.shelf(widget.shelf,
          start: more ? _start : 0, limit: 60, cancelToken: token);
      if (!mounted || token != _cancel) return;
      final seen = <String>{};
      final previous = more ? _items.length : 0;
      setState(() {
        _items = [...(more ? _items : <MediaServerItem>[]), ...page.items]
            .where((e) => seen.add(e.id))
            .toList();
        _start = page.nextStart;
        _more = page.hasMore && (!more || _items.length > previous);
      });
    } catch (error) {
      if (mounted &&
          token == _cancel &&
          !(error is DioException && CancelToken.isCancel(error))) {
        setState(() => _error = mediaServerError(error));
      }
    } finally {
      if (mounted && token == _cancel) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: Text(shelfTitle(widget.shelf)), actions: [
        IconButton(
            tooltip: '刷新列表', onPressed: _load, icon: const Icon(Icons.refresh))
      ]),
      body: Column(children: [
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          TextButton(
              onPressed: () => _load(more: _items.isNotEmpty),
              child: Text('$_error · 重试')),
        Expanded(
            child: !_busy && _error == null && _items.isEmpty
                ? const Center(child: Text('暂无内容'))
                : GridView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(12),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 190,
                            childAspectRatio: .6,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8),
                    itemCount: _items.length,
                    itemBuilder: (_, i) => MediaServerPoster(
                        client: _client,
                        item: _items[i],
                        onTap: () async {
                          await openServerItem(
                              context, widget.connection, _items[i]);
                          if (mounted) _load();
                        }))),
        if (_more && _items.isNotEmpty)
          TextButton(
              onPressed: _busy ? null : () => _load(more: true),
              child: const Text('加载更多')),
      ]));
}
