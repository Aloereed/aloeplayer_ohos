import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/services/media_server_client.dart';
import 'package:aloeplayer/pages/media_server_home_page.dart';
import 'package:aloeplayer/pages/media_server_detail_page.dart';

const connection = MediaServerConnection(
    id: 'c',
    name: 'Test server',
    url: 'https://example.invalid/prefix',
    userId: 'u',
    username: 'u',
    token: 't',
    kind: 'Jellyfin');
Map<String, dynamic> row(String id, String type) =>
    {'Id': id, 'Name': id, 'Type': type};
MediaServerClient fixture(FutureOr<Object> Function(RequestOptions) answer) {
  final client = MediaServerClient(connection);
  client.dio.interceptors
      .add(InterceptorsWrapper(onRequest: (options, handler) async {
    try {
      handler.resolve(Response(
          requestOptions: options,
          statusCode: 200,
          data: await answer(options)));
    } catch (_) {
      handler.reject(DioException(
          requestOptions: options,
          response: Response(requestOptions: options, statusCode: 500)));
    }
  }));
  return client;
}

void main() {
  testWidgets(
      'home renders successful shelves while another fails and retries independently',
      (tester) async {
    var resumeRequests = 0, libraryRequests = 0;
    final client = fixture((options) {
      if (options.path == 'UserViews') {
        libraryRequests++;
        return {
          'Items': [row('Library', 'CollectionFolder')]
        };
      }
      if (options.path == 'UserItems/Resume') {
        resumeRequests++;
        throw StateError('offline');
      }
      return {'Items': []};
    });
    addTearDown(() => client.dio.close(force: true));
    await tester.pumpWidget(MaterialApp(
        home: MediaServerHomePage(connection: connection, client: client)));
    await tester.pumpAndSettle(const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 2));
    expect(find.text('Library'), findsOneWidget);
    expect(find.textContaining('加载失败'), findsOneWidget);
    await tester.tap(find.textContaining('加载失败'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 2));
    expect(resumeRequests, 2);
    expect(libraryRequests, 1);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'failed favorite never toggles state; from-start and resume are distinct actions',
      (tester) async {
    final client = fixture((options) {
      if (options.method == 'POST') throw StateError('offline');
      return {
        ...row('Film', 'Movie'),
        'UserData': {'PlaybackPositionTicks': 120000000},
        'Overview': 'Film overview'
      };
    });
    addTearDown(() => client.dio.close(force: true));
    await tester.pumpWidget(MaterialApp(
        home: MediaServerDetailPage(
            connection: connection,
            item: MediaServerItem.fromJson(row('Film', 'Movie')),
            client: client)));
    await tester.pumpAndSettle(const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 2));
    expect(find.text('续播 0 分钟'), findsOneWidget);
    expect(find.text('从头播放'), findsOneWidget);
    await tester.tap(find.text('收藏'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 2));
    expect(
        tester
            .widget<FilterChip>(find.widgetWithText(FilterChip, '收藏'))
            .selected,
        isFalse);
    expect(find.textContaining('操作或状态刷新失败'), findsOneWidget);
  });
  testWidgets(
      'closing a pending detail cancels requests without late navigation',
      (tester) async {
    final pending = Completer<Object>();
    CancelToken? token;
    final client = fixture((options) {
      token = options.cancelToken;
      return pending.future;
    });
    addTearDown(() => client.dio.close(force: true));
    await tester.pumpWidget(MaterialApp(
        home: MediaServerDetailPage(
            connection: connection,
            item: MediaServerItem.fromJson(row('Film', 'Movie')),
            client: client)));
    for (var i = 0; i < 5 && token == null; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.pumpWidget(const MaterialApp(home: Text('Closed')));
    expect(token!.isCancelled, isTrue);
    pending.complete(row('Film', 'Movie'));
    await tester.pumpAndSettle(const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 2));
    expect(find.text('Closed'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
      'a late season response cannot overwrite the newly selected season',
      (tester) async {
    final firstSeason = Completer<Object>();
    final client = fixture((options) {
      if (options.path == 'Items/show')
        return {...row('show', 'Series'), 'IsFolder': true};
      if (options.path.endsWith('/Seasons'))
        return {
          'Items': [row('Season one', 'Season'), row('Season two', 'Season')]
        };
      if (options.path.endsWith('/Episodes')) {
        if (options.queryParameters['SeasonId'] == 'Season one')
          return firstSeason.future;
        return {
          'Items': [row('New episode', 'Episode')],
          'TotalRecordCount': 1
        };
      }
      return {'Items': []};
    });
    addTearDown(() => client.dio.close(force: true));
    await tester.pumpWidget(MaterialApp(
        home: MediaServerDetailPage(
            connection: connection,
            item: MediaServerItem.fromJson(row('show', 'Series')),
            client: client)));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    final dropdown = find.byType(DropdownButtonFormField<String>);
    await tester.ensureVisible(dropdown);
    await tester.tap(dropdown);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Season two').last);
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    firstSeason.complete({
      'Items': [row('Old episode', 'Episode')],
      'TotalRecordCount': 1
    });
    await tester.pumpAndSettle(const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate, const Duration(seconds: 2));
    expect(find.text('New episode'), findsOneWidget);
    expect(find.text('Old episode'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
