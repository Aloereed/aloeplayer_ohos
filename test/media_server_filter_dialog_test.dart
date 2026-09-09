import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/services/media_server_query.dart';
import 'package:aloeplayer/widgets/media_server_filter_dialog.dart';

void main() {
  testWidgets(
      'narrow filter dialog applies type, watched, favorite and rating order',
      (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    MediaServerQuery? result;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () async {
                      result = await showDialog<MediaServerQuery>(
                          context: context,
                          builder: (_) => const MediaServerFilterDialog(
                              initial: MediaServerQuery()));
                    },
                    child: const Text('打开'))))));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部类型'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('电影').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('全部观看状态'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('未看').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('名称'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('评分').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('只看收藏'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(result!.type, MediaServerTypeFilter.movies);
    expect(result!.watched, MediaServerWatchFilter.unwatched);
    expect(result!.favorites, isTrue);
    expect(result!.descending, isTrue);
    expect(result!.parameters['SortBy'], 'CommunityRating,SortName');
    expect(result!.parameters['Recursive'], isTrue);
  });

  testWidgets('reset removes all filters and restores folder browsing',
      (tester) async {
    MediaServerQuery? result;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () async {
                      result = await showDialog<MediaServerQuery>(
                          context: context,
                          builder: (_) => const MediaServerFilterDialog(
                              initial: MediaServerQuery(
                                  type: MediaServerTypeFilter.audio,
                                  favorites: true,
                                  descending: true)));
                    },
                    child: const Text('打开'))))));
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('重置'));
    await tester.pumpAndSettle();
    expect(result!.changed, isFalse);
    expect(result!.parameters.containsKey('Recursive'), isFalse);
    expect(result!.parameters.containsKey('IsFavorite'), isFalse);
  });
}
