import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Blocks the entire player hit-test and focus tree while retaining one exit.
class PlayerInteractionLock extends StatefulWidget {
  final Widget child;
  final ValueChanged<bool>? onLockChanged;
  final bool controlsVisible;
  const PlayerInteractionLock(
      {super.key,
      required this.child,
      this.onLockChanged,
      this.controlsVisible = true});
  @override
  State<PlayerInteractionLock> createState() => _PlayerInteractionLockState();
}

class _PlayerInteractionLockState extends State<PlayerInteractionLock> {
  bool _locked = false;
  bool _buttonVisible = true;
  Timer? _hideTimer;
  final _focus = FocusNode();
  @override
  void initState() {
    super.initState();
    _scheduleHide();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) setState(() => _buttonVisible = false);
    });
  }

  void _reveal() {
    if (!_buttonVisible) setState(() => _buttonVisible = true);
    _scheduleHide();
  }

  @override
  void didUpdateWidget(covariant PlayerInteractionLock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.controlsVisible && widget.controlsVisible) {
      _buttonVisible = true;
      _scheduleHide();
    }
  }

  void _set(bool value) {
    setState(() {
      _locked = value;
      _buttonVisible = true;
    });
    _scheduleHide();
    widget.onLockChanged?.call(value);
    if (value) _focus.requestFocus();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_locked,
      child: Focus(
          focusNode: _focus,
          onKeyEvent: (_, event) =>
              _locked ? KeyEventResult.handled : KeyEventResult.ignored,
          child: Stack(fit: StackFit.expand, children: [
            ExcludeFocus(
                excluding: _locked,
                child: Listener(
                    onPointerDown: _locked ? null : (_) => _reveal(),
                    child:
                        IgnorePointer(ignoring: _locked, child: widget.child))),
            if (_locked)
              Positioned.fill(
                  child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: _reveal,
                      child: const SizedBox.expand())),
            if (_buttonVisible && (_locked || widget.controlsVisible))
              Positioned(
                  right: 12,
                  top: MediaQuery.sizeOf(context).height * .38,
                  child: SafeArea(
                      child: Material(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(24),
                          child: Semantics(
                              button: true,
                              label: _locked ? '已锁定，长按解锁' : '锁定屏幕',
                              child: InkWell(
                                  borderRadius: BorderRadius.circular(24),
                                  onTapDown: (_) => _hideTimer?.cancel(),
                                  onTapCancel: _scheduleHide,
                                  onTap: _locked ? _reveal : () => _set(true),
                                  onLongPress:
                                      _locked ? () => _set(false) : null,
                                  child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                                _locked
                                                    ? Icons.lock
                                                    : Icons.lock_open,
                                                color: Colors.white,
                                                semanticLabel:
                                                    _locked ? '长按解锁' : '锁定屏幕'),
                                            if (_locked)
                                              const Text('长按解锁',
                                                  style: TextStyle(
                                                      color: Colors.white,
                                                      fontSize: 12)),
                                          ])))))))
          ])));
}
