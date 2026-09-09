import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/services/media_server_client.dart';
import 'package:aloeplayer/services/media_server_catalog.dart';
import 'package:aloeplayer/services/media_server_sequence.dart';
import 'package:aloeplayer/services/media_server_playback.dart';
import 'package:dio/dio.dart';

void main() {
  test('older server fallback crosses pages and seasons without wrapping',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final starts = <int>[];
    final negotiations = <Map>[];
    var repeat = false;
    final rows = List.generate(
        205,
        (i) => {
              'Id': '$i',
              'Name': 'Episode $i',
              'Type': 'Episode',
              'SeriesId': 'show',
              'ParentIndexNumber': i < 200 ? 1 : 2,
              'IndexNumber': i < 200 ? i + 1 : i - 199
            });
    server.listen((request) async {
      if (request.uri.path.endsWith('/PlaybackInfo')) {
        negotiations
            .add(jsonDecode(await utf8.decoder.bind(request).join()) as Map);
        request.response.headers.contentType = ContentType.json;
        request.response.write(jsonEncode({
          'PlaySessionId': 'session-${negotiations.length}',
          'MediaSources': [
            {'Id': 'source-${negotiations.length}', 'SupportsDirectPlay': true}
          ]
        }));
        await request.response.close();
        return;
      }
      expect(request.uri.queryParameters.containsKey('SeasonId'), isFalse);
      final start =
          int.tryParse(request.uri.queryParameters['StartIndex'] ?? '') ?? 0;
      final limit = int.parse(request.uri.queryParameters['Limit']!);
      starts.add(start);
      // Simulate a legacy server which ignores AdjacentTo entirely.
      final offset = repeat ? 0 : start;
      final page = rows.skip(offset).take(limit).toList();
      request.response.headers.contentType = ContentType.json;
      request.response.write(jsonEncode(
          {'Items': page, 'TotalRecordCount': repeat ? 10000 : rows.length}));
      await request.response.close();
    });
    final client = MediaServerClient(MediaServerConnection(
        id: 'device',
        name: 'Test',
        url: 'http://127.0.0.1:${server.port}',
        userId: 'u',
        username: 'u',
        token: 't',
        kind: 'Emby'));
    MediaServerItem item(int i) =>
        MediaServerItem.fromJson(Map<String, dynamic>.from(rows[i]));
    try {
      expect(
          (await client.adjacentEpisode(item(199), forward: true))?.id, '200');
      expect(starts, [0, 0, 200]);
      repeat = false;
      final initial = await client.playback(item(199));
      final sequence = MediaServerSequence(
          client: client,
          cancelToken: CancelToken(),
          item: item(199),
          media: initial,
          options: const MediaServerPlaybackOptions(
              sourceId: 'previous-version',
              audioIndex: 99,
              subtitleIndex: -1,
              maxBitrate: 2000000,
              mode: MediaServerPlayMode.original));
      final prepared = (await sequence.adjacent(initial, true))!;
      expect(negotiations.last.containsKey('MediaSourceId'), isFalse);
      expect(negotiations.last.containsKey('AudioStreamIndex'), isFalse);
      expect(negotiations.last['SubtitleStreamIndex'], -1);
      expect(negotiations.last['MaxStreamingBitrate'], 2000000);
      expect(negotiations.last['EnableTranscoding'], isFalse);
      expect(prepared.id, contains('/200'));
      await sequence.discard(prepared);
      final retried = (await sequence.adjacent(initial, true))!;
      expect(retried.id, prepared.id);
      expect(retried.url, isNot(prepared.url));
      await sequence.discard(retried);
      starts.clear();
      expect(
          (await client.adjacentEpisode(item(200), forward: false))?.id, '199');
      expect(await client.adjacentEpisode(item(204), forward: true), isNull);
      expect(await client.adjacentEpisode(item(0), forward: false), isNull);
      starts.clear();
      repeat = true;
      expect(await client.adjacentEpisode(item(204), forward: true), isNull);
      expect(starts, [0, 0, 200]);
    } finally {
      await client.close();
      await server.close(force: true);
    }
  });
}
