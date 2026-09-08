import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/services/webdav_service.dart';
import 'webdav_compatibility_test.dart' show entry, multi, rootProps;

void main() {
  test('ignored Range supports offset-zero prefixes but never a nonzero seek',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (request.method == 'PROPFIND') {
        request.response.statusCode = 207;
        request.response.write(multi(entry('/', props: rootProps)));
      } else {
        request.response.contentLength = 6;
        request.response.add([0, 1, 2, 3, 4, 5]);
      }
      await request.response.close();
    });
    final service = WebDavService();
    try {
      await service.connect(
          baseUrl: 'http://127.0.0.1:${server.port}',
          username: '',
          password: '');
      expect(
          await (await service.getFileStream('/clip', start: 0))
              .expand((x) => x)
              .toList(),
          [0, 1, 2, 3, 4, 5]);
      expect(
          await (await service.getFileStream('/clip', start: 0, end: 2))
              .expand((x) => x)
              .toList(),
          [0, 1, 2]);
      expect(
          await (await service.getFileStream('/clip', start: 0, end: 100))
              .expand((x) => x)
              .toList(),
          [0, 1, 2, 3, 4, 5]);
      await expectLater(
          service.getFileStream('/clip', start: 3), throwsStateError);
    } finally {
      await service.disconnect();
      await server.close(force: true);
    }
  });

  test('chunked ignored Range cannot silently truncate a requested prefix',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (request.method == 'PROPFIND') {
        request.response.statusCode = 207;
        request.response.write(multi(entry('/', props: rootProps)));
      } else {
        request.response.add([0, 1]);
      }
      await request.response.close();
    });
    final service = WebDavService();
    try {
      await service.connect(
          baseUrl: 'http://127.0.0.1:${server.port}',
          username: '',
          password: '');
      await expectLater(
          (await service.getFileStream('/clip', start: 0, end: 3))
              .drain<void>(),
          throwsStateError);
    } finally {
      await service.disconnect();
      await server.close(force: true);
    }
  });
}
