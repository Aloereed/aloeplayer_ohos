import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import 'package:aloeplayer/services/media_server_client.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test('pagination preserves proxy prefix, filters and server total', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requests = <Uri>[];
    server.listen((request) async {
      requests.add(request.uri);
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'Items': [
          {'Id': 'second', 'Name': '第二页', 'Type': 'Movie'}
        ],
        'TotalRecordCount': 5
      }));
      await request.response.close();
    });
    final client = MediaServerClient(MediaServerConnection(
        id: 'fixture',
        name: 'fixture',
        url: 'http://127.0.0.1:${server.port}/emby',
        userId: 'user',
        username: 'user',
        token: 'token',
        kind: 'Emby'));
    try {
      final page = await client.itemPage(
          parent: 'library', search: '中文 & test', start: 2, limit: 2);
      expect(page.nextStart, 3);
      expect(page.hasMore, isTrue);
      expect(page.total, 5);
      expect(requests.single.path, '/emby/Users/user/Items');
      expect(requests.single.queryParameters,
          containsPair('EnableTotalRecordCount', 'true'));
      expect(requests.single.queryParameters, containsPair('StartIndex', '2'));
      expect(requests.single.queryParameters, containsPair('Limit', '2'));
      expect(requests.single.queryParameters,
          containsPair('SearchTerm', '中文 & test'));
      expect(
          requests.single.queryParameters, containsPair('ParentId', 'library'));
      final cancel = CancelToken()..cancel();
      await expectLater(
          client.playback(
              const MediaServerItem(id: 'movie', name: 'Movie', type: 'Movie'),
              cancelToken: cancel),
          throwsA(isA<DioException>()
              .having((e) => CancelToken.isCancel(e), 'cancelled', isTrue)));
      expect(requests, hasLength(1));
    } finally {
      await client.close();
      await server.close(force: true);
    }
  });
  test(
      'server URL validation preserves reverse-proxy prefixes and rejects credentials',
      () {
    expect(MediaServerConnection.normalizeUrl('https://nas.example/jellyfin/'),
        'https://nas.example/jellyfin');
    expect(() => MediaServerConnection.normalizeUrl('https://user:pass@nas/'),
        throwsFormatException);
    expect(() => MediaServerConnection.normalizeUrl('file:///movie'),
        throwsFormatException);
  });
  test(
      'login, browsing, header-authenticated stream and tick-based progress use server protocol',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final events = <String>[];
    final positions = <int>[];
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      final route = request.uri.path;
      events.add(route);
      request.response.headers.contentType = ContentType.json;
      Object response = {};
      if (route == '/jellyfin/Users/AuthenticateByName') {
        expect((jsonDecode(body) as Map)['Pw'], 'test-password');
        expect(request.headers.value('X-Emby-Authorization'),
            contains('AloePlayer'));
        expect(request.headers.value('Authorization'),
            contains('MediaBrowser Client="AloePlayer"'));
        response = {
          'AccessToken': 'test-token',
          'User': {'Id': 'user'}
        };
      } else {
        expect(request.headers.value('X-Emby-Token'), 'test-token');
        expect(request.headers.value('Authorization'),
            contains('Token="test-token"'));
        if (route.endsWith('/stream')) {
          expect(request.uri.queryParameters['Static'], 'true');
          expect(request.uri.queryParameters['MediaSourceId'], 'source');
        }
        if (route.endsWith('/Items')) {
          expect(route, '/jellyfin/Items');
          expect(request.uri.queryParameters['UserId'], 'user');
          expect(request.uri.queryParameters['Fields'],
              isNot(contains('MediaSources')));
          response = {
            'Items': [
              {
                'Id': 'movie',
                'Name': 'Movie',
                'Type': 'Movie',
                'UserData': {'PlaybackPositionTicks': 120000000}
              }
            ]
          };
        }
        if (route.endsWith('/PlaybackInfo'))
          response = {
            'PlaySessionId': 'session',
            'MediaSources': [
              {'Id': 'source'}
            ]
          };
        if (route.contains('/Sessions/'))
          positions.add((jsonDecode(body) as Map)['PositionTicks'] as int);
      }
      request.response.write(jsonEncode(response));
      await request.response.close();
    });
    MediaServerClient? client;
    try {
      final connection = await MediaServerClient.login(
          url: 'http://127.0.0.1:${server.port}/jellyfin',
          username: 'test-user',
          password: 'test-password',
          kind: 'Jellyfin');
      expect(connection.toJson().containsKey('token'), isFalse);
      client = MediaServerClient(connection);
      final items = await client.items();
      expect(items.single.resumeMs, 12000);
      final media = await client.playback(items.single);
      expect(Uri.parse(media.url).host, '127.0.0.1');
      expect(
          Uri.parse(media.url).queryParameters.containsKey('api_key'), isFalse);
      expect(media.httpHeaders, isEmpty);
      final reader = HttpClient();
      try {
        final response =
            await (await reader.getUrl(Uri.parse(media.url))).close();
        expect(response.statusCode, 200);
        await response.drain<void>();
      } finally {
        reader.close(force: true);
      }
      await client.report(media, 15000, false, true);
      await client.report(media, 18000, true, false);
      expect(positions, [150000000, 150000000, 180000000]);
      expect(events.last, '/jellyfin/Sessions/Playing/Stopped');
    } finally {
      await client?.close();
      await server.close(force: true);
    }
  });
}
