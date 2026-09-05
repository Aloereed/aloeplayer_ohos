import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker_ohos/file_picker_ohos.dart';
import '../history_service.dart';
import '../models/playback_media.dart';
import '../mpvplayer.dart';
import 'remote_playback_page.dart';

class ContinueWatchingPage extends StatefulWidget {
  const ContinueWatchingPage({super.key});
  @override
  State<ContinueWatchingPage> createState() => _ContinueWatchingPageState();
}
class _ContinueWatchingPageState extends State<ContinueWatchingPage> {
  final _history = HistoryService();
  List<HistoryItem> _items = [];
  String _filter = '全部';
  String? _error;
  @override
  void initState() { super.initState(); _load(); }
  Future<void> _load() async {
    try {
      final items = await _history.getContinueWatching(limit: 500);
      if (mounted) setState(() { _items = items; _error = null; });
    } catch (_) { if (mounted) setState(() => _error = '加载失败，请重试'); }
  }
  Future<void> _open(HistoryItem item) async {
    final remote = PlaybackMedia.isRemote(item.filePath);
    if (!remote && !item.filePath.contains('://') && !await File(item.filePath).exists()) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('文件已移动，请在更多菜单中重新定位')));
      return;
    }
    if (!mounted) return;
    await Navigator.push(context, MaterialPageRoute(builder: (_) => remote
      ? RemotePlaybackPage(mediaId: item.filePath, initialPositionMs: item.lastPosition) : MPVPlayer(filePath: item.filePath, initialPositionMs: item.lastPosition)));
    await _load();
  }
  Future<void> _action(String action, HistoryItem item) async {
    if (action == 'done') await _history.markCompleted(item.filePath);
    if (action == 'remove') await _history.deleteHistory(item.filePath);
    if (action == 'locate') {
      final result = await FilePicker.platform.pickFiles(type: FileType.any);
      final selected = result?.files.single.path;
      if (selected != null) await _history.relocate(item.filePath, selected);
    }
    await _load();
  }
  @override
  Widget build(BuildContext context) {
    final items = _items.where((item) => _filter == '全部' || (_filter == '网络') == PlaybackMedia.isRemote(item.filePath)).toList();
    return Scaffold(appBar: AppBar(title: const Text('继续观看 / 收听'), actions: [IconButton(onPressed: _load, icon: const Icon(Icons.refresh))]),
      body: Column(children: [
        Wrap(spacing: 8, children: ['全部', '本地', '网络'].map((filter) => ChoiceChip(label: Text(filter), selected: _filter == filter, onSelected: (_) => setState(() => _filter = filter))).toList()),
        if (_error != null) Text(_error!),
        Expanded(child: items.isEmpty ? const Center(child: Text('暂无未播完的媒体')) : ListView.builder(itemCount: items.length, itemBuilder: (_, index) {
          final item = items[index];
          return ListTile(leading: Icon(PlaybackMedia.isRemote(item.filePath) ? Icons.cloud_outlined : Icons.play_circle_outline),
            title: Text(item.title ?? item.filePath, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('上次播放至 ${(item.lastPosition / 60000).floor()} 分钟'),
              if (item.durationMs > 0) LinearProgressIndicator(value: (item.lastPosition / item.durationMs).clamp(0.0, 1.0)),
            ]), onTap: () => _open(item),
            trailing: PopupMenuButton<String>(onSelected: (action) => _action(action, item), itemBuilder: (_) => [
              const PopupMenuItem(value: 'done', child: Text('标记已播完')),
              if (!PlaybackMedia.isRemote(item.filePath)) const PopupMenuItem(value: 'locate', child: Text('重新定位文件')),
              const PopupMenuItem(value: 'remove', child: Text('移除记录')),
            ]));
        })),
      ]));
  }
}
