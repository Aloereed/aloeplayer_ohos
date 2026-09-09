import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/services/media_server_client.dart';
import 'package:aloeplayer/services/media_server_catalog.dart';

void main() {
  test(
      'album neighbours cross pages, reject foreign albums, and terminate repeated pages',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final starts = <int>[];
    var repeat = false;
    final rows = List.generate(
        205,
        (i) => <String, dynamic>{
              'Id': '$i',
              'Name': 'Track $i',
              'Type': 'Audio',
              'AlbumId': 'album',
              'ParentIndexNumber': i < 200 ? 1 : 2,
              'IndexNumber': i % 200 + 1
            });
    rows[201]['AlbumId'] = 'foreign';
    server.listen((request) async {
      expect(request.uri.queryParameters['ParentId'], 'album');
      expect(request.uri.queryParameters['SortBy'],
          'ParentIndexNumber,IndexNumber,SortName');
      expect(request.uri.queryParameters['IncludeItemTypes'], 'Audio');
      final start = int.parse(request.uri.queryParameters['StartIndex']!);
      starts.add(start);
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode({
        'Items': rows.skip(repeat ? 0 : start).take(200).toList(),
        'TotalRecordCount': repeat ? 10000 : rows.length
      }));
      await request.response.close();
    });
    final client = MediaServerClient(MediaServerConnection(
        id: 'device',
        name: 'Test',
        url: 'http://127.0.0.1:${server.port}',
        userId: 'u',
        username: 'u',
        token: 't',
        kind: 'Jellyfin'));
    MediaServerItem item(int i) => MediaServerItem.fromJson(rows[i]);
    try {
      expect((await client.adjacentTrack(item(199), forward: true))?.id, '200');
      expect(starts, [0, 200]);
      expect((await client.adjacentTrack(item(200), forward: true))?.id, '202');
      expect(
          (await client.adjacentTrack(item(202), forward: false))?.id, '200');
      expect(await client.adjacentTrack(item(0), forward: false), isNull);
      expect(await client.adjacentTrack(item(204), forward: true), isNull);
      repeat = true;
      starts.clear();
      expect(await client.adjacentTrack(item(204), forward: true), isNull);
      expect(starts, [0, 200]);
      final cancel = CancelToken()..cancel('Closed');
      await expectLater(
          client.adjacentTrack(item(1), forward: true, cancelToken: cancel),
          throwsA(isA<DioException>()));
    } finally {
      await client.close();
      await server.close(force: true);
    }
  });
}
