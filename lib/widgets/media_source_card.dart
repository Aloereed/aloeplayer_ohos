import 'package:flutter/material.dart';

class MediaSourceCard extends StatelessWidget {
  final String name, address, protocol;
  final IconData icon;
  final VoidCallback onOpen;
  final VoidCallback? onEdit, onRemove;
  final bool active;
  const MediaSourceCard(
      {super.key,
      required this.name,
      required this.address,
      required this.protocol,
      required this.icon,
      required this.onOpen,
      this.onEdit,
      this.onRemove,
      this.active = false});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
              color: active
                  ? colors.primary.withValues(alpha: .45)
                  : colors.outlineVariant)),
      child: InkWell(
          onTap: onOpen,
          child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(children: [
                      Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                              color: colors.primaryContainer,
                              borderRadius: BorderRadius.circular(14)),
                          child: Icon(icon, color: colors.onPrimaryContainer)),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Text(protocol,
                              style: Theme.of(context)
                                  .textTheme
                                  .labelLarge
                                  ?.copyWith(color: colors.primary))),
                      if (onEdit != null || onRemove != null)
                        PopupMenuButton<String>(
                            tooltip: '管理 $name',
                            onSelected: (value) {
                              if (value == 'edit') onEdit?.call();
                              if (value == 'remove') onRemove?.call();
                            },
                            itemBuilder: (_) => [
                                  if (onEdit != null)
                                    const PopupMenuItem(
                                        value: 'edit',
                                        child: Text('编辑 / 重新登录')),
                                  if (onRemove != null)
                                    const PopupMenuItem(
                                        value: 'remove', child: Text('移除来源')),
                                ]),
                    ]),
                    const SizedBox(height: 18),
                    Text(name,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    Text(address,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: colors.onSurfaceVariant)),
                    const SizedBox(height: 18),
                    Row(children: [
                      Expanded(
                          child: Text(active ? '上次使用' : '浏览媒体',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelMedium
                                  ?.copyWith(color: colors.primary))),
                      Icon(Icons.arrow_forward_rounded,
                          size: 18, color: colors.primary)
                    ]),
                  ]))),
    );
  }
}
