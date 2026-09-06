import 'package:flutter/material.dart';

enum LocalImportAction { copy, shortcut, gallery, fileManager, folder, webdav, playFile, playUrl }

Future<LocalImportAction?> showLocalImportSheet(BuildContext context, {required String destination, String media = '视频'}) {
  final content = LocalImportSheet(destination: destination, media: media);
  if (MediaQuery.sizeOf(context).width >= 720) {
    return showDialog<LocalImportAction>(context: context, builder: (_) => Dialog(
      clipBehavior: Clip.antiAlias, child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 720), child: content)));
  }
  return showModalBottomSheet<LocalImportAction>(context: context, isScrollControlled: true,
    showDragHandle: true, useSafeArea: true,
    builder: (_) => FractionallySizedBox(heightFactor: .92, child: content));
}

class LocalImportSheet extends StatelessWidget {
  final String destination, media;
  const LocalImportSheet({super.key, required this.destination, this.media = '视频'});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = Theme.of(context).colorScheme;
    void choose(LocalImportAction action) => Navigator.pop(context, action);
    Widget option({required IconData icon, required String title, required String detail,
      required LocalImportAction value}) => Material(
      color: colors.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colors.outlineVariant)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(onTap: () => choose(value), child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(children: [
          Icon(icon, size: 24, color: colors.primary), const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 3),
            Text(detail, style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
          ])),
          const SizedBox(width: 8), Icon(Icons.chevron_right, size: 20, color: colors.onSurfaceVariant),
        ]),
      )),
    );
    Widget playButton(IconData icon, String title, LocalImportAction action) => OutlinedButton(
      onPressed: () => choose(action),
      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12)),
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(icon, size: 20), const SizedBox(width: 8), Flexible(child: Text(title, textAlign: TextAlign.center)),
      ]),
    );
    return SafeArea(child: Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 8, 8, 4), child: Row(children: [
        Expanded(child: Text('添加$media', style: theme.textTheme.titleLarge)),
        IconButton(tooltip: '关闭', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
      ])),
      Expanded(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 20), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
        option(icon: Icons.file_copy_outlined, title: '复制到媒体库',
          detail: '原文件保留，占用额外空间', value: LocalImportAction.copy),
        const SizedBox(height: 8),
        option(icon: Icons.add_link_rounded, title: '添加快捷方式',
          detail: '不复制文件，不占额外空间', value: LocalImportAction.shortcut),
        const SizedBox(height: 16),
        Text('直接播放', style: theme.textTheme.titleSmall), const SizedBox(height: 8),
        LayoutBuilder(builder: (_, box) {
          final columns = box.maxWidth >= 260 && MediaQuery.textScalerOf(context).scale(14) <= 21;
          final file = playButton(Icons.play_circle_outline, '打开文件', LocalImportAction.playFile);
          final url = playButton(Icons.link_rounded, '打开 URL', LocalImportAction.playUrl);
          return columns
            ? Row(children: [Expanded(child: file), const SizedBox(width: 8), Expanded(child: url)])
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [file, const SizedBox(height: 8), url]);
        }),
        const SizedBox(height: 20),
        Text('其他添加方式', style: theme.textTheme.titleSmall), const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (media == '视频') ActionChip(avatar: const Icon(Icons.photo_library_outlined, size: 18), label: const Text('从相册复制'), onPressed: () => choose(LocalImportAction.gallery)),
          ActionChip(avatar: const Icon(Icons.folder_open_outlined, size: 18), label: const Text('文件管理器'), onPressed: () => choose(LocalImportAction.fileManager)),
          ActionChip(avatar: const Icon(Icons.create_new_folder_outlined, size: 18), label: const Text('新建文件夹'), onPressed: () => choose(LocalImportAction.folder)),
          ActionChip(avatar: const Icon(Icons.cloud_download_outlined, size: 18), label: const Text('从 WebDAV 下载'), onPressed: () => choose(LocalImportAction.webdav)),
        ]),
        const SizedBox(height: 8),
        ExpansionTile(tilePadding: EdgeInsets.zero, title: const Text('保存位置与说明'), children: [
          Align(alignment: Alignment.centerLeft, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('复制后的保存位置', style: theme.textTheme.labelLarge), const SizedBox(height: 6),
            SelectableText(destination, style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
            const SizedBox(height: 12),
            Text('复制会保留原文件，大文件需要更多时间和存储空间。快捷方式只保存原文件位置；移动、删除原文件或撤销访问权限后可能失效。直接播放不会把文件加入媒体库。', style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
          ])),
        ]),
      ]))),
    ]));
  }
}
