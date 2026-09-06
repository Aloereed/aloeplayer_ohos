import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as path;
import '../history_service.dart';
import '../models/catalog_item.dart';
import '../models/playback_media.dart';
import '../services/catalog_playback.dart';
import '../services/media_catalog.dart';
import '../widgets/catalog_artwork.dart';
import '../mpvplayer.dart';
import '../settings.dart';
import 'catalog_detail_page.dart';

class CatalogPage extends StatefulWidget {
  final MediaCatalog? catalog;
  final Future<List<HistoryItem>> Function()? historyLoader;
  final bool generateArtwork;
  const CatalogPage(
      {super.key,
      this.catalog,
      this.historyLoader,
      this.generateArtwork = true});
  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  late final catalog = widget.catalog ?? MediaCatalog.instance;
  final _searchController = TextEditingController();
  Map<String, HistoryItem> _history = {};
  String _filter = '全部';
  String _sort = '名称';
  String? _error;
  bool _loading = true;
  bool _adding = false;
  bool _playing = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      await catalog.initialize();
      await _loadHistory();
      if (mounted) {
        setState(() {
          _loading = false;
          _error = null;
        });
      }
      if (mounted &&
          !catalog.scanning &&
          !catalog.cancelled &&
          catalog.lastScan == null) {
        await _scan();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '媒体索引无法打开，请重试';
        });
      }
    }
  }

  Future<void> _loadHistory() async {
    try {
      final rows = await (widget.historyLoader?.call() ??
          HistoryService().getRecentHistory(limit: 10000));
      final byId = {for (final row in rows) row.filePath: row};
      final histories = <String, HistoryItem>{};
      for (final item in catalog.items) {
        var value = byId[PlaybackMedia.localId(item.filePath)];
        if (value == null && item.filePath.endsWith('.lnk')) {
          try {
            value = byId[PlaybackMedia.localId(await catalogSource(item))];
          } catch (_) {}
        }
        if (value != null) histories[item.filePath] = value;
      }
      if (mounted) setState(() => _history = histories);
    } catch (_) {/* The library remains usable without history. */}
  }

  Future<void> _scan() async {
    if (mounted) setState(() => _error = null);
    await catalog.scan();
    await _loadHistory();
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _add() async {
    if (_adding) return;
    setState(() => _adding = true);
    try {
      final result = await SettingsService().getPersistPermission(
          '媒体文件|.mp4,.mkv,.avi,.mov,.flv,.wmv,.webm,.m4v,.ts,.m2ts,.mp3,.flac,.m4a,.wav,.aac,.ogg,.opus');
      var added = 0;
      for (final source
          in result.split('|||').where((s) => s.trim().isNotEmpty)) {
        final uri = Uri.tryParse(source);
        final name = uri?.pathSegments.lastOrNull ?? path.basename(source);
        if (name.isEmpty || name == '.' || name == '..') continue;
        final audio =
            CatalogItem(filePath: name, title: name, revision: '').isAudio;
        final directory = Directory(MediaCatalog.defaultRoots[audio ? 1 : 0]);
        await directory.create(recursive: true);
        final safeName = path.basename(name);
        var target = File(path.join(directory.path, '$safeName.lnk'));
        var suffix = 2;
        while (await target.exists()) {
          if ((await target.readAsString()).trim() == source.trim()) break;
          target = File(path.join(directory.path,
              '${path.basenameWithoutExtension(safeName)} ($suffix)${path.extension(safeName)}.lnk'));
          suffix++;
        }
        if (await target.exists()) continue;
        await target.writeAsString(source.trim(), flush: true);
        added++;
      }
      if (added > 0) {
        _message('已添加 $added 个快捷方式，原文件未复制');
        await _scan();
      }
    } catch (_) {
      _message('添加未完成，请检查文件访问权限后重试');
    } finally {
      if (mounted) setState(() => _adding = false);
    }
  }

  Future<Map<String, HistoryItem>> _play(
      CatalogItem item, List<CatalogItem> items, int? position) async {
    if (_playing) return _history;
    _playing = true;
    try {
      final queue = await catalogQueue(item, items);
      final source = await catalogSource(item);
      if (!mounted) return _history;
      await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => MPVPlayer(
                  filePath: source,
                  mediaQueue: queue,
                  initialPositionMs: position ?? 0)));
      await _loadHistory();
    } catch (_) {
      _message('文件已移动或无法访问，请重新添加文件或刷新媒体库');
    } finally {
      _playing = false;
    }
    return _history;
  }

  Future<void> _details(CatalogCollection collection) async {
    await Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => CatalogDetailPage(
                collection: collection,
                history: _history,
                onPlay: _play,
                generateArtwork: widget.generateArtwork)));
    await _loadHistory();
  }

  void _info() => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
              title: const Text('整理你的海报库'),
              content: const SingleChildScrollView(
                  child: Text('添加本地媒体只保存快捷方式，不复制文件。已有视频库、音频库和下载文件可直接扫描。\n\n'
                      '影片支持同名 NFO、movie.nfo 和 poster.jpg；剧集支持 tvshow.nfo、季文件夹和 S01E01 文件名。'
                      '没有海报的视频会尝试生成画面缩略图。\n\n'
                      '这里只读取本地资料，不会自动联网匹配影片。移动文件后刷新索引即可。')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('知道了'))
              ]));

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: catalog,
      builder: (context, _) {
        final colors = Theme.of(context).colorScheme;
        final collections = CatalogCollection.group(catalog.items);
        final visible = collections
            .where((c) =>
                c.matches(_searchController.text) &&
                (_filter == '全部' ||
                    _filter == c.kind ||
                    (_filter == '未看完' &&
                        c.items.any((i) =>
                            catalogResume(_history[i.filePath]) != null))))
            .toList();
        visible.sort((a, b) {
          final order = _sort == '最近更新'
              ? b.modifiedMs.compareTo(a.modifiedMs)
              : _sort == '年份'
                  ? (b.year ?? 0).compareTo(a.year ?? 0)
                  : 0;
          return order != 0 ? order : compareCatalogTitles(a.title, b.title);
        });
        return Scaffold(
          appBar: AppBar(title: const Text('海报库'), actions: [
            IconButton(
                tooltip: '添加本地媒体（不复制）',
                onPressed: _adding || catalog.scanning ? null : _add,
                icon: const Icon(Icons.add_rounded)),
            IconButton(
                tooltip: catalog.scanning ? '取消扫描' : '刷新索引',
                onPressed: catalog.cancelled && catalog.scanning
                    ? null
                    : catalog.scanning
                        ? catalog.cancel
                        : _scan,
                icon: Icon(catalog.scanning
                    ? Icons.stop_circle_outlined
                    : Icons.refresh_rounded)),
            IconButton(
                tooltip: '媒体整理说明',
                onPressed: _info,
                icon: const Icon(Icons.info_outline)),
          ]),
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _scan,
                  child: LayoutBuilder(builder: (context, constraints) {
                    final columns =
                        (constraints.maxWidth / 160).floor().clamp(2, 7);
                    final width =
                        (constraints.maxWidth - 32 - (columns - 1) * 12) /
                            columns;
                    final textScale =
                        MediaQuery.textScalerOf(context).scale(14) / 14;
                    return CustomScrollView(
                        physics: const AlwaysScrollableScrollPhysics(),
                        slivers: [
                          SliverToBoxAdapter(
                              child: Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(16, 8, 16, 16),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text('你的私人放映室',
                                            style: Theme.of(context)
                                                .textTheme
                                                .headlineSmall),
                                        const SizedBox(height: 6),
                                        Text(
                                            '${collections.length} 部作品 · ${catalog.items.length} 个媒体文件',
                                            style: TextStyle(
                                                color:
                                                    colors.onSurfaceVariant)),
                                        const SizedBox(height: 18),
                                        TextField(
                                            controller: _searchController,
                                            onChanged: (_) => setState(() {}),
                                            decoration: InputDecoration(
                                                prefixIcon:
                                                    const Icon(Icons.search),
                                                hintText: '搜索片名、剧集或年份',
                                                suffixIcon: _searchController
                                                        .text.isEmpty
                                                    ? null
                                                    : IconButton(
                                                        tooltip: '清空搜索',
                                                        icon: const Icon(
                                                            Icons.close),
                                                        onPressed: () =>
                                                            setState(
                                                                _searchController
                                                                    .clear)))),
                                        const SizedBox(height: 14),
                                        Wrap(
                                            spacing: 8,
                                            runSpacing: 6,
                                            children: [
                                              '全部',
                                              '电影',
                                              '剧集',
                                              '音频',
                                              '未看完'
                                            ]
                                                .map((filter) => ChoiceChip(
                                                    label: Text(filter),
                                                    selected: _filter == filter,
                                                    onSelected: (_) => setState(
                                                        () =>
                                                            _filter = filter)))
                                                .toList()),
                                        const SizedBox(height: 6),
                                        Row(children: [
                                          Expanded(
                                              child: Text(
                                                  '${visible.length} 部作品',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .labelLarge)),
                                          DropdownButton<String>(
                                              value: _sort,
                                              underline:
                                                  const SizedBox.shrink(),
                                              items: ['名称', '最近更新', '年份']
                                                  .map((sort) =>
                                                      DropdownMenuItem(
                                                          value: sort,
                                                          child: Text(sort)))
                                                  .toList(),
                                              onChanged: (sort) {
                                                if (sort != null) {
                                                  setState(() => _sort = sort);
                                                }
                                              })
                                        ]),
                                        if (catalog.scanning || _adding) ...[
                                          const LinearProgressIndicator(),
                                          const SizedBox(height: 8),
                                          Text(_adding
                                              ? '正在添加媒体…'
                                              : catalog.cancelled
                                                  ? '正在停止，已扫描结果会保留…'
                                                  : '已扫描 ${catalog.scanned} 个媒体文件'),
                                        ] else if (catalog.lastScan != null ||
                                            catalog.cancelled)
                                          Text(
                                              catalog.cancelled
                                                  ? '扫描已取消，已保留现有结果'
                                                  : '索引已更新',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall),
                                        if (_error != null ||
                                            catalog.error != null)
                                          Padding(
                                              padding:
                                                  const EdgeInsets.only(top: 8),
                                              child: Text(
                                                  _error ?? catalog.error!,
                                                  style: TextStyle(
                                                      color: colors.error))),
                                      ]))),
                          if (visible.isEmpty)
                            SliverFillRemaining(
                                hasScrollBody: false,
                                child: Padding(
                                    padding: const EdgeInsets.all(24),
                                    child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                              catalog.items.isEmpty
                                                  ? Icons.video_library_outlined
                                                  : Icons.search_off,
                                              size: 64,
                                              color: colors.primary),
                                          const SizedBox(height: 16),
                                          Text(
                                              catalog.items.isEmpty
                                                  ? '把喜欢的影片放进来'
                                                  : '没有符合条件的作品',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleLarge,
                                              textAlign: TextAlign.center),
                                          const SizedBox(height: 8),
                                          Text(
                                              catalog.items.isEmpty
                                                  ? '添加本地媒体，或扫描已有的视频库和音频库。'
                                                  : '试试其他关键词，或清除筛选。',
                                              textAlign: TextAlign.center),
                                          const SizedBox(height: 20),
                                          if (catalog.items.isEmpty) ...[
                                            FilledButton.icon(
                                                onPressed:
                                                    catalog.scanning || _adding
                                                        ? null
                                                        : _add,
                                                icon: const Icon(Icons.add),
                                                label: const Text('添加本地媒体')),
                                            TextButton(
                                                onPressed: catalog.scanning
                                                    ? null
                                                    : _scan,
                                                child: const Text('扫描已有文件')),
                                          ] else
                                            TextButton(
                                                onPressed: () => setState(() {
                                                      _filter = '全部';
                                                      _searchController.clear();
                                                    }),
                                                child: const Text('清除筛选')),
                                        ])))
                          else
                            SliverPadding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 16),
                                sliver: SliverGrid(
                                    gridDelegate:
                                        SliverGridDelegateWithFixedCrossAxisCount(
                                            crossAxisCount: columns,
                                            crossAxisSpacing: 12,
                                            mainAxisSpacing: 16,
                                            mainAxisExtent:
                                                width * 1.4 + 80 * textScale),
                                    delegate: SliverChildBuilderDelegate(
                                        (context, index) {
                                      final collection = visible[index];
                                      final next =
                                          catalogNext(collection, _history);
                                      final resume = catalogResume(
                                          _history[next.filePath]);
                                      final done = collection.items.every((i) =>
                                          catalogCompleted(
                                              _history[i.filePath]));
                                      return Semantics(
                                          button: true,
                                          label:
                                              '${collection.title}，${collection.kind}，查看详情',
                                          child: Card(
                                              margin: EdgeInsets.zero,
                                              child: InkWell(
                                                  onTap: () =>
                                                      _details(collection),
                                                  child: Column(
                                                      crossAxisAlignment:
                                                          CrossAxisAlignment
                                                              .stretch,
                                                      children: [
                                                        Expanded(
                                                            child: Stack(
                                                                fit: StackFit
                                                                    .expand,
                                                                children: [
                                                              CatalogArtwork(
                                                                  key: ValueKey(
                                                                      collection
                                                                          .id),
                                                                  item:
                                                                      collection
                                                                          .first,
                                                                  poster:
                                                                      collection
                                                                          .poster,
                                                                  generate: widget
                                                                      .generateArtwork),
                                                              Positioned(
                                                                  left: 8,
                                                                  top: 8,
                                                                  child: DecoratedBox(
                                                                      decoration: BoxDecoration(
                                                                          color: Colors.black.withValues(
                                                                              alpha:
                                                                                  .65),
                                                                          borderRadius: BorderRadius.circular(
                                                                              8)),
                                                                      child: Padding(
                                                                          padding: const EdgeInsets
                                                                              .symmetric(
                                                                              horizontal:
                                                                                  8,
                                                                              vertical:
                                                                                  4),
                                                                          child: Text(
                                                                              collection.isSeries ? '${collection.items.length} 集' : collection.kind,
                                                                              style: const TextStyle(color: Colors.white, fontSize: 12))))),
                                                              if (resume !=
                                                                      null ||
                                                                  done)
                                                                Positioned(
                                                                    left: 0,
                                                                    right: 0,
                                                                    bottom: 0,
                                                                    child: ColoredBox(
                                                                        color: Colors.black.withValues(
                                                                            alpha:
                                                                                .7),
                                                                        child: Padding(
                                                                            padding: const EdgeInsets.all(
                                                                                6),
                                                                            child: Text(done ? '已看完' : '观看至 ${catalogTime(resume!)}',
                                                                                style: const TextStyle(color: Colors.white, fontSize: 12),
                                                                                maxLines: 1,
                                                                                overflow: TextOverflow.ellipsis)))),
                                                            ])),
                                                        Padding(
                                                            padding:
                                                                const EdgeInsets
                                                                    .fromLTRB(
                                                                    10,
                                                                    10,
                                                                    10,
                                                                    4),
                                                            child: Text(
                                                                collection
                                                                    .title,
                                                                style: Theme.of(
                                                                        context)
                                                                    .textTheme
                                                                    .titleSmall,
                                                                maxLines: 2,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis)),
                                                        Padding(
                                                            padding:
                                                                const EdgeInsets
                                                                    .fromLTRB(
                                                                    10,
                                                                    0,
                                                                    10,
                                                                    10),
                                                            child: Text(
                                                                [
                                                                  if (collection
                                                                          .year !=
                                                                      null)
                                                                    '${collection.year}',
                                                                  collection
                                                                          .isSeries
                                                                      ? '${collection.items.map((i) => i.season ?? 1).toSet().length} 季'
                                                                      : collection
                                                                          .kind
                                                                ].join(' · '),
                                                                maxLines: 1,
                                                                overflow:
                                                                    TextOverflow
                                                                        .ellipsis,
                                                                style: Theme.of(
                                                                        context)
                                                                    .textTheme
                                                                    .bodySmall)),
                                                      ]))));
                                    }, childCount: visible.length))),
                          SliverToBoxAdapter(
                              child: SizedBox(
                                  height: MediaQuery.paddingOf(context).bottom +
                                      24)),
                        ]);
                  })),
        );
      });
}
