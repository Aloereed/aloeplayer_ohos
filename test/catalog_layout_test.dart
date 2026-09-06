import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/history_service.dart';
import 'package:aloeplayer/models/catalog_item.dart';
import 'package:aloeplayer/pages/catalog_page.dart';
import 'package:aloeplayer/pages/catalog_detail_page.dart';
import 'package:aloeplayer/services/media_catalog.dart';
import 'package:aloeplayer/theme/app_theme.dart';
import 'support/catalog_database.dart';

final episodes = [
  const CatalogItem(
      filePath: '/shows/Season 1/ep2.mkv',
      title: '回到星海的第二集',
      series: '星海旅行',
      season: 1,
      episode: 2,
      revision: ''),
  const CatalogItem(
      filePath: '/shows/Season 2/ep1.mkv',
      title: '新的旅程',
      series: '星海旅行',
      season: 2,
      episode: 1,
      revision: '',
      plot: '很长的简介。很长的简介。很长的简介。'),
];

Widget app(Widget page, Brightness brightness, double scale) => MaterialApp(
    theme: buildAloeTheme(brightness),
    builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!),
    home: page);

void main() {
  testWidgets('grouped library remains usable on small screens in both themes',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 640);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final brightness in Brightness.values) {
      final db = CatalogMemoryDatabase();
      for (final item in episodes) {
        db.rows[item.filePath] = item.toMap();
      }
      final catalog = MediaCatalog.forTesting(db, []);
      await tester.pumpWidget(app(
          CatalogPage(
              catalog: catalog,
              historyLoader: () async => [],
              generateArtwork: false),
          brightness,
          1.6));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('1 部作品 · 2 个媒体文件'), findsOneWidget);
      await tester.enterText(find.byType(TextField), '不匹配');
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('没有符合条件的作品'), 150,
          scrollable: find.byType(Scrollable).last);
      expect(find.text('没有符合条件的作品'), findsOneWidget);
      expect(find.text('添加本地媒体'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      catalog.dispose();
    }
  });
  testWidgets(
      'details keep play action visible; season selection plays complete ordered queue',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final collection = CatalogCollection.group(episodes).single;
    for (final size in [const Size(320, 640), const Size(640, 320)]) {
      tester.view.physicalSize = size;
      CatalogItem? selected;
      List<CatalogItem>? queue;
      int? position;
      await tester.pumpWidget(app(
          CatalogDetailPage(
              collection: collection,
              generateArtwork: false,
              history: {
                episodes[0].filePath: HistoryItem(
                    filePath: episodes[0].filePath,
                    durationMs: 120000,
                    lastPosition: 65000,
                    lastPlayed: DateTime(2026),
                    mediaType: 'video')
              },
              onPlay: (item, items, start) async {
                selected = item;
                queue = items;
                position = start;
                return {};
              }),
          Brightness.light,
          1.6));
      await tester.pumpAndSettle();
      final play = find.widgetWithText(FilledButton, '继续播放 · 1:05');
      expect(play.hitTestable(), findsOneWidget);
      await tester.tap(play);
      await tester.pumpAndSettle();
      expect(selected, episodes[0]);
      expect(position, 65000);
      await tester.scrollUntilVisible(find.text('第 2 季'), 200);
      await tester.pumpAndSettle();
      await tester.tap(find.text('第 2 季'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('新的旅程'), 150);
      await tester.pumpAndSettle();
      await tester.tap(find.text('新的旅程'));
      await tester.pumpAndSettle();
      expect(selected, episodes[1]);
      expect(queue, orderedEquals(episodes));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
  });
}
