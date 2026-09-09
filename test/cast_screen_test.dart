import 'package:castscreen/castscreen.dart';
import 'package:xml/xml.dart';
import 'package:aloeplayer/models/cast_device.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/screens/cast_screen_page.dart';
import 'package:aloeplayer/services/media_cast_service.dart';

void main() {
  testWidgets(
      'casting page fits a narrow dark screen and retains actionable errors',
      (tester) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final service = MediaCastService.forTesting()
      ..lastError = '设备拒绝命令 (UPnP 701)';
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(),
        home: CastScreenPage(
            mediaPath: 'https://example.com/测试.mp4',
            castService: service,
            discover: false)));
    await tester.pumpAndSettle();
    expect(find.text('投屏'), findsOneWidget);
    expect(find.text('复制错误详情'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byTooltip('手动添加设备'));
    await tester.pumpAndSettle();
    expect(find.text('设备描述地址'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpWidget(const SizedBox());
    service.dispose();
  });
  testWidgets('active casting controls fit narrow screen with enlarged text',
      (tester) async {
    tester.view.physicalSize = const Size(320, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final device = CastDevice(
        device: Device.create(
            const Client('', '', 'http://127.0.0.1/device.xml', '', {}),
            XmlDocument.parse(
                '<root><device><friendlyName>客厅电视超长名称兼容性测试</friendlyName><UDN>uuid:test</UDN><serviceList><service><serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType><serviceId>transport</serviceId><controlURL>/av</controlURL></service></serviceList></device></root>'),
            'http://127.0.0.1/device.xml'),
        isConnected: true);
    final service = MediaCastService.forTesting()
      ..activeDevice = device
      ..devices = [device]
      ..awaitingPlayback = true
      ..currentMediaTitle = '正在投送的电影名称很长很长很长'
      ..statusWarning = '接收端不提供播放状态。请在电视确认画面后手动暂停本机。'
      ..duration = const Duration(hours: 2);
    await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!),
        home: CastScreenPage(
            mediaPath: 'https://example.com/movie.mp4',
            castService: service,
            discover: false)));
    await tester.pumpAndSettle();
    expect(find.text('已发送，等待接收端开始播放…'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('断开连接'), 150);
    expect(tester.takeException(), isNull);
    await tester.scrollUntilVisible(find.text('投屏网络设置'), 150);
    await tester.tap(find.text('投屏网络设置'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    service.dispose();
  });
}
