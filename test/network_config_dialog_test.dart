import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aloeplayer/pages/servers_page.dart';

void main() {
  testWidgets(
      'small-screen WebDAV configuration exposes connection test and validates before networking',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(320, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: ServersPage()));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加来源'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('WebDAV').last);
    await tester.pumpAndSettle();
    expect(find.text('测试连接'), findsOneWidget);
    await tester.tap(find.text('测试连接'));
    await tester.pumpAndSettle();
    expect(find.text('请填写服务器名称和主机地址'), findsOneWidget);
    expect(find.text('添加服务器'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
  });
}
