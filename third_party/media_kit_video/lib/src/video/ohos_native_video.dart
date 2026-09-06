import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import '../video_controller/ohos_video_controller/real.dart';

class OhosNativeVideo extends StatefulWidget {
  final OhosVideoController controller;
  const OhosNativeVideo({super.key, required this.controller});
  @override
  State<OhosNativeVideo> createState() => _OhosNativeVideoState();
}

class _OhosNativeVideoState extends State<OhosNativeVideo> {
  static int _nextViewId = 0;
  late final int _viewId = _nextViewId++;
  late final Future<void> _created;
  String? _error;

  @override
  void initState() {
    super.initState();
    _created = widget.controller.createNativeSurface(_viewId).catchError((Object error) {
      if (mounted) setState(() => _error = error.toString());
    });
  }

  Future<void> _rectChanged(Rect rect) async {
    await _created;
    if (!mounted || _error != null) return;
    try {
      await widget.controller.updateNativeRect(_viewId, rect);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
  }

  @override
  void dispose() {
    unawaited(widget.controller.detachNativeSurface(_viewId).catchError((Object error) {
      debugPrint('Native surface detach: $error');
    }));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<String?>(
    valueListenable: widget.controller.nativeSurfaceError,
    builder: (context, error, _) => Stack(fit: StackFit.expand, children: [
      NativeVideoHole(onRect: _rectChanged, devicePixelRatio: MediaQuery.devicePixelRatioOf(context)),
      if ((_error ?? error) != null) ColoredBox(color: Colors.black,
        child: Center(child: Text('原生视频输出失败，请关闭原生 HDR 模式。\n${_error ?? error}',
          style: const TextStyle(color: Colors.white)))),
    ]),
  );
}

/// Clears Flutter's video rectangle to reveal an independent ArkUI Surface.
/// Do not wrap this in an Opacity/saveLayer: that only clears an offscreen layer.
class NativeVideoHole extends LeafRenderObjectWidget {
  final ValueChanged<Rect> onRect;
  final double devicePixelRatio;
  const NativeVideoHole({super.key, required this.onRect, required this.devicePixelRatio});
  @override
  RenderObject createRenderObject(BuildContext context) => _NativeVideoHoleRender(onRect, devicePixelRatio);
  @override
  void updateRenderObject(BuildContext context, covariant _NativeVideoHoleRender renderObject) {
    renderObject.onRect = onRect;
    renderObject.devicePixelRatio = devicePixelRatio;
    renderObject.markNeedsPaint();
  }
}

class _NativeVideoHoleRender extends RenderBox {
  ValueChanged<Rect> onRect;
  double devicePixelRatio;
  Rect? _lastRect;
  _NativeVideoHoleRender(this.onRect, this.devicePixelRatio);
  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints.biggest;
  @override
  void performLayout() { size = constraints.biggest; }
  @override
  void paint(PaintingContext context, Offset offset) {
    context.canvas.drawRect(offset & size, Paint()..blendMode = BlendMode.clear);
    final logical = MatrixUtils.transformRect(getTransformTo(null), Offset.zero & size);
    final physical = Rect.fromLTRB(logical.left * devicePixelRatio, logical.top * devicePixelRatio,
      logical.right * devicePixelRatio, logical.bottom * devicePixelRatio);
    if (physical == _lastRect || !physical.isFinite || physical.isEmpty) return;
    _lastRect = physical;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (attached) onRect(physical);
    });
  }
}
