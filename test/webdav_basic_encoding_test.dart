import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/services/webdav_auth.dart';
import 'package:aloeplayer/services/webdav_service.dart';
import 'webdav_compatibility_test.dart' show entry, multi, rootProps;

void main() {
  test(
      'Basic fallback is limited to representable legacy credentials and an actual Basic challenge',
      () {
    expect(canRetryBasicLatin1(['Basic realm="old"'], 'café', 'pass'), isTrue);
    expect(
        canRetryBasicLatin1(
            ['Basic realm="new", charset="UTF-8"'], 'café', 'pass'),
        isFalse);
    expect(canRetryBasicLatin1(['Basic realm="old"'], '中文', 'pass'), isFalse);
    expect(canRetryBasicLatin1(['Negotiate'], 'café', 'pass'), isFalse);
    expect(canRetryBasicLatin1(['Basic realm="old"'], 'user', 'pass'), isFalse);
  });
  for (final modern in [false, true]) {
    test(
        'Basic Latin-1 transport ${modern ? 'never overrides explicit UTF-8' : 'retries once and persists the successful encoding'}',
        () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      var calls = 0;
      final expected = 'Basic ${base64Encode(latin1.encode('café:páss'))}';
      server.listen((request) async {
        calls++;
        if (request.headers.value('authorization') != expected) {
          request.response.statusCode = 401;
          request.response.headers.set('www-authenticate',
              'Basic realm="fixture"${modern ? ', charset="UTF-8"' : ''}');
        } else {
          request.response.statusCode = 207;
          request.response.write(multi(entry('/', props: rootProps)));
        }
        await request.response.close();
      });
      final service = WebDavService();
      try {
        final connect = service.connect(
            baseUrl: 'http://127.0.0.1:${server.port}',
            username: 'café',
            password: 'páss');
        if (modern) {
          await expectLater(connect, throwsStateError);
          expect(calls, 1);
        } else {
          expect(await connect, isTrue);
          await service.listFiles('/');
          expect(calls, 3);
        }
      } finally {
        await service.disconnect();
        await server.close(force: true);
      }
    });
  }
}
