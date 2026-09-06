import 'package:flutter/cupertino.dart' show CupertinoSwitch;
import 'package:flutter/material.dart';

class HarmonySwitchTile extends StatelessWidget {
  final Widget title;
  final Widget? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final EdgeInsetsGeometry? contentPadding;
  const HarmonySwitchTile({super.key, required this.title, this.subtitle,
    required this.value, this.onChanged, this.contentPadding});
  @override Widget build(BuildContext context) => ListTile(
    contentPadding: contentPadding, title: title, subtitle: subtitle,
    onTap: onChanged == null ? null : () => onChanged!(!value),
    trailing: CupertinoSwitch(value: value, onChanged: onChanged,
      activeTrackColor: Theme.of(context).colorScheme.primary));
}
