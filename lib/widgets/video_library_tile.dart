import 'dart:typed_data';
import 'package:flutter/material.dart';

class VideoTileInfo {
  final Duration duration;
  final double progress;
  final bool hdr;
  const VideoTileInfo({this.duration = Duration.zero, this.progress = 0, this.hdr = false});
}

class VideoLibraryTile extends StatefulWidget {
  final String name, details;
  final bool list, shortcut, favorite;
  final Future<Uint8List?> thumbnail;
  final Future<VideoTileInfo> info;
  final VoidCallback onPlay, onOptions, onFavorite;
  const VideoLibraryTile({super.key, required this.name, required this.details,
    required this.thumbnail, required this.info, required this.onPlay,
    required this.onOptions, required this.onFavorite, this.list = false,
    this.shortcut = false, this.favorite = false});
  @override State<VideoLibraryTile> createState() => _VideoLibraryTileState();
}
class _VideoLibraryTileState extends State<VideoLibraryTile> {
  bool _hovered = false;
  Widget _badge(String text) => DecoratedBox(decoration: BoxDecoration(color: Colors.black.withValues(alpha: .65),
    borderRadius: BorderRadius.circular(6)), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      child: Text(text, style: const TextStyle(color: Colors.white, fontSize: 11))));
  String _duration(Duration d) => '${d.inHours > 0 ? '${d.inHours}:' : ''}${(d.inMinutes % 60).toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
  Widget _image(VideoTileInfo info) {
    final colors = Theme.of(context).colorScheme;
    final placeholder = DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
      begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [colors.primaryContainer, colors.surfaceContainerHighest])),
      child: Center(child: Icon(Icons.movie_outlined, size: widget.list ? 30 : 42, color: colors.onPrimaryContainer.withValues(alpha: .65))));
    return AspectRatio(aspectRatio: 16 / 9, child: Stack(fit: StackFit.expand, children: [
      FutureBuilder<Uint8List?>(future: widget.thumbnail, builder: (_, snapshot) => snapshot.data == null ? placeholder
        : Image.memory(snapshot.data!, fit: BoxFit.cover, gaplessPlayback: true, errorBuilder: (_, __, ___) => placeholder)),
      if (_hovered) ColoredBox(color: Colors.black.withValues(alpha: .18),
        child: const Center(child: Icon(Icons.play_circle_fill_rounded, size: 44, color: Colors.white))),
      if (!widget.list && (info.hdr || widget.shortcut)) Positioned(left: 8, right: 42, top: 8, child: Wrap(spacing: 4, runSpacing: 4,
        children: [if (widget.shortcut) _badge('快捷方式'), if (info.hdr) _badge('HDR')])),
      if (!widget.list) Positioned(right: 4, top: 4, child: IconButton(
        tooltip: widget.favorite ? '取消收藏' : '收藏', onPressed: widget.onFavorite,
        style: IconButton.styleFrom(backgroundColor: Colors.black.withValues(alpha: .3), minimumSize: const Size(32, 32), padding: const EdgeInsets.all(6)),
        icon: Icon(widget.favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          color: widget.favorite ? const Color(0xFFFFA9BB) : Colors.white, size: 18))),
      if (info.duration > Duration.zero) Positioned(right: 8, bottom: 8, child: _badge(_duration(info.duration))),
      if (info.progress > 0) Positioned(left: 0, right: 0, bottom: 0,
        child: LinearProgressIndicator(value: info.progress.clamp(0.0, 1.0), minHeight: 3,
          backgroundColor: Colors.black26, color: colors.primary)),
    ]));
  }
  @override Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = Theme.of(context).colorScheme;
    return MouseRegion(onEnter: (_) => setState(() => _hovered = true), onExit: (_) => setState(() => _hovered = false),
      child: Card(elevation: 0, margin: widget.list ? const EdgeInsets.symmetric(horizontal: 16, vertical: 5) : EdgeInsets.zero,
        color: _hovered ? colors.surfaceContainerHigh : colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: _hovered ? colors.primary.withValues(alpha: .5) : colors.outlineVariant.withValues(alpha: .65))),
        clipBehavior: Clip.antiAlias, child: InkWell(onTap: widget.onPlay,
          onLongPress: widget.onOptions, onSecondaryTap: widget.onOptions,
          child: FutureBuilder<VideoTileInfo>(future: widget.info, builder: (_, snapshot) {
            final info = snapshot.data ?? const VideoTileInfo();
            final name = Text(widget.name, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600, height: 1.35));
            final detail = Text(info.progress > 0 ? '已观看 ${(info.progress * 100).round()}% · ${widget.details}' : widget.details,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant));
            if (widget.list) return Padding(padding: const EdgeInsets.all(12), child: Row(children: [
              SizedBox(width: 96, child: ClipRRect(borderRadius: BorderRadius.circular(10), child: _image(info))),
              const SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min, children: [name, const SizedBox(height: 6), detail])),
              IconButton(tooltip: '更多操作', onPressed: widget.onOptions, icon: const Icon(Icons.more_horiz)),
            ]));
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _image(info), Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(12, 10, 8, 6), child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [name, const Spacer(), Row(children: [
                  Expanded(child: detail), SizedBox(width: 28, height: 28, child: IconButton(tooltip: '更多操作',
                    padding: EdgeInsets.zero, onPressed: widget.onOptions, icon: const Icon(Icons.more_horiz, size: 20))),
                ]),
              ]))),
            ]);
          }))),
    );
  }
}
