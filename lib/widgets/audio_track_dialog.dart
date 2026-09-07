import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

/// Keeps the chooser current while the demuxer discovers additional tracks.
class AudioTrackDialog extends StatefulWidget {
  final List<AudioTrack> initialTracks;
  final Stream<List<AudioTrack>> tracks;
  final AudioTrack currentTrack;
  final Future<void> Function(AudioTrack) onSelect;

  const AudioTrackDialog({super.key, required this.initialTracks,
    required this.tracks, required this.currentTrack, required this.onSelect,
    });

  @override
  State<AudioTrackDialog> createState() => _AudioTrackDialogState();
}

class _AudioTrackDialogState extends State<AudioTrackDialog> {
  final _scroll = ScrollController();
  bool _selecting = false;
  String? _error;

  @override
  void dispose() { _scroll.dispose(); super.dispose(); }

  Future<void> _select(AudioTrack track) async {
    if (_selecting) return;
    setState(() { _selecting = true; _error = null; });
    try {
      await widget.onSelect(track);
      if (mounted) Navigator.pop(context);
    } catch (_) {
      if (mounted) setState(() { _selecting = false; _error = '音轨切换失败，请重试或选择其他轨道。'; });
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<AudioTrack>>(
    stream: widget.tracks, initialData: widget.initialTracks,
    builder: (context, snapshot) {
      final tracks = (snapshot.data ?? widget.initialTracks)
          .where((track) => track.id != 'auto' && track.id != 'no').toList();
      final options = [AudioTrack.auto(), AudioTrack.no(), ...tracks];
      return AlertDialog(
        title: Text('选择音轨（${tracks.length} 条）'),
        content: SizedBox(width: 480, height: MediaQuery.sizeOf(context).height * 0.5,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('上下滑动查看全部音轨，语言与标题由视频文件提供。'),
            if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            if (_selecting) const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Expanded(child: Scrollbar(controller: _scroll, thumbVisibility: true,
              child: ListView.builder(controller: _scroll, itemCount: options.length,
                itemBuilder: (context, index) {
                  final track = options[index];
                  final selected = widget.currentTrack.id == track.id;
                  final title = track.id == 'auto' ? '自动选择音轨'
                      : track.id == 'no' ? '关闭音轨'
                      : (track.title?.trim().isNotEmpty == true ? track.title! : '音轨 ${track.id}');
                  final info = [if (index >= 2) '轨道 ${track.id}',
                    if (track.language?.isNotEmpty == true) track.language!,
                    if (track.codec?.isNotEmpty == true) track.codec!,
                    if (track.channels?.isNotEmpty == true) track.channels!,
                    if (track.uri) '外部音轨'];
                  return ListTile(key: ValueKey('audio-track-${track.id}'),
                    leading: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_unchecked),
                    title: Text(title), subtitle: info.isEmpty ? null : Text(info.join(' · ')),
                    selected: selected, enabled: !_selecting,
                    onTap: () => _select(track));
                }))),
          ])),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消'))],
      );
    });
}
