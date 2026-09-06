import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'harmony_navigation_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class ResponsiveAppShell extends StatelessWidget {
  final bool desktop, fullScreen;
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final Widget child;
  const ResponsiveAppShell({super.key, required this.desktop, required this.fullScreen,
    required this.selectedIndex, required this.onSelected, required this.child});
  static const destinations = [
    (label: '视频库', icon: CupertinoIcons.play_rectangle, selected: CupertinoIcons.play_rectangle_fill),
    (label: '音频库', icon: CupertinoIcons.music_note_list, selected: CupertinoIcons.music_note_list),
    (label: '媒体库', icon: CupertinoIcons.square_stack_3d_up, selected: CupertinoIcons.square_stack_3d_up_fill),
    (label: '设置', icon: CupertinoIcons.gear, selected: CupertinoIcons.gear_solid),
  ];
  @override Widget build(BuildContext context) => LayoutBuilder(builder: (context, size) {
    final colors = Theme.of(context).colorScheme;
    if (fullScreen) return child;
    // Nested page Scaffolds need the navigation's measured height reserved,
    // including large text and the system inset, to keep their FABs reachable.
    if (!desktop || size.maxWidth < 840) return Scaffold(body: child,
      bottomNavigationBar: HarmonyNavigationBar(selectedIndex: selectedIndex, onSelected: onSelected, destinations: destinations));
    final expanded = size.maxWidth >= 1200;
    return CallbackShortcuts(bindings: {
      SingleActivator(LogicalKeyboardKey.digit1, control: true): () => onSelected(0),
      SingleActivator(LogicalKeyboardKey.digit2, control: true): () => onSelected(1),
      SingleActivator(LogicalKeyboardKey.digit3, control: true): () => onSelected(2),
      SingleActivator(LogicalKeyboardKey.digit4, control: true): () => onSelected(3),
    }, child: Focus(autofocus: true, child: Scaffold(body: Row(children: [
      Container(width: expanded ? 220 : 88, decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [colors.surfaceContainerLow, colors.primaryContainer.withValues(alpha: .4)]),
        border: Border(right: BorderSide(color: colors.outlineVariant.withValues(alpha: .6)))),
        child: SafeArea(child: Column(children: [
          Padding(padding: EdgeInsets.symmetric(horizontal: expanded ? 20 : 16, vertical: 28),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.asset('Assets/icon.png', width: 40, height: 40,
                errorBuilder: (_, __, ___) => Icon(Icons.play_circle, size: 40, color: colors.primary))),
              if (expanded) ...[const SizedBox(width: 12), Expanded(child: Text('AloePlayer',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)))],
            ])),
          Expanded(child: ListView(padding: EdgeInsets.zero, children: [for (var i = 0; i < destinations.length; i++) Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            child: Tooltip(message: '${destinations[i].label} · Ctrl+${i + 1}', child: Material(
              color: selectedIndex == i ? colors.surfaceContainerLowest : Colors.transparent,
              elevation: selectedIndex == i ? 3 : 0, shadowColor: colors.primary.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(16), child: InkWell(
                borderRadius: BorderRadius.circular(16), onTap: () => onSelected(i),
                child: Semantics(selected: selectedIndex == i, button: true, label: destinations[i].label,
                  child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16), child: expanded
                    ? Row(children: [Icon(selectedIndex == i ? destinations[i].selected : destinations[i].icon, color: selectedIndex == i ? colors.primary : colors.onSurfaceVariant),
                        const SizedBox(width: 16), Expanded(child: Text(destinations[i].label, style: TextStyle(
                          color: selectedIndex == i ? colors.primary : colors.onSurfaceVariant,
                          fontWeight: selectedIndex == i ? FontWeight.w700 : FontWeight.w500)))])
                    : Icon(selectedIndex == i ? destinations[i].selected : destinations[i].icon,
                        color: selectedIndex == i ? colors.primary : colors.onSurfaceVariant)),
                ),
              ),
            ))),
          ])),
          if (expanded && size.maxHeight >= 640) Padding(padding: const EdgeInsets.all(24), child: Text('本地与远程\n随时接着看',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.onSurfaceVariant, height: 1.8))),
        ]))),
      Expanded(child: child),
    ]))));
  });
}
