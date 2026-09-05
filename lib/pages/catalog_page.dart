import 'dart:io';
import 'package:flutter/material.dart';
import '../models/catalog_item.dart';
import '../models/playback_media.dart';
import '../services/media_catalog.dart';
import '../mpvplayer.dart';

class CatalogPage extends StatefulWidget {
  const CatalogPage({super.key});
  @override
  State<CatalogPage> createState() => _CatalogPageState();
}
class _CatalogPageState extends State<CatalogPage> {
  final catalog = MediaCatalog.instance;
  String _search = '';
  String? _series;
  String? _error;
  @override
  void initState() { super.initState(); catalog.initialize().catchError((_) { if (mounted) setState(() => _error = '媒体索引无法打开'); }); }
  Future<void> _scan() async {
    try { await catalog.scan(); } catch (_) { if (mounted) setState(() => _error = '扫描失败，请重试'); }
  }
  void _open(CatalogItem item, List<CatalogItem> items) {
    final episodes = item.series == null ? [item] : items.where((m) => m.series == item.series).toList();
    final queue = episodes.map((m) => PlaybackMedia(id: PlaybackMedia.localId(m.filePath), url: m.filePath, title: m.title)).toList();
    Navigator.push(context, MaterialPageRoute(builder: (_) => MPVPlayer(filePath: item.filePath, mediaQueue: queue)));
  }
  @override
  Widget build(BuildContext context) => ListenableBuilder(listenable: catalog, builder: (_, __) {
    final items = catalog.items.where((m) => (_series == null || m.series == _series) && '${m.title} ${m.series ?? ''}'.toLowerCase().contains(_search.toLowerCase())).toList();
    final series = catalog.items.map((m) => m.series).whereType<String>().toSet().toList()..sort();
    return Scaffold(appBar: AppBar(title: const Text('海报媒体库'), actions: [IconButton(tooltip: catalog.scanning ? '取消扫描' : '增量扫描', onPressed: catalog.scanning ? catalog.cancel : _scan, icon: Icon(catalog.scanning ? Icons.stop : Icons.refresh))]),
      body: Column(children: [
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: TextField(decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: '搜索影片或剧集'), onChanged: (value) => setState(() => _search = value))),
        if (series.isNotEmpty) SizedBox(height: 52, child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
          ChoiceChip(label: const Text('全部'), selected: _series == null, onSelected: (_) => setState(() => _series = null)),
          for (final title in series) Padding(padding: const EdgeInsets.only(left: 8), child: ChoiceChip(label: Text(title), selected: _series == title, onSelected: (_) => setState(() => _series = title))),
        ])),
        if (catalog.scanning) const LinearProgressIndicator(),
        if (catalog.scanning) Text('已扫描 ${catalog.scanned} 个媒体'),
        if (_error != null || catalog.error != null) Padding(padding: const EdgeInsets.all(12), child: Text(_error ?? catalog.error!)),
        Expanded(child: items.isEmpty ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const Text('扫描本地音视频库，读取同目录 NFO 和海报'), FilledButton(onPressed: catalog.scanning ? null : _scan, child: const Text('扫描媒体库'))]))
          : GridView.builder(padding: const EdgeInsets.all(12), gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 200, mainAxisSpacing: 12, crossAxisSpacing: 12, childAspectRatio: 0.62),
            itemCount: items.length, itemBuilder: (_, index) {
              final item = items[index];
              return Card(clipBehavior: Clip.antiAlias, child: InkWell(onTap: () => _open(item, catalog.items), onLongPress: () => showDialog(context: context, builder: (context) => AlertDialog(title: Text(item.title), content: SingleChildScrollView(child: Text(item.plot ?? item.filePath)), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))])),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(child: item.poster == null ? const Center(child: Icon(Icons.movie_outlined, size: 56)) : Image.file(File(item.poster!), cacheWidth: 320, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.movie_outlined, size: 56))),
                  Padding(padding: const EdgeInsets.all(8), child: Text(item.title, maxLines: 2, overflow: TextOverflow.ellipsis)),
                  Padding(padding: const EdgeInsets.fromLTRB(8, 0, 8, 8), child: Text(item.episode != null ? 'S${item.season ?? 1} · E${item.episode}' : '${item.year ?? ''}', style: Theme.of(context).textTheme.bodySmall)),
                ])));
            })),
      ]));
  });
}
