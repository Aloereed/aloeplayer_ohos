import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/widgets/local_import_sheet.dart';
import 'package:aloeplayer/theme/app_theme.dart';

void main() {
  testWidgets('small phone exposes both imports and direct playback before scrolling with large text', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    LocalImportAction? result;
    await tester.pumpWidget(MaterialApp(theme: buildAloeTheme(Brightness.light),
      builder: (context, child) => MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.5)), child: child!),
      home: Builder(builder: (context) => Scaffold(body: TextButton(
        onPressed: () async { result = await showLocalImportSheet(context, destination: 'Downloads/com.aloereed.aloeplayer/Videos'); },
        child: const Text('add'))))));
    await tester.tap(find.text('add'));
    await tester.pumpAndSettle();
    for (final label in ['复制到媒体库', '添加快捷方式', '打开文件', '打开 URL']) {
      expect(find.text(label).hitTestable(), findsOneWidget);
      expect(tester.getRect(find.text(label)).bottom,
        lessThanOrEqualTo(tester.getRect(find.byType(SingleChildScrollView)).bottom));
    }
    expect(find.text('播放历史'), findsNothing);
    final shortcut = find.text('添加快捷方式');
    expect(shortcut.hitTestable(), findsOneWidget);
    await tester.tap(shortcut);
    await tester.pumpAndSettle();
    expect(result, LocalImportAction.shortcut);
    expect(tester.takeException(), isNull);
  });
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
      final shortcut = find.text('添加快捷方式');
      await tester.ensureVisible(shortcut);
      await tester.pumpAndSettle();
      await tester.tap(shortcut);
      await tester.pumpAndSettle();
      expect(result, LocalImportAction.shortcut);
      expect(tester.takeException(), isNull);
    });
  }
  for (final action in {'复制到媒体库': LocalImportAction.copy, '打开文件': LocalImportAction.playFile, '打开 URL': LocalImportAction.playUrl}.entries) {
    testWidgets('${action.key} returns its original action', (tester) async {
      LocalImportAction? result;
      await tester.pumpWidget(MaterialApp(home: Builder(builder: (context) => Scaffold(body: TextButton(
        onPressed: () async { result = await showLocalImportSheet(context, destination: 'Videos'); },
        child: const Text('add'))))));
      await tester.tap(find.text('add'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(action.key));
      await tester.pumpAndSettle();
      expect(result, action.value);
      expect(tester.takeException(), isNull);
    });
  }
}
