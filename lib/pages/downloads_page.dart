import 'package:flutter/material.dart';
import '../models/download_task.dart';
import '../services/download_manager.dart';
import '../mpvplayer.dart';

class DownloadsPage extends StatefulWidget {
  const DownloadsPage({super.key});
  @override
  State<DownloadsPage> createState() => _DownloadsPageState();
}
class _DownloadsPageState extends State<DownloadsPage> {
  final manager = DownloadManager.instance;
  String? _error;
  @override
  void initState() { super.initState(); manager.initialize().catchError((_) { if (mounted) setState(() => _error = '无法读取下载任务'); }); }
  String _size(int bytes) => '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  String _status(DownloadStatus status) => const {
    DownloadStatus.queued: '等待中', DownloadStatus.downloading: '下载中', DownloadStatus.paused: '已暂停',
    DownloadStatus.completed: '已入库', DownloadStatus.failed: '失败', DownloadStatus.canceled: '已取消',
  }[status]!;
  Future<void> _action(Future<void> Function() action) async {
    try { await action(); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'))); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('下载任务'), actions: [IconButton(tooltip: '清理已结束记录（保留文件）', onPressed: () => _action(manager.removeFinished), icon: const Icon(Icons.cleaning_services_outlined))]),
    body: ListenableBuilder(listenable: manager, builder: (_, __) => _error != null ? Center(child: Text(_error!)) : manager.tasks.isEmpty
      ? const Center(child: Text('在网络文件的更多菜单中选择“下载到本地”'))
      : ListView.builder(itemCount: manager.tasks.length, itemBuilder: (_, index) {
        final task = manager.tasks[manager.tasks.length - 1 - index];
        return Card(margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), child: Padding(padding: const EdgeInsets.all(12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (index == 0 && manager.backgroundNotice != null) Padding(padding: const EdgeInsets.only(bottom: 8), child: Text(manager.backgroundNotice!)),
          Text(task.name, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: task.size > 0 ? (task.received / task.size).clamp(0.0, 1.0) : null),
          Text('${_status(task.status)} · ${_size(task.received)} / ${_size(task.size)}'),
          if (task.error != null) Text(task.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (task.status == DownloadStatus.completed) Text(task.destination, maxLines: 2, overflow: TextOverflow.ellipsis),
          Wrap(spacing: 8, children: [
            if (task.status == DownloadStatus.downloading || task.status == DownloadStatus.queued)
              TextButton.icon(onPressed: () => _action(() => manager.pause(task)), icon: const Icon(Icons.pause), label: const Text('暂停')),
            if (task.status == DownloadStatus.paused || task.status == DownloadStatus.failed)
              TextButton.icon(onPressed: () => _action(() => manager.resume(task)), icon: const Icon(Icons.play_arrow), label: Text(task.status == DownloadStatus.failed ? '重试' : '继续')),
            if (task.status != DownloadStatus.completed && task.status != DownloadStatus.canceled)
              TextButton.icon(onPressed: () => _action(() => manager.cancel(task)), icon: const Icon(Icons.close), label: const Text('取消')),
            if (task.status == DownloadStatus.completed)
              TextButton.icon(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => MPVPlayer(filePath: task.destination))), icon: const Icon(Icons.play_arrow), label: const Text('播放')),
          ]),
        ])));
      })));
}
