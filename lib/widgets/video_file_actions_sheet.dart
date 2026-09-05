import 'dart:typed_data';
import 'package:flutter/material.dart';

enum VideoFileAction { play, favorite, refreshThumbnail, share, cast, convert, extractSubtitle, extractAudio, delete }

Future<VideoFileAction?> showVideoFileActions(BuildContext context, {
  required String name, required String details, required Future<Uint8List?> thumbnail,
  bool favorite = false, bool shortcut = false, bool conversionBusy = false,
}) {
  final content = VideoFileActionsSheet(name: name, details: details, thumbnail: thumbnail,
    favorite: favorite, shortcut: shortcut, conversionBusy: conversionBusy);
  if (MediaQuery.sizeOf(context).width >= 840) {
    return showDialog<VideoFileAction>(context: context, builder: (_) => Dialog(
      clipBehavior: Clip.antiAlias, child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700, maxHeight: 760), child: content)));
  }
  return showModalBottomSheet<VideoFileAction>(context: context, useSafeArea: true,
    isScrollControlled: true, showDragHandle: true,
    builder: (_) => FractionallySizedBox(heightFactor: .9, child: content));
}

class VideoFileActionsSheet extends StatelessWidget {
  final String name, details;
  final Future<Uint8List?> thumbnail;
  final bool favorite, shortcut, conversionBusy;
  const VideoFileActionsSheet({super.key, required this.name, required this.details, required this.thumbnail,
    this.favorite = false, this.shortcut = false, this.conversionBusy = false});
  @override Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = Theme.of(context).colorScheme;
    void choose(VideoFileAction action) => Navigator.pop(context, action);
    Widget action(IconData icon, String title, String detail, VideoFileAction value, {bool enabled = true, bool destructive = false}) =>
      ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        leading: Icon(icon, color: destructive ? colors.error : colors.primary),
        title: Text(title, style: destructive ? TextStyle(color: colors.error) : null),
        subtitle: Text(detail), enabled: enabled, onTap: enabled ? () => choose(value) : null);
    final placeholder = ColoredBox(color: colors.primaryContainer,
      child: Icon(Icons.movie_outlined, size: 32, color: colors.onPrimaryContainer));
    return SafeArea(child: Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(24, 12, 12, 8), child: Row(children: [
        Expanded(child: Text('视频操作', style: theme.textTheme.titleLarge)),
        IconButton(tooltip: '关闭', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
      ])),
      Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
        Padding(padding: const EdgeInsets.all(8), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          ClipRRect(borderRadius: BorderRadius.circular(12), child: SizedBox(width: 84, height: 64,
            child: FutureBuilder<Uint8List?>(future: thumbnail, builder: (_, image) => image.data == null ? placeholder
              : Image.memory(image.data!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => placeholder)))),
          const SizedBox(width: 14), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name, maxLines: 3, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
            const SizedBox(height: 6), Text(details, style: theme.textTheme.bodySmall),
            if (shortcut) Padding(padding: const EdgeInsets.only(top: 6), child: Text('快捷方式 · 原视频未复制',
              style: theme.textTheme.bodySmall?.copyWith(color: colors.primary))),
          ])),
        ])),
        const SizedBox(height: 12), FilledButton.icon(onPressed: () => choose(VideoFileAction.play),
          icon: const Icon(Icons.play_arrow_rounded), label: const Text('播放视频')),
        const SizedBox(height: 12),
        action(favorite ? Icons.favorite_rounded : Icons.favorite_border_rounded,
          favorite ? '取消收藏' : '收藏视频', '在视频库中快速找到', VideoFileAction.favorite),
        action(Icons.refresh_rounded, '重新生成缩略图', '缩略图缺失或不正确时重新读取', VideoFileAction.refreshThumbnail),
        const Divider(height: 24),
        action(Icons.share_outlined, '分享', '使用系统分享菜单', VideoFileAction.share),
        action(Icons.cast_rounded, '投屏', '连接同一网络中的播放设备', VideoFileAction.cast),
        const Divider(height: 24),
        action(Icons.video_file_outlined, '转换为 MP4', conversionBusy ? '当前已有转换任务' : '打开转换选项', VideoFileAction.convert, enabled: !conversionBusy),
        action(Icons.subtitles_outlined, '抽取字幕', '查看并导出内挂字幕轨道', VideoFileAction.extractSubtitle),
        action(Icons.audiotrack_outlined, '抽取音轨', '查看并导出音频轨道', VideoFileAction.extractAudio),
        const Divider(height: 24),
        action(Icons.delete_outline, shortcut ? '移除快捷方式' : '删除视频',
          shortcut ? '仅移除链接，原视频保留' : '删除媒体库中的这个文件', VideoFileAction.delete, destructive: true),
      ])),
    ]));
  }
}
