import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/services/webdav_service.dart';

void main() {
  test('WebDAV rejects ignored and misaligned range responses before download writes', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var mode = 'valid';
    server.listen((request) async {
      if (request.method == 'PROPFIND') {
        request.response.statusCode = 207;
        request.response.write('<multistatus/>');
      } else {
        expect(request.headers.value('range'), 'bytes=3-5');
        request.response.statusCode = mode == 'ignored' ? 200 : 206;
        if (mode != 'ignored') request.response.headers.set('content-range', mode == 'valid' ? 'bytes 3-5/6' : 'bytes 0-2/6');
        request.response.add([3, 4, 5]);
      }
      await request.response.close();
    });
    final service = WebDavService();
    try {
      expect(await service.connect(baseUrl: 'http://127.0.0.1:${server.port}', username: 'user', password: 'password'), isTrue);
      final bytes = await (await service.getFileStream('/video', start: 3, end: 5)).expand((chunk) => chunk).toList();
      expect(bytes, [3, 4, 5]);
      mode = 'ignored';
      await expectLater(service.getFileStream('/video', start: 3, end: 5), throwsException);
      mode = 'wrong';
      await expectLater(service.getFileStream('/video', start: 3, end: 5), throwsException);
    } finally { await service.disconnect(); await server.close(force: true); }
  });
}
