import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/services/byte_range.dart';
import 'package:aloeplayer/services/webdav_service.dart';
import 'package:aloeplayer/services/file_service.dart';
import 'package:aloeplayer/services/http_service.dart';
import 'package:aloeplayer/services/media_cast_service.dart';
import 'webdav_compatibility_test.dart' show multi, entry, rootProps;

void main() {
  test(
      'authenticated WebDAV HLS and ranges survive browser shutdown through independent scoped grants',
      () async {
    final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final files = <String, List<int>>{
      '/dav/hls/index.m3u8': utf8
          .encode('#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=100000\nv/main.m3u8\n'),
      '/dav/hls/v/main.m3u8': utf8.encode(
          '#EXTM3U\n#EXT-X-KEY:METHOD=AES-128,URI="../key.bin"\n#EXTINF:1,\n../segment.ts\n#EXT-X-ENDLIST\n'),
      '/dav/hls/key.bin': List.filled(16, 7),
      '/dav/hls/segment.ts': List.generate(512, (i) => i % 256),
    };
    var connections = 0;
    origin.listen((request) async {
      final response = request.response;
      if (request.headers.value('authorization') !=
          'Basic ${base64Encode(utf8.encode('viewer:test-secret'))}') {
        response.statusCode = 401;
        response.headers.set('WWW-Authenticate', 'Basic realm="test"');
      } else if (request.method == 'PROPFIND') {
        response.statusCode = 207;
        if (request.uri.path == '/dav/') {
          connections++;
          response.write(multi(entry('/dav/', props: rootProps)));
        } else if (files.containsKey(request.uri.path)) {
          response.write(multi(entry(request.uri.path,
              props:
                  '<z:getcontentlength>${files[request.uri.path]!.length}</z:getcontentlength><z:getetag>&quot;v1&quot;</z:getetag>')));
        } else {
          response.statusCode = 404;
        }
      } else if (files.containsKey(request.uri.path)) {
        final bytes = files[request.uri.path]!;
        final header = request.headers.value('range');
        final range =
            header == null ? null : ByteRange.parse(header, bytes.length);
        final data =
            range == null ? bytes : bytes.sublist(range.start, range.end + 1);
        response.statusCode = range == null ? 200 : 206;
        if (range != null)
          response.headers.set('Content-Range',
              'bytes ${range.start}-${range.end}/${bytes.length}');
        response.headers.set('ETag', '"v1"');
        response.contentLength = data.length;
        if (request.method != 'HEAD') response.add(data);
      } else {
        response.statusCode = 404;
      }
      await response.close();
    });
    final browser = WebDavService();
    final proxy = HttpService.forSource(WebDavFileService(service: browser));
    final cast = MediaCastService.forTesting(
        advertisedHost: '127.0.0.1', fileProxy: proxy);
    final reader = HttpClient();
    Future<List<int>> read(String url, {String? range}) async {
      final request = await reader.getUrl(Uri.parse(url));
      if (range != null) request.headers.set('range', range);
      final response = await request.close();
      expect(response.statusCode, range == null ? 200 : 206);
      return response.fold<List<int>>([], (all, next) => all..addAll(next));
    }

    try {
      await browser.connect(
          baseUrl: 'http://127.0.0.1:${origin.port}/dav/',
          username: 'viewer',
          password: 'test-secret');
      await proxy.startServer();
      final url = await cast
          .startLocalServer(proxy.getFileUrlLocalhost('/hls/index.m3u8'));
      expect(connections, 2);
      await browser.disconnect();
      await proxy.stopServer();
      final master = utf8.decode(await read(url));
      expect(master, isNot(contains('test-secret')));
      final child =
          master.split('\n').firstWhere((line) => line.startsWith('http'));
      final variant = utf8.decode(await read(child));
      final key = RegExp('URI="([^"]+)"').firstMatch(variant)!.group(1)!;
      expect(await read(key), List.filled(16, 7));
      final segment =
          variant.split('\n').firstWhere((line) => line.startsWith('http'));
      expect(await read(segment, range: 'bytes=250-269'),
          List.generate(20, (i) => (250 + i) % 256));
      await cast.closeIdleRelay();
      await expectLater(() async {
        await (await reader.getUrl(Uri.parse(url))).close();
      }, throwsA(anyOf(isA<SocketException>(), isA<HttpException>())));
    } finally {
      reader.close(force: true);
      await cast.closeIdleRelay();
      cast.dispose();
      await proxy.stopServer();
      await browser.disconnect();
      await origin.close(force: true);
    }
  });
}
