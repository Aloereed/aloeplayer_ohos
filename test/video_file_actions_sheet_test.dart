import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/theme/app_theme.dart';
import 'package:aloeplayer/widgets/video_file_actions_sheet.dart';

void main() {
  testWidgets('file actions scroll on short screens and explain shortcut removal', (tester) async {
    for (final size in [const Size(320, 568), const Size(700, 320), const Size(1280, 800)]) {
      tester.view.physicalSize = size; tester.view.devicePixelRatio = 1;
      VideoFileAction? selected;
      await tester.pumpWidget(MaterialApp(theme: buildAloeTheme(Brightness.dark),
        builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.5)), child: child!),
        home: Builder(builder: (context) => Scaffold(body: TextButton(
          onPressed: () async { selected = await showVideoFileActions(context, name: '一个非常长的电影名称_家庭旅行录像.mp4',
            details: '快捷方式 · 3 天前', thumbnail: Future<Uint8List?>.value(null), shortcut: true); }, child: const Text('open'))))));
      await tester.tap(find.text('open')); await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('移除快捷方式'), 250);
      expect(find.text('仅移除链接，原视频保留'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('移除快捷方式')); await tester.pumpAndSettle();
      expect(selected, VideoFileAction.delete);
      await tester.pumpWidget(const SizedBox());
    }
    tester.view.resetPhysicalSize(); tester.view.resetDevicePixelRatio();
  });
}
