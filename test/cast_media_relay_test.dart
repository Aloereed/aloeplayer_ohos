import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/services/cast_media_relay.dart';

void main() {
  late HttpServer origin;
  late HttpServer cdn;
  late HttpClient reader;
  late String base;
  late Completer<void> blocked;
  final requests = <String>[];
  setUp(() async {
    requests.clear();
    blocked = Completer<void>();
    origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    cdn = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    reader = HttpClient()..autoUncompress = false;
    base = 'http://127.0.0.1:${origin.port}';
    cdn.listen((request) async {
      expect(request.headers.value('authorization'), isNull);
      expect(request.headers.value('cookie'), isNull);
      expect(request.headers.value('x-api-key'), isNull);
      request.response.add([9, 8, 7]);
      await request.response.close();
    });
    origin.listen((request) async {
      requests.add('${request.method} ${request.uri.path}');
      expect(request.headers.value('authorization'), request.uri.path == '/basic'
          ? 'Basic ${base64Encode(utf8.encode('viewer:p:ss'))}' : 'Bearer test-secret');
      final response = request.response;
      switch (request.uri.path) {
        case '/basic':
          response.add([4,3,2,1]);
        case '/get-only':
          if (request.method == 'HEAD') response.statusCode = 405;
          else { response.contentLength = 4; response.add([1,2,3,4]); }
        case '/blocked':
          response.bufferOutput = false;
          response.contentLength = 2;
          response.add([0]); await response.flush();
          await blocked.future; response.add([1]);
        case '/redirect.m3u8':
          response.statusCode = 302;
          response.headers.set('Location', '/hls/master.m3u8');
        case '/hls/master.m3u8':
          response.headers.set('Content-Type', 'application/vnd.apple.mpegurl');
          response.headers.set('Content-Encoding', 'gzip');
          response.add(gzip.encode(utf8.encode(
              '#EXTM3U\n#EXT-X-MEDIA:TYPE=AUDIO,URI="audio.m3u8"\n#EXT-X-STREAM-INF:BANDWIDTH=120000\nvideo.m3u8\n')));
        case '/hls/audio.m3u8':
        case '/hls/video.m3u8':
        case '/dynamic':
          response.headers.set('Content-Type', 'application/x-mpegURL');
          final playlist =
              '#EXTM3U\n#EXT-X-TARGETDURATION:10\n#EXT-X-KEY:METHOD=AES-128,URI="key.bin"\n#EXT-X-MAP:URI="init.mp4"\n#EXTINF:10,\nsegment.ts\n#EXTINF:10,\nhttp://127.0.0.1:${cdn.port}/other.ts\n#EXT-X-ENDLIST\n';
          response.contentLength = utf8.encode(playlist).length;
          if (request.method == 'GET') response.write(playlist);
        case '/hls/key.bin':
          response.add(List.filled(16, 7));
        case '/hls/init.mp4':
          response.add([1, 2, 3, 4]);
        case '/hls/segment.ts':
          expect(request.headers.value('range'), 'bytes=10-19');
          response.statusCode = 206;
          response.headers.set('Content-Range', 'bytes 10-19/100');
          response.contentLength = 10;
          response.add(List.generate(10, (i) => i + 10));
        case '/compressed.bin':
          response.headers.set('Content-Encoding', 'gzip');
          response.add(gzip.encode([1, 2, 3, 4]));
        case '/forbidden':
          response.statusCode = 403;
        default:
          response.statusCode = 404;
      }
      await response.close();
    });
  });
  tearDown(() async {
    if (!blocked.isCompleted) blocked.complete();
    reader.close(force: true);
    await origin.close(force: true);
    await cdn.close(force: true);
  });
  Future<HttpClientResponse> get(String url,
      {String method = 'GET', String? range}) async {
    final request = await reader.openUrl(method, Uri.parse(url));
    if (range != null) request.headers.set('Range', range);
    return request.close();
  }

  Future<List<int>> body(HttpClientResponse response) =>
      response.fold<List<int>>([], (all, bytes) => all..addAll(bytes));
  const auth = {
    'Authorization': 'Bearer test-secret',
    'Cookie': 'session=secret',
    'X-Api-Key': 'test-api-secret'
  };

  test('URL credentials stay private and HEAD falls back for GET-only origins', () async {
    final credentialUrl = Uri.parse('$base/basic').replace(userInfo: 'viewer:p%3Ass').toString();
    final basic = await CastMediaRelay.start(credentialUrl, host: '127.0.0.1');
    addTearDown(basic.close);
    expect(basic.url, isNot(contains('viewer')));
    expect(await body(await get(basic.url)), [4,3,2,1]);
    final fallback = await CastMediaRelay.start('$base/get-only', host: '127.0.0.1', headers: auth);
    addTearDown(fallback.close);
    final response = await get(fallback.url, method: 'HEAD');
    expect(response.statusCode, 200); expect(response.contentLength, 4);
    expect(await body(response), isEmpty);
  });

  test('concurrent relay reads are bounded and recover after streams finish', () async {
    final relay = await CastMediaRelay.start('$base/blocked', host: '127.0.0.1', headers: auth);
    addTearDown(relay.close);
    final pending = await Future.wait(List.generate(CastMediaRelay.maxReaders, (_) => get(relay.url)));
    final overflow = await get(relay.url);
    expect(overflow.statusCode, 503); expect(overflow.headers.value('retry-after'), '1');
    await body(overflow); blocked.complete();
    for (final response in pending) { expect(await body(response), [0,1]); }
    expect(await body(await get(relay.url)), [0,1]);
  });

  test(
      'redirected gzip master rewrites nested manifests, AES keys, init, segments and strips cross-origin credentials',
      () async {
    final relay = await CastMediaRelay.start('$base/redirect.m3u8',
        host: '127.0.0.1', headers: auth);
    addTearDown(relay.close);
    final masterResponse = await get(relay.url);
    expect(masterResponse.statusCode, 200);
    expect(masterResponse.headers.value('content-encoding'), isNull);
    final master = utf8.decode(await body(masterResponse));
    expect(master, isNot(contains('test-secret')));
    expect(master, isNot(contains('$base/hls/')));
    final audio = RegExp('URI="([^"]+)"').firstMatch(master)!.group(1)!;
    final video =
        master.split('\n').firstWhere((line) => line.startsWith('http'));
    final variant = utf8.decode(await body(await get(video)));
    expect((await get(audio)).statusCode, 200);
    final attrs = RegExp('URI="([^"]+)"')
        .allMatches(variant)
        .map((m) => m.group(1)!)
        .toList();
    expect(await body(await get(attrs[0])), List.filled(16, 7));
    expect(await body(await get(attrs[1])), [1, 2, 3, 4]);
    final segments =
        variant.split('\n').where((line) => line.startsWith('http')).toList();
    final segment = await get(segments[0], range: 'bytes=10-19');
    expect(segment.statusCode, 206);
    expect(segment.headers.value('content-range'), 'bytes 10-19/100');
    expect(await body(segment), List.generate(10, (i) => i + 10));
    expect(await body(await get(segments[1])), [9, 8, 7]);
    expect(relay.bytesServed, greaterThan(0));
    expect(requests, contains('GET /hls/master.m3u8'));
  });
  test(
      'HEAD for a dynamic HLS URL reports rewritten length; manifest ranges and denied tokens are correct',
      () async {
    final relay = await CastMediaRelay.start('$base/dynamic',
        host: '127.0.0.1', headers: auth);
    addTearDown(relay.close);
    final head = await get(relay.url, method: 'HEAD');
    final length = head.contentLength;
    expect(await body(head), isEmpty);
    final full = await body(await get(relay.url));
    expect(length, full.length);
    final range = await get(relay.url, range: 'bytes=0-9');
    expect(range.statusCode, 206);
    expect(await body(range), full.take(10).toList());
    final invalid = Uri.parse(relay.url)
        .replace(queryParameters: {'token': 'invalid'}).toString();
    expect((await get(invalid)).statusCode, 403);
    expect((await get(relay.url, method: 'POST')).statusCode, 405);
  });
  test('binary Content-Encoding and upstream failure status are preserved',
      () async {
    final relay = await CastMediaRelay.start('$base/compressed.bin',
        host: '127.0.0.1', headers: auth);
    addTearDown(relay.close);
    final response = await get(relay.url);
    expect(response.headers.value('content-encoding'), 'gzip');
    expect(gzip.decode(await body(response)), [1, 2, 3, 4]);
    final errors = <String>[];
    final denied = await CastMediaRelay.start('$base/forbidden',
        host: '127.0.0.1', headers: auth, onError: errors.add);
    addTearDown(denied.close);
    expect((await get(denied.url)).statusCode, 403);
    expect(errors.single, contains('403'));
  });
  test(
      'local file URI with reserved characters supports HEAD, suffix range and scoped local HLS',
      () async {
    final temp = await Directory.systemTemp.createTemp('cast-relay-');
    addTearDown(() => temp.delete(recursive: true));
    final file = File('${temp.path}/中文 #%25.mp4');
    await file.writeAsBytes(List.generate(256, (i) => i));
    final relay =
        await CastMediaRelay.start(file.uri.toString(), host: '127.0.0.1');
    addTearDown(relay.close);
    final head = await get(relay.url, method: 'HEAD');
    expect(head.contentLength, 256);
    expect(await body(head), isEmpty);
    expect(await body(await get(relay.url, range: 'bytes=-4')),
        [252, 253, 254, 255]);
    expect((await get(relay.url, range: 'bytes=256-')).statusCode, 416);
    final playlist = File('${temp.path}/index.m3u8');
    await playlist.writeAsString(
        '#EXTM3U\n#EXTINF:1,\n${file.uri.pathSegments.last}\n#EXT-X-ENDLIST\n');
    final hls = await CastMediaRelay.start(playlist.path, host: '127.0.0.1');
    addTearDown(hls.close);
    final text = utf8.decode(await body(await get(hls.url)));
    final segment =
        text.split('\n').firstWhere((line) => line.startsWith('http'));
    // The playlist URI must escape literal # and % characters.
    expect((await get(segment)).statusCode, 502);
    await playlist.writeAsString(
        '#EXTM3U\n#EXTINF:1,\n${Uri.encodeComponent(file.uri.pathSegments.last)}\n#EXT-X-ENDLIST\n');
    final valid = utf8
        .decode(await body(await get(hls.url)))
        .split('\n')
        .firstWhere((line) => line.startsWith('http'));
    expect(await body(await get(valid)), List.generate(256, (i) => i));
  });
}
