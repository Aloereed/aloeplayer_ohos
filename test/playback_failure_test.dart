import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/widgets/playback_failure.dart';

void main() {
  testWidgets(
      'failure replaces spinner with accessible retry and back on short screens',
      (tester) async {
    tester.view.physicalSize = const Size(320, 200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var retries = 0;
    var backs = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: PlaybackFailure(
                message: '无法访问原文件，请重新添加快捷方式授权。' * 8,
                onRetry: () => retries++,
                onBack: () => backs++))));
    await tester.ensureVisible(find.text('重试'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重试'));
    await tester.tap(find.text('返回'));
    expect(retries, 1);
    expect(backs, 1);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
