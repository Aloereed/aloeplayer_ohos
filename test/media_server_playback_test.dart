import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/services/media_server_client.dart';
import 'package:aloeplayer/services/media_server_playback.dart';

void main() {
  test(
      'stop is delivered and relay released even when start acknowledgement fails',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final events = <String>[];
    server.listen((request) async {
      await request.drain<void>();
      request.response.headers.contentType = ContentType.json;
      final route = request.uri.path;
      if (route.endsWith('/PlaybackInfo')) {
        request.response.write(jsonEncode({
          'PlaySessionId': 'session',
          'MediaSources': [
            {'Id': 'source', 'SupportsDirectPlay': true}
          ]
        }));
      } else {
        events.add(route);
        if (route == '/Sessions/Playing') request.response.statusCode = 503;
        request.response.write('{}');
      }
      await request.response.close();
    });
    final client = MediaServerClient(MediaServerConnection(
        id: 'device',
        name: 'Test',
        url: 'http://127.0.0.1:${server.port}',
        userId: 'u',
        username: 'u',
        token: 'secret',
        kind: 'Emby'));
    try {
      final media = await client.playback(
          const MediaServerItem(id: 'movie', name: 'Movie', type: 'Movie'));
      await client.report(media, 7000, true, false);
      expect(events, ['/Sessions/Playing', '/Sessions/Playing/Stopped']);
      await client.report(media, 100, false, true);
      expect(events.length, 2);
      final reader = HttpClient();
      try {
        await expectLater(reader.getUrl(Uri.parse(media.url)),
            throwsA(isA<SocketException>()));
      } finally {
        reader.close(force: true);
      }
    } finally {
      await client.close();
      await server.close(force: true);
    }
  });
  test(
      'live source opens explicitly when needed and releases its exact ID on stop',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final closed = <String>[];
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      request.response.headers.contentType = ContentType.json;
      Object response = {};
      if (request.uri.path.endsWith('/PlaybackInfo')) {
        response = {
          'PlaySessionId': 'live-session',
          'MediaSources': [
            {
              'Id': 'live-source',
              'RequiresOpening': true,
              'OpenToken': 'open-token'
            }
          ]
        };
      } else if (request.uri.path.endsWith('/Open')) {
        final data = jsonDecode(body) as Map;
        expect(data['OpenToken'], 'open-token');
        expect(data['PlaySessionId'], 'live-session');
        response = {
          'MediaSource': {
            'Id': 'live-source',
            'LiveStreamId': 'opened-stream',
            'SupportsDirectPlay': true,
            'IsInfiniteStream': true
          }
        };
      } else if (request.uri.path.endsWith('/Close')) {
        closed.add(request.uri.queryParameters['LiveStreamId']!);
      } else if (request.uri.path.contains('/Sessions/')) {
        final payload = jsonDecode(body) as Map;
        expect(payload['CanSeek'], isFalse);
        expect(payload['LiveStreamId'], 'opened-stream');
      }
      request.response.write(jsonEncode(response));
      await request.response.close();
    });
    final client = MediaServerClient(MediaServerConnection(
        id: 'device',
        name: 'Test',
        url: 'http://127.0.0.1:${server.port}',
        userId: 'u',
        username: 'u',
        token: 'secret',
        kind: 'Emby'));
    try {
      final media = await client.playback(const MediaServerItem(
          id: 'channel', name: 'Channel', type: 'TvChannel'));
      await client.report(media, 0, true, false);
      await client.close();
      expect(closed, ['opened-stream']);
    } finally {
      await client.close();
      await server.close(force: true);
    }
  });
  test(
      'media URL resolution preserves proxy prefix and removes only same-origin API keys',
      () {
    const base = 'https://nas.example/proxy';
    for (final input in [
      'Videos/id/master.m3u8',
      '/Videos/id/master.m3u8',
      '/proxy/Videos/id/master.m3u8'
    ]) {
      expect(resolveMediaServerUrl(base, input).path,
          '/proxy/Videos/id/master.m3u8');
    }
    expect(resolveMediaServerUrl(base, '/Videos/a?api_key=secret').query, '');
    expect(resolveMediaServerUrl(base, '/Videos/a?api_key=secret&x=2').query,
        'x=2');
    expect(
        resolveMediaServerUrl(base, 'https://cdn.example/a?api_key=cdn-key')
            .query,
        'api_key=cdn-key');
    expect(() => resolveMediaServerUrl(base, 'file:///etc/passwd'),
        throwsStateError);
    expect(() => resolveMediaServerUrl(base, 'https://u:p@cdn.example/a'),
        throwsStateError);
  });
  test(
      'negotiation keeps source and stream indices together and enforces selected mode',
      () {
    final body = playbackRequest(
        'user',
        const MediaServerPlaybackOptions(
            sourceId: 'version',
            audioIndex: 7,
            subtitleIndex: -1,
            maxBitrate: 4000000,
            mode: MediaServerPlayMode.transcode),
        playing: true);
    expect(body['MediaSourceId'], 'version');
    expect(body['AudioStreamIndex'], 7);
    expect(body['SubtitleStreamIndex'], -1);
    expect(body['EnableDirectPlay'], isFalse);
    expect(body['EnableDirectStream'], isFalse);
    expect(body['EnableTranscoding'], isTrue);
    expect(body['MaxStreamingBitrate'], 4000000);
    expect(body['StartTimeTicks'], 0);
    final probe = playbackRequest('user', const MediaServerPlaybackOptions(),
        playing: false);
    expect(probe['AutoOpenLiveStream'], isFalse);
    expect(probe['IsPlayback'], isFalse);
  });
  test(
      'HLS and selected subtitles stay authenticated through loopback; same-item sessions and cleanup remain separate',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final payloads = <Map<String, dynamic>>[];
    final cleanup = <String>[];
    var sessionCounter = 0;
    server.listen((request) async {
      final body = await utf8.decoder.bind(request).join();
      expect(request.headers.value('X-Emby-Token'), 'server-secret');
      expect(request.uri.queryParameters.containsKey('api_key'), isFalse);
      final route = request.uri.path;
      request.response.headers.contentType = ContentType.json;
      Object response = {};
      if (route.endsWith('/PlaybackInfo')) {
        final posted = jsonDecode(body) as Map;
        expect(posted['MediaSourceId'], 'version-b');
        expect(posted['AudioStreamIndex'], 8);
        expect(posted['SubtitleStreamIndex'], 9);
        response = {
          'PlaySessionId': 'session-${++sessionCounter}',
          'MediaSources': [
            {
              'Id': 'version-b',
              'SupportsDirectPlay': false,
              'SupportsDirectStream': false,
              'TranscodingUrl':
                  '/Videos/movie/master.m3u8?api_key=server-secret',
              'MediaStreams': [
                {'Index': 8, 'Type': 'Audio', 'Codec': 'aac'},
                {
                  'Index': 9,
                  'Type': 'Subtitle',
                  'IsExternal': true,
                  'DeliveryMethod': 'External',
                  'DeliveryUrl': '/Videos/movie/sub.srt?api_key=server-secret'
                }
              ]
            }
          ]
        };
      } else if (route.endsWith('/master.m3u8')) {
        request.response.headers.contentType =
            ContentType('application', 'vnd.apple.mpegurl');
        request.response.write(
            '#EXTM3U\n#EXT-X-TARGETDURATION:4\n#EXTINF:4,\nsegment.ts\n#EXT-X-ENDLIST\n');
        await request.response.close();
        return;
      } else if (route.endsWith('/segment.ts')) {
        request.response.add([1, 2, 3, 4]);
        await request.response.close();
        return;
      } else if (route.endsWith('/sub.srt')) {
        request.response.write('1\n00:00:00,000 --> 00:00:02,000\n字幕\n');
        await request.response.close();
        return;
      } else if (route.contains('/Sessions/')) {
        payloads.add(Map<String, dynamic>.from(jsonDecode(body) as Map));
      } else if (route.endsWith('/ActiveEncodings')) {
        expect(request.method, 'DELETE');
        cleanup.add(request.uri.queryParameters['PlaySessionId']!);
      }
      request.response.write(jsonEncode(response));
      await request.response.close();
    });
    final client = MediaServerClient(MediaServerConnection(
        id: 'device',
        name: 'Test',
        url: 'http://127.0.0.1:${server.port}/proxy',
        userId: 'u',
        username: 'u',
        token: 'server-secret',
        kind: 'Jellyfin'));
    final reader = HttpClient();
    Future<List<int>> read(String url) async {
      final response = await (await reader.getUrl(Uri.parse(url))).close();
      expect(response.statusCode, 200);
      return response
          .fold<List<int>>([], (bytes, chunk) => bytes..addAll(chunk));
    }

    try {
      const movie = MediaServerItem(id: 'movie', name: 'Movie', type: 'Movie');
      const options = MediaServerPlaybackOptions(
          sourceId: 'version-b',
          audioIndex: 8,
          subtitleIndex: 9,
          mode: MediaServerPlayMode.transcode);
      final first = await client.playback(movie, options: options);
      final second = await client.playback(movie, options: options);
      expect(first.url, isNot(second.url));
      expect(first.httpHeaders, isEmpty);
      expect(first.preferredAudioTrack, '1');
      expect(first.preferredSubtitleTrack, 'external');
      final manifest = utf8.decode(await read(first.url));
      expect(manifest, isNot(contains('server-secret')));
      final segment =
          manifest.split('\n').firstWhere((line) => line.startsWith('http://'));
      expect(await read(segment), [1, 2, 3, 4]);
      expect(utf8.decode(await read(first.subtitles.single)), contains('字幕'));
      await client.report(first, 1000, false, true);
      await client.report(second, 2000, false, true);
      await client.report(first, 1500, true, false);
      await client.report(first, 1500, true, false);
      expect(cleanup, ['session-1']);
      expect(
          payloads.where((p) => p['PlaySessionId'] == 'session-1').length, 3);
      expect(
          payloads.where((p) => p['PlaySessionId'] == 'session-2').length, 2);
      expect(
          payloads.every((p) =>
              p['MediaSourceId'] == 'version-b' &&
              p['PlayMethod'] == 'Transcode'),
          isTrue);
      await client.close();
      expect(cleanup, ['session-1', 'session-2']);
    } finally {
      await client.close();
      reader.close(force: true);
      await server.close(force: true);
    }
  });
}
