import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/screens/cast_screen_page.dart';
import 'package:aloeplayer/services/media_cast_service.dart';
void main() {
 testWidgets('casting page fits a narrow dark screen and retains actionable errors', (tester) async {
  tester.view.physicalSize = const Size(320, 600); tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize); addTearDown(tester.view.resetDevicePixelRatio);
  final service = MediaCastService.forTesting()..lastError = '设备拒绝命令 (UPnP 701)';
  await tester.pumpWidget(MaterialApp(theme:ThemeData.dark(),home:CastScreenPage(mediaPath:'https://example.com/测试.mp4',castService:service,discover:false)));
  await tester.pumpAndSettle();
  expect(find.text('投屏'),findsOneWidget); expect(find.text('复制错误详情'),findsOneWidget);
  expect(tester.takeException(),isNull);
  await tester.tap(find.byTooltip('手动添加设备')); await tester.pumpAndSettle();
  expect(find.text('设备描述地址'),findsOneWidget);
  await tester.tap(find.text('取消')); await tester.pumpAndSettle(); await tester.pump(const Duration(seconds:1));
  await tester.pumpWidget(const SizedBox()); service.dispose();
 });
}
