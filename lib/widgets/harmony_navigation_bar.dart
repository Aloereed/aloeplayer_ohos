import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// A small, clipped glass surface keeps blur cost independent of library size.
class HarmonyNavigationBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelected;
  final List<({String label, IconData icon, IconData selected})> destinations;
  const HarmonyNavigationBar({super.key, required this.selectedIndex, required this.onSelected, required this.destinations});
  @override Widget build(BuildContext context) {
    final theme = Theme.of(context), colors = Theme.of(context).colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final contrast = MediaQuery.highContrastOf(context);
    final radius = BorderRadius.circular(30);
    final content = DecoratedBox(decoration: BoxDecoration(
      borderRadius: radius,
      gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: dark
        ? [const Color(0xEE253758), const Color(0xF0152036)]
        : [Colors.white.withValues(alpha: contrast ? 1 : .94), const Color(0xE8EDF3FF)]),
      border: Border.all(color: Colors.white.withValues(alpha: dark ? .15 : .9))),
      child: Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9), child: Row(
        children: [for (var i = 0; i < destinations.length; i++) Expanded(child: Semantics(
          selected: selectedIndex == i, button: true, label: destinations[i].label,
          child: TextButton(style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 4),
            foregroundColor: selectedIndex == i ? colors.primary : colors.onSurfaceVariant,
            minimumSize: const Size(48, 48), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
            onPressed: () => onSelected(i), child: ExcludeSemantics(child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(selectedIndex == i ? destinations[i].selected : destinations[i].icon, size: 25,
                shadows: selectedIndex == i && !contrast ? [Shadow(color: colors.primary.withValues(alpha: .24), blurRadius: 15)] : null),
              const SizedBox(height: 4), Text(destinations[i].label, maxLines: 1,
                style: TextStyle(fontSize: 11, fontWeight: selectedIndex == i ? FontWeight.w700 : FontWeight.w500)),
            ]))),
        ))],
      )));
    return SafeArea(top: false, minimum: const EdgeInsets.fromLTRB(14, 0, 14, 10), child: Container(
      decoration: BoxDecoration(borderRadius: radius, boxShadow: [BoxShadow(
        color: (dark ? Colors.black : const Color(0xFF2857A4)).withValues(alpha: dark ? .25 : .12), blurRadius: 26, offset: const Offset(0, 6))]),
      child: ClipRRect(borderRadius: radius, child: contrast ? content : BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18), child: content))));
  }
}
