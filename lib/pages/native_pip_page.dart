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
  MethodChannel? _channel;
  bool _ready = false, _closing = false, _allowPop = false;
  String? _error;
  PipPlaybackResult? _returnState;
  bool _timerStopped = false;
  void _created(int id) {
    final channel = MethodChannel('aloeplayer/pip-view/$id');
    _channel = channel;
    widget.controller?.attach(channel);
    PlaybackSleepTimer.instance.attach(this, () async { _timerStopped = true; await channel.invokeMethod<void>('pause'); });
    channel.setMethodCallHandler((call) async {
      if (!mounted) return;
      if (call.method == 'position') {
        final state = call.arguments as Map;
        widget.onPosition?.call(PipPlaybackResult((state['positionMs'] as num).round(), state['playing'] == true));
      }
      if (call.method == 'completed') PlaybackSleepTimer.instance.consumeEnd(this);
      if (call.method == 'ready') setState(() => _ready = true);
      if (call.method == 'error') setState(() => _error = call.arguments as String);
    });
    channel.invokeMethod<void>('open').catchError((_) { if (mounted) setState(() => _error = '无法初始化系统播放器'); });
  }
  Future<void> _start() async {
    try { await _channel?.invokeMethod<void>('startPiP'); }
    on PlatformException catch (e) { if (mounted) setState(() => _error = e.message); }
  }
  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    try {
      final state = await _channel?.invokeMapMethod<String, dynamic>('stopPiP');
      if (state != null) _returnState = PipPlaybackResult((state['positionMs'] as num).round(), !_timerStopped && state['playing'] == true);
    } catch (_) {}
    if (!mounted) return;
    setState(() => _allowPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) Navigator.pop(context, _returnState ?? PipPlaybackResult(widget.positionMs, !_timerStopped && widget.playing)); });
  }
  @override void dispose() { widget.controller?.detach(); PlaybackSleepTimer.instance.detach(this, cancelTimer: false); _channel?.setMethodCallHandler(null); super.dispose(); }
  @override Widget build(BuildContext context) => PopScope(canPop: _allowPop, onPopInvokedWithResult: (didPop, _) { if (!didPop) _close(); },
    child: Scaffold(appBar: AppBar(title: const Text('系统画中画'), leading: IconButton(onPressed: _close, icon: const Icon(Icons.arrow_back))),
      body: Column(children: [
        Expanded(child: OhosView(viewType: 'aloeplayer/pip-view', onPlatformViewCreated: _created,
          creationParams: {'uri': widget.uri, 'positionMs': widget.positionMs, 'playing': widget.playing, 'headers': widget.headers}, creationParamsCodec: const StandardMessageCodec())),
        if (_error != null) Padding(padding: const EdgeInsets.all(12), child: Text(_error!)),
        if (!_ready && _error == null) const LinearProgressIndicator(),
        Padding(padding: const EdgeInsets.all(16), child: Wrap(spacing: 12, children: [
          FilledButton.icon(onPressed: _ready ? _start : null, icon: const Icon(Icons.picture_in_picture_alt), label: const Text('开启系统画中画')),
          TextButton(onPressed: _close, child: const Text('返回原播放器')),
        ])),
      ])));
}
