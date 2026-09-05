import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/widgets/local_import_sheet.dart';

void main() {
  for (final width in [320.0, 1100.0]) {
    testWidgets('copy and shortcut are explicit choices at width $width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      LocalImportAction? result;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (ctx) => Scaffold(body: TextButton(
        onPressed: () async { result = await showLocalImportSheet(ctx, destination: 'Downloads/com.aloereed.aloeplayer/Videos'); },
        child: const Text('add'))))));
      await tester.tap(find.text('add'));
      await tester.pumpAndSettle();
      expect(find.text('复制到媒体库'), findsOneWidget);
      expect(find.text('添加快捷方式'), findsOneWidget);
      expect(find.textContaining('原文件保留'), findsOneWidget);
      final shortcut = find.text('选择文件创建快捷方式');
      await tester.ensureVisible(shortcut);
      await tester.pumpAndSettle();
      await tester.tap(shortcut);
      await tester.pumpAndSettle();
      expect(result, LocalImportAction.shortcut);
      expect(tester.takeException(), isNull);
    });
  }
}
