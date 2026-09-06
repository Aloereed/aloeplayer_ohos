import 'package:flutter/material.dart';

/// A compact, theme-aware marker; the tooltip also supplies its accessible name.
class MemberBadge extends StatelessWidget {
  const MemberBadge({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Tooltip(
      message: '会员权益',
      child: Container(
        width: 20,
        height: 20,
        decoration: BoxDecoration(
          color: colors.tertiaryContainer,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(Icons.diamond_rounded, size: 13, color: colors.onTertiaryContainer),
      ),
    );
  }
}

class MemberFeatureLabel extends StatelessWidget {
  final String text;
  final TextStyle? style;
  const MemberFeatureLabel(this.text, {super.key, this.style});

  @override
  Widget build(BuildContext context) => Text.rich(TextSpan(
    text: text,
    style: style,
    children: const [WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Padding(padding: EdgeInsets.only(left: 6), child: MemberBadge()),
    )],
  ));
}
