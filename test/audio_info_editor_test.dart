import 'dart:async';
import 'package:aloeplayer/audiolibrary.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const channel = MethodChannel('samples.flutter.dev/ffmpegplugin');
  testWidgets('leaving editor while twelve tag reads finish is safe', (tester) async {
    final release = Completer<void>();
    var reads = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      reads++;
      await release.future;
      return ['getYear', 'getTrack', 'getDisc'].contains(call.method) ? 0 : '';
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(const MaterialApp(home: AudioInfoEditor(filePath: 'missing-review-audio.mp3')));
    expect(reads, 12);
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, '读取中…')).onPressed, isNull);
    await tester.pumpWidget(const SizedBox());
    release.complete();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty optional tags open and a native save failure is visible', (tester) async {
    var writes = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      if (call.method.startsWith('set')) {
        writes++;
        throw PlatformException(code: 'TAG_WRITE_FAILED');
      }
      return ['getYear', 'getTrack', 'getDisc'].contains(call.method) ? 0 : '';
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(const MaterialApp(home: AudioInfoEditor(filePath: 'missing-review-audio.mp3')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '保存'));
    await tester.pumpAndSettle();
    expect(writes, 1);
    expect(find.text('元信息保存失败，部分字段可能已写入，请重新打开检查'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
