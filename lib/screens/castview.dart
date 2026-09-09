/*
 * Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 * http://www.apache.org/licenses/LICENSE-2.0
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SystemCastStatus {
  final String state;
  final String message;
  final Duration position;
  const SystemCastStatus(this.state,
      {this.message = '', this.position = Duration.zero});
  static SystemCastStatus? parse(Object? payload) {
    try {
      final data = payload is String ? jsonDecode(payload) : payload;
      if (data is! Map || data['state'] is! String) return null;
      final ms = data['positionMs'];
      return SystemCastStatus(data['state'] as String,
          message: data['message'] is String ? data['message'] as String : '',
          position: Duration(
              milliseconds:
                  ms is num && ms.isFinite ? ms.clamp(0, 1e15).round() : 0));
    } catch (_) {
      return null;
    }
  }
}

class CastViewController {
  final MethodChannel channel;
  final _events = StreamController<SystemCastStatus>.broadcast(sync: true);
  bool _disposed = false;
  CastViewController(this.channel) {
    channel.setMethodCallHandler(_handle);
  }
  Stream<SystemCastStatus> get statuses => _events.stream;
  Future<void> _handle(MethodCall call) async {
    if (_disposed || call.method != 'castState') return;
    final status = SystemCastStatus.parse(call.arguments);
    if (status != null) _events.add(status);
  }

  Future<void> sendMessageToOhosView(String method, String value) async {
    if (_disposed) throw StateError('系统投播页面已关闭');
    await channel
        .invokeMethod<void>(method, value)
        .timeout(const Duration(seconds: 20));
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    channel.setMethodCallHandler(null);
    unawaited(_events.close());
  }
}

class CastExample extends StatefulWidget {
  final String initUri;
  final VoidCallback toggleFullScreen;
  final VoidCallback? onCastStarted;
  final Duration duration;
  const CastExample(
      {super.key,
      required this.initUri,
      required this.toggleFullScreen,
      this.onCastStarted,
      this.duration = Duration.zero});
  @override
  State<CastExample> createState() => _CastExampleState();
}

class _CastExampleState extends State<CastExample> {
  CastViewController? _controller;
  StreamSubscription<SystemCastStatus>? _subscription;
  SystemCastStatus _status = const SystemCastStatus('INITIALIZING');
  bool _busy = false;
  bool _started = false;
  String? _pendingPayload;
  double? _drag;

  void _created(int id) {
    if (!mounted) return;
    final controller = CastViewController(
        MethodChannel('com.aloereed.aloeplayer/castView$id'));
    _controller = controller;
    _subscription = controller.statuses.listen((status) {
      if (!mounted) return;
      setState(() => _status = status);
      if (status.state == 'PLAYING' && !_started) {
        _started = true;
        widget.onCastStarted?.call();
      }
    });
    _send('getMessageFromFlutterView', widget.initUri);
  }

  @override
  void didUpdateWidget(covariant CastExample oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initUri != widget.initUri && _controller != null) {
      _started = false;
      if (_busy)
        _pendingPayload = widget.initUri;
      else
        _send('newPlay', widget.initUri);
    }
  }

  Future<void> _send(String method, [String value = '']) async {
    if (_controller == null || _busy) return;
    setState(() => _busy = true);
    try {
      await _controller!.sendMessageToOhosView(method, value);
    } catch (error) {
      if (mounted)
        setState(() => _status = SystemCastStatus('ERROR',
            message: error is PlatformException
                ? (error.message ?? error.code)
                : error.toString()));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        final pending = _pendingPayload;
        _pendingPayload = null;
        if (pending != null) _send('newPlay', pending);
      }
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _controller?.dispose();
    super.dispose();
  }

  String get _label => switch (_status.state) {
        'READY' => '点击下方系统投播图标选择设备',
        'CONNECTING' => '正在连接接收设备…',
        'LOADING' => '已发送媒体，等待接收端播放…',
        'PLAYING' => '系统投播正在播放',
        'PAUSED' => '系统投播已暂停',
        'STOPPED' => '系统投播已停止',
        'COMPLETED' => '系统投播播放结束',
        'DISCONNECTED' => '设备已断开，可重新选择',
        'ERROR' => '系统投播失败：${_status.message}',
        _ => '正在准备系统投播…',
      };
  @override
  Widget build(BuildContext context) {
    final connected =
        ['PLAYING', 'PAUSED', 'LOADING', 'COMPLETED'].contains(_status.state);
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(12),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_label),
              if (_busy) const LinearProgressIndicator(),
              SizedBox(
                  height: 64,
                  child: OhosView(
                      viewType: 'com.aloereed.aloeplayer/castView',
                      onPlatformViewCreated: _created,
                      creationParams: const <String, dynamic>{},
                      creationParamsCodec: const StandardMessageCodec())),
              if (connected) ...[
                if (widget.duration > Duration.zero)
                  Slider(
                      value: (_drag ??
                              _status.position.inMilliseconds.toDouble())
                          .clamp(0, widget.duration.inMilliseconds.toDouble()),
                      max: widget.duration.inMilliseconds.toDouble(),
                      onChanged: _busy
                          ? null
                          : (value) => setState(() => _drag = value),
                      onChangeEnd: (value) async {
                        await _send('seek', value.round().toString());
                        if (mounted) setState(() => _drag = null);
                      }),
                Wrap(spacing: 8, children: [
                  TextButton.icon(
                      onPressed: _busy
                          ? null
                          : () => _send(
                              _status.state == 'PAUSED' ? 'play' : 'pause'),
                      icon: Icon(_status.state == 'PAUSED'
                          ? Icons.play_arrow
                          : Icons.pause),
                      label: Text(_status.state == 'PAUSED' ? '继续' : '暂停')),
                  TextButton(
                      onPressed: _busy ? null : () => _send('stopCasting'),
                      child: const Text('断开系统投播')),
                ]),
              ],
              if (_status.state == 'ERROR')
                Wrap(children: [
                  TextButton(
                      onPressed: _busy
                          ? null
                          : () => _send(
                              'getMessageFromFlutterView', widget.initUri),
                      child: const Text('重试准备')),
                  TextButton(
                      onPressed: () => Clipboard.setData(
                          ClipboardData(text: _status.message)),
                      child: const Text('复制错误')),
                ]),
              const Text('系统投播期间请保留此页面；关闭本页会结束系统投播。'),
            ])));
  }
}
