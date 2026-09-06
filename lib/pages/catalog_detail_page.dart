import 'package:flutter/material.dart';
import '../history_service.dart';
import '../models/catalog_item.dart';
import '../services/catalog_playback.dart';
import '../widgets/catalog_artwork.dart';

class CatalogDetailPage extends StatefulWidget {
  final CatalogCollection collection;
  final Map<String, HistoryItem> history;
  final Future<Map<String, HistoryItem>> Function(
      CatalogItem, List<CatalogItem>, int?) onPlay;
  final bool generateArtwork;
  const CatalogDetailPage(
      {super.key,
      required this.collection,
      required this.history,
      required this.onPlay,
      this.generateArtwork = true});
  @override
  State<CatalogDetailPage> createState() => _CatalogDetailPageState();
}

class _CatalogDetailPageState extends State<CatalogDetailPage> {
  late Map<String, HistoryItem> _history = widget.history;
  late int _season = catalogNext(widget.collection, _history).season ?? 1;
  bool _opening = false;
  Future<void> _play(CatalogItem item, {bool restart = false}) async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final history = await widget.onPlay(item, widget.collection.items,
          restart ? 0 : catalogResume(_history[item.filePath]));
      if (mounted) setState(() => _history = history);
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final collection = widget.collection;
    final next = catalogNext(collection, _history);
    final position = catalogResume(_history[next.filePath]);
    final seasons = collection.items.map((i) => i.season ?? 1).toSet().toList()
      ..sort();
    final episodes =
        collection.items.where((i) => (i.season ?? 1) == _season).toList();
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(collection.title)),
      bottomNavigationBar: SafeArea(
          top: false,
          child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: FilledButton.icon(
                  onPressed: _opening ? null : () => _play(next),
                  icon: _opening
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.play_arrow_rounded),
                  label: Text(
                      _opening
                          ? '正在打开…'
                          : position != null
                              ? '继续播放 · ${catalogTime(position)}'
                              : collection.isSeries
                                  ? '播放 ${next.episodeLabel}'
                                  : '立即播放',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis)))),
      body: CustomScrollView(slivers: [
        SliverToBoxAdapter(
            child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                          child: ClipRRect(
                              borderRadius: BorderRadius.circular(24),
                              child: SizedBox(
                                  width: 210,
                                  height: 294,
                                  child: CatalogArtwork(
                                      item: collection.first,
                                      poster: collection.poster,
                                      generate: widget.generateArtwork)))),
                      const SizedBox(height: 24),
                      Text(collection.title,
                          style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 8),
                      Text(
                          [
                            collection.kind,
                            if (collection.year != null) '${collection.year}',
                            if (collection.isSeries)
                              '${seasons.length} 季 · ${collection.items.length} 集'
                          ].join(' · '),
                          style: TextStyle(color: colors.onSurfaceVariant)),
                      if (position != null) ...[
                        const SizedBox(height: 14),
                        Text(collection.isSeries
                            ? '上次看到 ${next.episodeLabel} · ${catalogTime(position)}'
                            : '上次播放至 ${catalogTime(position)}'),
                        if ((_history[next.filePath]?.durationMs ?? 0) > 0)
                          Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: LinearProgressIndicator(
                                  value: (position /
                                          _history[next.filePath]!.durationMs)
                                      .clamp(0, 1))),
                        TextButton.icon(
                            onPressed: _opening
                                ? null
                                : () => _play(next, restart: true),
                            icon: const Icon(Icons.replay),
                            label: const Text('从头播放')),
                      ],
                      const SizedBox(height: 20),
                      if (collection.plot != null)
                        ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            childrenPadding: const EdgeInsets.only(bottom: 16),
                            title: const Text('剧情简介'),
                            subtitle: Text(collection.plot!,
                                maxLines: 3, overflow: TextOverflow.ellipsis),
                            children: [
                              Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(collection.plot!))
                            ])
                      else
                        Text('暂无简介',
                            style: TextStyle(color: colors.onSurfaceVariant)),
                      const SizedBox(height: 16),
                      if (collection.isSeries) ...[
                        Text('选集',
                            style: Theme.of(context).textTheme.titleLarge),
                        const SizedBox(height: 12),
                        Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: seasons
                                .map((season) => ChoiceChip(
                                    label: Text(
                                        season == 0 ? '特别篇' : '第 $season 季'),
                                    selected: _season == season,
                                    onSelected: (_) =>
                                        setState(() => _season = season)))
                                .toList()),
                      ] else
                        ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            title: const Text('文件信息'),
                            children: [
                              Padding(
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child:
                                      SelectableText(collection.first.filePath))
                            ]),
                    ]))),
        if (collection.isSeries)
          SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
            final item = episodes[index];
            final history = _history[item.filePath];
            final resume = catalogResume(history);
            return ListTile(
                enabled: !_opening,
                selected: item.filePath == next.filePath,
                leading: CircleAvatar(
                    backgroundColor: colors.primaryContainer,
                    child: Text('${item.episode ?? index + 1}',
                        style: TextStyle(color: colors.onPrimaryContainer))),
                title: Text(item.title,
                    maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                          '${item.episodeLabel} · ${catalogCompleted(history) ? '已看完' : resume != null ? '看到 ${catalogTime(resume)}' : '未观看'}'),
                      if (history != null && history.durationMs > 0)
                        Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: LinearProgressIndicator(
                                value:
                                    (history.lastPosition / history.durationMs)
                                        .clamp(0, 1))),
                    ]),
                trailing: const Icon(Icons.play_circle_outline),
                onTap: () => _play(item),
                onLongPress: () => showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                            title: Text(item.title),
                            content: SingleChildScrollView(
                                child: SelectableText(item.filePath)),
                            actions: [
                              TextButton(
                                  onPressed: () => Navigator.pop(context),
                                  child: const Text('关闭'))
                            ])));
          }, childCount: episodes.length)),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ]),
    );
  }
}
