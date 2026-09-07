import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

/// Keeps the chooser current while the demuxer discovers additional tracks.
class SubtitleTrackDialog extends StatefulWidget {
  final List<SubtitleTrack> initialTracks;
  final Stream<List<SubtitleTrack>> tracks;
  final SubtitleTrack currentTrack;
  final Future<void> Function(SubtitleTrack) onSelect;
  final VoidCallback onOpenExternal;

  const SubtitleTrackDialog({super.key, required this.initialTracks,
    required this.tracks, required this.currentTrack, required this.onSelect,
    required this.onOpenExternal});

  @override
  State<SubtitleTrackDialog> createState() => _SubtitleTrackDialogState();
}

class _SubtitleTrackDialogState extends State<SubtitleTrackDialog> {
  final _scroll = ScrollController();
  bool _selecting = false;
  String? _error;

  @override
  void dispose() { _scroll.dispose(); super.dispose(); }

  Future<void> _select(SubtitleTrack track) async {
    if (_selecting) return;
    setState(() { _selecting = true; _error = null; });
    try {
      await widget.onSelect(track);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() { _selecting = false; _error = '字幕切换失败，请重试或选择其他轨道。'; });
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<SubtitleTrack>>(
    stream: widget.tracks, initialData: widget.initialTracks,
    builder: (context, snapshot) {
      final tracks = (snapshot.data ?? widget.initialTracks)
          .where((track) => track.id != 'auto' && track.id != 'no').toList();
      final options = [SubtitleTrack.auto(), SubtitleTrack.no(), ...tracks];
      return AlertDialog(
        title: Text('选择字幕轨道（${tracks.length} 条）'),
        content: SizedBox(width: 480, height: MediaQuery.sizeOf(context).height * 0.5,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('上下滑动查看全部字幕，语言与标题由视频文件提供。'),
            if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (_selecting) const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Expanded(child: Scrollbar(controller: _scroll, thumbVisibility: true,
              child: ListView.builder(controller: _scroll, itemCount: options.length,
                itemBuilder: (context, index) {
                  final track = options[index];
                  final selected = widget.currentTrack.id == track.id;
                  final title = track.id == 'auto' ? '自动选择字幕'
                      : track.id == 'no' ? '无字幕'
                      : (track.title?.trim().isNotEmpty == true ? track.title! : '字幕轨道 ${track.id}');
                  final info = [if (index >= 2) '轨道 ${track.id}',
                    if (track.language?.isNotEmpty == true) track.language!,
                    if (track.codec?.isNotEmpty == true) track.codec!,
                    if (track.uri || track.data) '外部字幕'];
                  return ListTile(key: ValueKey('subtitle-track-${track.id}'),
                    leading: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                    title: Text(title), subtitle: info.isEmpty ? null : Text(info.join(' · ')),
                    selected: selected, enabled: !_selecting,
                    onTap: () => _select(track));
                }))),
          ])),
        actions: [TextButton(onPressed: _selecting ? null : () {
          Navigator.pop(context);
          widget.onOpenExternal();
        }, child: const Text('加载外部字幕')),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消'))],
      );
    });
}
