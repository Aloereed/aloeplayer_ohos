import 'package:flutter/material.dart';

class HoverableBuilder extends StatefulWidget {
  final Widget Function(BuildContext context, bool isHovered) builder;
  const HoverableBuilder({Key? key, required this.builder}) : super(key: key);
  @override
  _HoverableBuilderState createState() => _HoverableBuilderState();
}

class _HoverableBuilderState extends State<HoverableBuilder> {
  bool _isHovered = false;
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: widget.builder(context, _isHovered),
    );
  }
}
