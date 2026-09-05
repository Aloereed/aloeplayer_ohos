import 'package:flutter/material.dart';

enum LocalImportAction { copy, shortcut, gallery, fileManager, folder, webdav, playFile, playUrl, history }

Future<LocalImportAction?> showLocalImportSheet(BuildContext context, {required String destination, String media = '视频'}) {
  final content = LocalImportSheet(destination: destination, media: media);
  if (MediaQuery.sizeOf(context).width >= 720) {
    return showDialog<LocalImportAction>(context: context, builder: (_) => Dialog(
      clipBehavior: Clip.antiAlias, child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780, maxHeight: 850), child: content)));
  }
  return showModalBottomSheet<LocalImportAction>(context: context, isScrollControlled: true,
    showDragHandle: true, useSafeArea: true,
    builder: (_) => FractionallySizedBox(heightFactor: .92, child: content));
}

class LocalImportSheet extends StatelessWidget {
  final String destination, media;
  const LocalImportSheet({super.key, required this.destination, this.media = '视频'});
  @override Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = Theme.of(context).colorScheme;
    void choose(LocalImportAction action) => Navigator.pop(context, action);
    Widget option({required IconData icon, required String title, required String detail,
      required String storage, required String action, required LocalImportAction value, bool primary = false}) =>
      Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(
        color: primary ? colors.primaryContainer.withValues(alpha: .45) : colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(20), border: Border.all(color: primary ? colors.primary.withValues(alpha: .4) : colors.outlineVariant)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 30, color: colors.primary), const SizedBox(height: 14),
          Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10), Text(detail, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 12), Text(storage, style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
          const SizedBox(height: 20),
          if (primary) FilledButton(onPressed: () => choose(value), child: Text(action))
          else OutlinedButton(onPressed: () => choose(value), child: Text(action)),
        ]));
    return SafeArea(child: Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(24, 16, 12, 8), child: Row(children: [
        Expanded(child: Text('添加本地$media', style: theme.textTheme.headlineSmall)),
        IconButton(tooltip: '关闭', onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
      ])),
      Expanded(child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(24, 8, 24, 24), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('选择适合你的添加方式', style: theme.textTheme.bodyLarge?.copyWith(color: colors.onSurfaceVariant)),
        const SizedBox(height: 20),
        LayoutBuilder(builder: (_, box) {
          final copy = option(icon: Icons.file_copy_outlined, title: '复制到媒体库',
            detail: '添加本地文件会复制一份到应用媒体目录，原文件保留。',
            storage: '占用一份额外存储空间 · 复制大文件需要时间', action: '选择文件并复制', value: LocalImportAction.copy, primary: true);
          final shortcut = option(icon: Icons.add_link_rounded, title: '添加快捷方式',
            detail: '只保存原文件的位置，不复制$media。适合不想额外占用空间的你。',
            storage: '移动或删除原文件、撤销文件访问权限后，快捷方式可能失效。', action: '选择文件创建快捷方式', value: LocalImportAction.shortcut);
          if (box.maxWidth < 600) return Column(children: [copy, const SizedBox(height: 16), shortcut]);
          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: copy), const SizedBox(width: 16), Expanded(child: shortcut)]);
        }),
        const SizedBox(height: 20),
        Text('复制后的保存位置', style: theme.textTheme.labelLarge), const SizedBox(height: 6),
        SelectableText(destination, style: theme.textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant)),
        const SizedBox(height: 10),
        ExpansionTile(tilePadding: EdgeInsets.zero, title: const Text('为什么添加文件会复制？'),
          children: [Padding(padding: const EdgeInsets.only(bottom: 16), child: Text(
            '鸿蒙对应用访问文件有限制。AloePlayer 将导入文件复制到 Downloads 下的应用目录，方便持续访问和管理。原文件不会被移动或删除；不想复制时，使用上面的快捷方式即可。',
            style: theme.textTheme.bodyMedium))]),
        const SizedBox(height: 12),
        Text('其他添加方式', style: theme.textTheme.titleSmall), const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (media == '视频') ActionChip(avatar: const Icon(Icons.photo_library_outlined, size: 18), label: const Text('从相册复制'), onPressed: () => choose(LocalImportAction.gallery)),
          ActionChip(avatar: const Icon(Icons.folder_open_outlined, size: 18), label: const Text('文件管理器'), onPressed: () => choose(LocalImportAction.fileManager)),
          ActionChip(avatar: const Icon(Icons.create_new_folder_outlined, size: 18), label: const Text('新建文件夹'), onPressed: () => choose(LocalImportAction.folder)),
          ActionChip(avatar: const Icon(Icons.cloud_download_outlined, size: 18), label: const Text('从 WebDAV 下载'), onPressed: () => choose(LocalImportAction.webdav)),
        ]),
        const SizedBox(height: 24), Text('只播放，不加入媒体库', style: theme.textTheme.titleSmall), const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          ActionChip(label: const Text('打开文件'), onPressed: () => choose(LocalImportAction.playFile)),
          ActionChip(label: const Text('打开网址'), onPressed: () => choose(LocalImportAction.playUrl)),
          ActionChip(label: const Text('播放历史'), onPressed: () => choose(LocalImportAction.history)),
        ]),
      ]))),
    ]));
  }
}
