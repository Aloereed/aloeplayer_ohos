import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aloeplayer/pages/servers_page.dart';
import 'package:aloeplayer/widgets/media_source_card.dart';

void main() {
  testWidgets('all four source types appear on mobile and PC library home', (tester) async {
    SharedPreferences.setMockInitialValues({});
    for (final width in [320.0, 1280.0]) {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(home: const ServersPage()));
      await tester.pumpAndSettle();
      expect(find.byType(MediaSourceCard), findsNWidgets(4));
      expect(find.byTooltip('Jellyfin / Emby'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('添加来源'));
      await tester.pumpAndSettle();
      expect(find.text('局域网共享文件夹'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
    }
  });
  testWidgets('source card supports long names with large text', (tester) async {
    await tester.pumpWidget(MaterialApp(home: MediaQuery(data: const MediaQueryData(textScaler: TextScaler.linear(2)),
      child: Scaffold(body: SizedBox(width: 290, child: MediaSourceCard(
        name: '非常长的家庭影视媒体服务器名称', address: 'https://long-server.example.com/media', protocol: 'Jellyfin',
        icon: Icons.movie, onOpen: () {}, onEdit: () {}))))));
    expect(tester.takeException(), isNull);
  });
}
