import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/pages/private_space_page.dart';
import 'package:aloeplayer/services/private_space.dart';

void main() {
  late Directory temp;
  late PrivateSpace space;
  String? secret;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('private-page-');
    secret = null;
    space = PrivateSpace(
        directory: () async => Directory('${temp.path}/vault'),
        readSecret: () async => secret,
        writeSecret: (value) async {
          secret = value;
        });
    await space.initialize();
    await space.configure('123456');
    final file =
        await File('${temp.path}/private-title.mp4').writeAsBytes([1, 2, 3]);
    await space.importFile(file.path);
    space.lock();
  });
  tearDown(() async {
    space.dispose();
    await temp.delete(recursive: true);
  });
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 25)));
      await tester.pump(const Duration(milliseconds: 30));
    }
    await tester.pumpAndSettle();
  }

  testWidgets(
      'private titles are hidden before PIN and immediately after backgrounding on narrow screens',
      (tester) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(), home: PrivateSpacePage(space: space)));
    await settle(tester);
    expect(find.text('private-title.mp4'), findsNothing);
    await tester.enterText(find.byType(TextField).first, '000000');
    await tester.tap(find.text('解锁'));
    await settle(tester);
    expect(find.text('PIN 不正确'), findsOneWidget);
    expect(find.text('private-title.mp4'), findsNothing);
    await tester.enterText(find.byType(TextField).first, '123456');
    await tester.tap(find.text('解锁'));
    await settle(tester);
    expect(find.text('private-title.mp4'), findsOneWidget);
    expect(tester.takeException(), isNull);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pumpAndSettle();
    expect(find.text('private-title.mp4'), findsNothing);
    expect(find.text('输入 PIN 解锁'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(space.unlocked, isFalse);
    await tester.pumpWidget(const SizedBox());
  });
}
