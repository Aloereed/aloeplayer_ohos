import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/services/media_server_client.dart';
import 'package:aloeplayer/services/media_server_catalog.dart';

void main() {
  for (final kind in ['Jellyfin', 'Emby']) {
    test(
        '$kind catalog uses authenticated proxy routes and correct state verbs',
        () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final requests = <String>[];
      server.listen((request) async {
        await request.drain<void>();
        expect(request.headers.value('X-Emby-Token'), 'secret');
        expect(request.uri.queryParameters['UserId'], 'user');
        final route = request.uri.path;
        requests.add('${request.method} $route');
        request.response.headers.contentType = ContentType.json;
        if (route.endsWith('/Items/movie')) {
          request.response.write(jsonEncode({
            'Id': 'movie',
            'Name': 'Movie',
            'Type': 'Movie',
            'RunTimeTicks': 600000000,
            'UserData': {'IsFavorite': true, 'Played': true}
          }));
        } else if (route.endsWith('/Episodes')) {
          expect(request.uri.queryParameters['SeasonId'], 'season');
          expect(request.uri.queryParameters['StartIndex'], '100');
          expect(request.uri.queryParameters['IsMissing'], 'false');
          request.response.write(jsonEncode({
            'Items': [
              {
                'Id': 'ep',
                'Name': 'Episode',
                'Type': 'Episode',
                'SeriesId': 'series',
                'IndexNumber': 101,
                'ParentIndexNumber': 1
              }
            ],
            'TotalRecordCount': 101
          }));
        } else {
          if (route.endsWith('/Shows/NextUp')) {
            expect(request.uri.queryParameters['LegacyNextUp'],
                kind == 'Emby' ? 'true' : isNull);
          }
          if (request.uri.queryParameters['IsFavorite'] == 'true') {
            expect(request.uri.queryParameters['Recursive'], 'true');
          }
          if (request.uri.queryParameters['SortBy'] == 'DateCreated,SortName') {
            expect(request.uri.queryParameters['SortOrder'], 'Descending');
          }
          request.response
              .write(jsonEncode({'Items': [], 'TotalRecordCount': 0}));
        }
        await request.response.close();
      });
      final connection = MediaServerConnection(
          id: 'client',
          name: 'test',
          url: 'http://127.0.0.1:${server.port}/proxy',
          userId: 'user',
          username: 'u',
          token: 'secret',
          kind: kind);
      final client = MediaServerClient(connection);
      try {
        for (final shelf in MediaServerShelf.values) {
          await client.shelf(shelf);
        }
        final item = await client.details('movie');
        expect(item.favorite, isTrue);
        expect(item.played, isTrue);
        expect(item.durationMs, 60000);
        await client.seasons('series');
        final page =
            await client.episodes('series', seasonId: 'season', start: 100);
        expect(page.hasMore, isFalse);
        expect(page.nextStart, 101);
        expect(page.items.single.index, 101);
        expect(page.items.single.seriesId, 'series');
        await client.setFavorite('movie', true);
        await client.setFavorite('movie', false);
        await client.setPlayed('movie', true);
        await client.setPlayed('movie', false);
        final favoritePath = kind == 'Jellyfin'
            ? 'UserFavoriteItems/movie'
            : 'Users/user/FavoriteItems/movie';
        expect(requests, contains('POST /proxy/$favoritePath'));
        expect(requests, contains('DELETE /proxy/$favoritePath'));
        expect(requests, contains('POST /proxy/Users/user/PlayedItems/movie'));
        expect(
            requests, contains('DELETE /proxy/Users/user/PlayedItems/movie'));
        expect(
            requests,
            contains(
                'GET /proxy/${kind == 'Jellyfin' ? 'UserViews' : 'Users/user/Views'}'));
      } finally {
        await client.close();
        await server.close(force: true);
      }
    });
  }
  test(
      'legacy fallback is limited to missing routes, never auth or transport failures',
      () async {
    final client = MediaServerClient(const MediaServerConnection(
        id: 'c',
        name: 'test',
        url: 'https://example.invalid/prefix',
        userId: 'u',
        username: 'u',
        token: 't',
        kind: 'Jellyfin'));
    final paths = <String>[];
    var status = 404;
    client.dio.interceptors
        .add(InterceptorsWrapper(onRequest: (options, handler) {
      paths.add(options.path);
      if (options.path == 'UserViews') {
        handler.reject(DioException(
            requestOptions: options,
            response: Response(requestOptions: options, statusCode: status)));
      } else {
        handler.resolve(Response(
            requestOptions: options, statusCode: 200, data: {'Items': []}));
      }
    }));
    addTearDown(client.close);
    await client.shelf(MediaServerShelf.libraries);
    expect(paths, ['UserViews', 'Users/u/Views']);
    for (final failure in [401, 403, 500]) {
      paths.clear();
      status = failure;
      await expectLater(client.shelf(MediaServerShelf.libraries),
          throwsA(isA<DioException>()));
      expect(paths, ['UserViews']);
    }
  });
}
