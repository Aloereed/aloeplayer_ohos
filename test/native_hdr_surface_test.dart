import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit_video/src/video/ohos_native_video.dart';

void main() {
  testWidgets('native video clears the Flutter target while preserving controls', (tester) async {
    final key = GlobalKey();
    Rect? rect;
    await tester.pumpWidget(Directionality(textDirection: TextDirection.ltr, child: Center(
      child: RepaintBoundary(key: key, child: SizedBox(width: 100, height: 100,
        child: Stack(children: [
          const Positioned.fill(child: ColoredBox(color: Colors.red)),
          Positioned(left: 20, top: 20, width: 60, height: 60,
            child: NativeVideoHole(devicePixelRatio: 2, onRect: (value) => rect = value)),
          const Positioned(left: 40, top: 40, width: 20, height: 20,
            child: ColoredBox(color: Colors.white)),
        ]))),
    )));
    expect(rect?.size, const Size(120, 120));
    final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 1);
      final pixels = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      int alpha(int x, int y) => pixels.getUint8((y * 100 + x) * 4 + 3);
      expect(alpha(10, 10), 255, reason: 'letterbox remains opaque');
      expect(alpha(30, 30), 0, reason: 'HDR surface is visible through Flutter');
      expect(alpha(50, 50), 255, reason: 'controls remain above the video');
      image.dispose();
    });
  });

  testWidgets('native bounds follow layout and do not notify after removal', (tester) async {
    final rects = <Rect>[];
    Widget frame(double left) => Directionality(textDirection: TextDirection.ltr,
      child: Stack(children: [Positioned(left: left, top: 15, width: 160, height: 90,
        child: NativeVideoHole(devicePixelRatio: 2, onRect: rects.add))]));
    await tester.pumpWidget(frame(10));
    expect(rects.last, const Rect.fromLTWH(20, 30, 320, 180));
    await tester.pumpWidget(frame(25));
    expect(rects.last, const Rect.fromLTWH(50, 30, 320, 180));
    final count = rects.length;
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(rects.length, count);
  });
}
