import 'package:aloeplayer/widgets/media_url_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('sample link is underlined, replaces input and remains editable', (tester) async {
    await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) =>
      TextButton(onPressed: () => showMediaUrlDialog(context), child: const Text('打开')))));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '不是直链');
    await tester.tap(find.text('播放'));
    await tester.pump();
    expect(find.textContaining('未找到有效'), findsOneWidget);
    final text = tester.widget<Text>(find.text('测试链接'));
    expect(text.style?.decoration, TextDecoration.underline);
    await tester.tap(find.text('测试链接'));
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, sampleMediaUrl);
    expect(find.textContaining('未找到有效'), findsNothing);
    await tester.enterText(find.byType(TextField), 'https://example.com/own.mp4');
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'https://example.com/own.mp4');
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('打开视频直链'), findsNothing);
  });
}
