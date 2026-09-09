import 'package:flutter/material.dart';
import '../services/media_server_playback.dart';

class MediaServerPlaybackDialog extends StatefulWidget {
  final List<MediaServerSource> sources;
  final MediaServerPlaybackOptions initial;
  const MediaServerPlaybackDialog(
      {super.key,
      required this.sources,
      this.initial = const MediaServerPlaybackOptions()});
  @override
  State<MediaServerPlaybackDialog> createState() =>
      _MediaServerPlaybackDialogState();
}

class _MediaServerPlaybackDialogState extends State<MediaServerPlaybackDialog> {
  late MediaServerSource _source = widget.sources
          .where((s) => s.id == widget.initial.sourceId)
          .firstOrNull ??
      widget.sources.first;
  late int _audio = widget.initial.audioIndex ?? _source.defaultAudio ?? -1;
  late int _subtitle =
      widget.initial.subtitleIndex ?? _source.defaultSubtitle ?? -1;
  late int _bitrate = widget.initial.maxBitrate;
  late MediaServerPlayMode _mode = widget.initial.mode;
  @override
  void initState() {
    super.initState();
    if (widget.initial.sourceId != _source.id) {
      _audio = _source.defaultAudio ?? -1;
      _subtitle = _source.defaultSubtitle ?? -1;
    }
    _normalizeTracks();
  }

  void _normalizeTracks() {
    if (!_source.streams.any((s) => s.type == 'Audio' && s.index == _audio))
      _audio = -1;
    if (!_source.streams
        .any((s) => s.type == 'Subtitle' && s.index == _subtitle))
      _subtitle = -1;
  }

  List<DropdownMenuItem<int>> _tracks(String type) => [
        DropdownMenuItem(
            value: -1, child: Text(type == 'Audio' ? '服务器默认音轨' : '关闭字幕')),
        for (final track in _source.streams.where((t) => t.type == type))
          DropdownMenuItem(
              value: track.index,
              child: Text(
                  track.label.isEmpty ? '轨道 ${track.index}' : track.label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis)),
      ];
  @override
  Widget build(BuildContext context) => AlertDialog(
          title: const Text('播放设置'),
          content: SizedBox(
              width: 440,
              child: SingleChildScrollView(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                DropdownButtonFormField<String>(
                    initialValue: _source.id,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '媒体版本'),
                    items: widget.sources
                        .map((s) => DropdownMenuItem(
                            value: s.id,
                            child: Text(s.label,
                                maxLines: 2, overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: (value) => setState(() {
                          _source =
                              widget.sources.firstWhere((s) => s.id == value);
                          _audio = _source.defaultAudio ?? -1;
                          _subtitle = _source.defaultSubtitle ?? -1;
                          _normalizeTracks();
                        })),
                DropdownButtonFormField<MediaServerPlayMode>(
                    initialValue: _mode,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '播放方式'),
                    items: const [
                      DropdownMenuItem(
                          value: MediaServerPlayMode.auto, child: Text('自动协商')),
                      DropdownMenuItem(
                          value: MediaServerPlayMode.original,
                          child: Text('原画优先（不允许转码）')),
                      DropdownMenuItem(
                          value: MediaServerPlayMode.transcode,
                          child: Text('服务器转码（H.264 / AAC）'))
                    ],
                    onChanged: (value) => setState(() => _mode = value!)),
                DropdownButtonFormField<int>(
                    initialValue: _bitrate,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '带宽上限'),
                    items: [
                      if (![2, 4, 8, 15, 30, 60, 120]
                          .contains(_bitrate / 1000000))
                        DropdownMenuItem(
                            value: _bitrate,
                            child: Text('${_bitrate / 1000000} Mbps')),
                      for (final mbps in [2, 4, 8, 15, 30, 60, 120])
                        DropdownMenuItem(
                            value: mbps * 1000000, child: Text('$mbps Mbps'))
                    ],
                    onChanged: (value) => _bitrate = value!),
                DropdownButtonFormField<int>(
                    key: ValueKey('audio-${_source.id}'),
                    initialValue: _tracks('Audio').any((t) => t.value == _audio)
                        ? _audio
                        : -1,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '音轨'),
                    items: _tracks('Audio'),
                    onChanged: (value) => _audio = value!),
                DropdownButtonFormField<int>(
                    key: ValueKey('subtitle-${_source.id}'),
                    initialValue:
                        _tracks('Subtitle').any((t) => t.value == _subtitle)
                            ? _subtitle
                            : -1,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: '字幕'),
                    items: _tracks('Subtitle'),
                    onChanged: (value) => _subtitle = value!),
                const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text('自动模式尽量保留原始画质；转码受服务器权限和性能影响。')),
              ]))),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('取消')),
            FilledButton(
                onPressed: () => Navigator.pop(
                    context,
                    MediaServerPlaybackOptions(
                        sourceId: _source.id,
                        audioIndex: _audio < 0 ? null : _audio,
                        subtitleIndex: _subtitle,
                        maxBitrate: _bitrate,
                        mode: _mode)),
                child: const Text('应用'))
          ]);
}
