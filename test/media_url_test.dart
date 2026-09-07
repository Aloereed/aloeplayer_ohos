import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/services/media_url.dart';

void main() {
  test('extracts shared text, preserves signatures and balanced parentheses', () {
    expect(extractMediaUrls('来看视频【https://example.com/a.mp4?token=a%2Bb&x=1】。'),
      ['https://example.com/a.mp4?token=a%2Bb&x=1']);
    expect(extractMediaUrls('视频 (https://example.com/a(b).mp4)。'), ['https://example.com/a(b).mp4']);
    expect(extractMediaUrls('无链接 ftp://example.com/a'), isEmpty);
    expect(extractMediaUrls('https:// https:///'), isEmpty);
    expect(extractMediaUrls('https://example.com/a https://example.com/b https://example.com/a'), hasLength(2));
    expect(extractMediaUrls('https://example.com/播放?id=1'), ['https://example.com/播放?id=1']);
  });

  test('rejects HTML and expired links, accepts extensionless media and redirects', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      switch (request.uri.path) {
        case '/web': request.response.headers.contentType = ContentType.html;
        case '/expired': request.response.statusCode = 403;
        case '/redirect':
          request.response.statusCode = 302;
          request.response.headers.set('location', '/stream');
        default: request.response.headers.set('content-type', 'video/mp4');
      }
      await request.response.close();
    });
    addTearDown(() => server.close(force: true));
    final base = 'http://127.0.0.1:${server.port}';
    await expectLater(validateMediaUrl('$base/web'), throwsFormatException);
    await expectLater(validateMediaUrl('$base/expired'), throwsFormatException);
    await validateMediaUrl('$base/stream');
    await validateMediaUrl('$base/redirect');
  });
}
