import 'dart:async';
import '../services/sleep_timer.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A separate native surface owns system PiP. The original decoder stays paused
/// and receives the latest position when the user returns.
class PipPlaybackResult {
  final int positionMs;
  final bool playing;
  const PipPlaybackResult(this.positionMs, this.playing);
}

class NativePipController {
  MethodChannel? _channel;
  void attach(MethodChannel channel) { _channel = channel; }
  void detach() { _channel = null; }
  Future<void> play() async { await _channel?.invokeMethod<void>('play'); }
  Future<void> pause() async { await _channel?.invokeMethod<void>('pause'); }
  Future<void> seek(Duration position) async { await _channel?.invokeMethod<void>('seek', {'positionMs': position.inMilliseconds}); }
}

class NativePipPage extends StatefulWidget {
  final String uri;
  final int positionMs;
  final Map<String, String> headers;
  final bool playing;
  final NativePipController? controller;
  final void Function(PipPlaybackResult)? onPosition;
  const NativePipPage({super.key, required this.uri, required this.positionMs, this.headers = const {}, this.playing = true, this.controller, this.onPosition});
  @override State<NativePipPage> createState() => _NativePipPageState();
}
class _NativePipPageState extends State<NativePipPage> {
  static const _channel = MethodChannel('aloeplayer/system-pip');
  bool _closing = false, _allowPop = false;
  String? _error;
  String _phase = '正在打开系统画中画';
  PipPlaybackResult? _returnState;
  bool _timerStopped = false;
  Timer? _watchdog;

  @override void initState() {
    super.initState();
    _channel.setMethodCallHandler(_receive);
    widget.controller?.attach(_channel);
    PlaybackSleepTimer.instance.attach(this, () async {
      _timerStopped = true;
      await _channel.invokeMethod<void>('pause');
    });
    _watchdog = Timer(const Duration(seconds: 35), () {
      if (mounted) setState(() => _error = '画中画准备超时，可返回原播放器继续播放');
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _open());
  }
  Future<void> _open() async {
    if (!mounted) return;
    try {
      await _channel.invokeMethod<void>('open', {
        'uri': widget.uri, 'positionMs': widget.positionMs,
        'playing': widget.playing, 'headers': widget.headers,
      });
    } catch (_) {
      _watchdog?.cancel();
      if (mounted) setState(() => _error = '无法打开系统画中画，可返回原播放器继续播放');
    }
  }
  Future<void> _receive(MethodCall call) async {
    if (!mounted) return;
    if (call.method == 'position' || call.method == 'closed') {
      final state = call.arguments as Map;
      _returnState = PipPlaybackResult((state['positionMs'] as num).round(), !_timerStopped && state['playing'] == true);
      widget.onPosition?.call(_returnState!);
      if (call.method == 'closed') _finish();
    } else if (call.method == 'completed') {
      PlaybackSleepTimer.instance.consumeEnd(this);
    } else if (call.method == 'phase') {
      setState(() => _phase = call.arguments as String);
    } else if (call.method == 'ready') {
      _watchdog?.cancel();
    } else if (call.method == 'error') {
      _watchdog?.cancel();
      setState(() => _error = call.arguments as String);
    }
  }
  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    try { await _channel.invokeMethod<void>('close').timeout(const Duration(seconds: 5)); }
    catch (_) {}
    _finish();
  }
  void _finish() {
    if (!mounted || _allowPop) return;
    _watchdog?.cancel();
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.pop(context, _returnState ?? PipPlaybackResult(widget.positionMs, !_timerStopped && widget.playing));
    });
  }
  @override void dispose() {
    _watchdog?.cancel();
    widget.controller?.detach();
    PlaybackSleepTimer.instance.detach(this, cancelTimer: false);
    _channel.setMethodCallHandler(null);
    _channel.invokeMethod<void>('dispose').catchError((_) {});
    super.dispose();
  }
  @override Widget build(BuildContext context) => PopScope(
    canPop: _allowPop, onPopInvokedWithResult: (didPop, _) { if (!didPop) _close(); },
    child: Scaffold(
      appBar: AppBar(title: const Text('系统画中画'), leading: IconButton(onPressed: _close, icon: const Icon(Icons.arrow_back))),
      body: Center(child: Padding(padding: const EdgeInsets.all(24), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(_error == null ? Icons.picture_in_picture_alt : Icons.info_outline, size: 56, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 20),
        Text(_error ?? _phase, textAlign: TextAlign.center),
        const SizedBox(height: 20),
        if (_error == null) const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(height: 20),
        FilledButton(onPressed: _close, child: const Text('返回原播放器')),
      ]))),
    ),
  );
}
