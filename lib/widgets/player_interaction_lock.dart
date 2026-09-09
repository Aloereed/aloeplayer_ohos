import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Blocks the entire player hit-test and focus tree while retaining one exit.
class PlayerInteractionLock extends StatefulWidget {
  final Widget child;
  final ValueChanged<bool>? onLockChanged;
  const PlayerInteractionLock(
      {super.key, required this.child, this.onLockChanged});
  @override
  State<PlayerInteractionLock> createState() => _PlayerInteractionLockState();
}

class _PlayerInteractionLockState extends State<PlayerInteractionLock> {
  bool _locked = false;
  final _focus = FocusNode();
  void _set(bool value) {
    setState(() => _locked = value);
    widget.onLockChanged?.call(value);
    if (value) _focus.requestFocus();
  }

  @override
  void dispose() {
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
                child: IgnorePointer(ignoring: _locked, child: widget.child)),
            if (_locked)
              const Positioned.fill(
                  child: ModalBarrier(
                      dismissible: false, color: Colors.transparent)),
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
                                onTap: _locked ? () {} : () => _set(true),
                                onLongPress: _locked ? () => _set(false) : null,
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
