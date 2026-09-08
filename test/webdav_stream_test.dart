import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/services/webdav_service.dart';
import 'package:aloeplayer/services/file_service.dart';
import 'package:aloeplayer/models/download_task.dart';
import 'webdav_compatibility_test.dart' show entry, multi, rootProps;

void main() {
  test(
      'conditional reads reject replacement files and persisted tasks retain ETags',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var changed = false;
    server.listen((request) async {
      if (request.method == 'PROPFIND') {
        request.response.statusCode = 207;
        request.response.write(multi(entry('/clip',
            props:
                '<z:getcontentlength>3</z:getcontentlength><z:getetag>&quot;revision-1&quot;</z:getetag>')));
      } else {
        expect(request.headers.value('if-match'), '"revision-1"');
        if (changed) {
          request.response.statusCode = 412;
        } else {
          request.response.add([1, 2, 3]);
        }
      }
      await request.response.close();
    });
    final service = WebDavService();
    try {
      await service.connect(
          baseUrl: 'http://127.0.0.1:${server.port}',
          username: '',
          password: '');
      final adapter = WebDavFileService(service: service);
      final file = (await adapter.getFile('/clip'))!;
      expect(
          await (await adapter.getFileStreamForRevision(file))
              .expand((x) => x)
              .toList(),
          [1, 2, 3]);
      changed = true;
      await expectLater(
          adapter.getFileStreamForRevision(file), throwsStateError);
      final task = DownloadTask(
          id: 'x',
          serverId: 's',
          remotePath: file.path,
          name: file.name,
          destination: 'unused',
          size: file.size,
          etag: fileEtag(file));
      expect(DownloadTask.fromJson(task.toJson()).etag, '"revision-1"');
      expect(DownloadTask.fromJson(task.toJson()..remove('etag')).etag, isNull);
    } finally {
      await service.disconnect();
      await server.close(force: true);
    }
  });
  test('unknown PROPFIND lengths use HEAD and stat matches requested resource',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var heads = 0;
    server.listen((request) async {
      if (request.method == 'HEAD') {
        heads++;
        request.response.contentLength = 123456789;
      } else {
        request.response.statusCode = 207;
        request.response.write(multi(entry('/dav/', props: rootProps) +
            entry('/dav/clip', props: '<z:resourcetype/>')));
      }
      await request.response.close();
    });
    final service = WebDavService();
    try {
      await service.connect(
          baseUrl: 'http://127.0.0.1:${server.port}/dav/',
          username: '',
          password: '');
      expect((await service.listFiles('/')).single.sizeKnown, isFalse);
      expect((await service.getFileInfo('/clip'))!.size, 123456789);
      expect(heads, 1);
      expect(await service.getFileInfo('/missing'), isNull);
      expect(heads, 1);
    } finally {
      await service.disconnect();
      await server.close(force: true);
    }
  });

  test('chunked range bodies must contain exactly the declared bytes',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var count = 2;
    server.listen((request) async {
      if (request.method == 'PROPFIND') {
        request.response.statusCode = 207;
        request.response.write(multi(''));
      } else {
        request.response.statusCode = 206;
        request.response.headers.set('content-range', 'bytes 3-5/6');
        request.response.add(List.generate(count, (i) => i));
      }
      await request.response.close();
    });
    final service = WebDavService();
    try {
      await service.connect(
          baseUrl: 'http://127.0.0.1:${server.port}',
          username: '',
          password: '');
      for (final length in [2, 4]) {
        count = length;
        final stream = await service.getFileStream('/file', start: 3, end: 5);
        await expectLater(stream.drain<void>(), throwsStateError);
      }
      count = 3;
      expect(
          await (await service.getFileStream('/file', start: 3, end: 5))
              .expand((c) => c)
              .toList(),
          [0, 1, 2]);
      await expectLater(
          service.getFileStream('/file', start: -1), throwsArgumentError);
      await expectLater(service.getFileStream('/file', start: 5, end: 3),
          throwsArgumentError);
    } finally {
      await service.disconnect();
      await server.close(force: true);
    }
  });

  test('configured subdirectory can connect when server root is forbidden',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      if (request.uri.path == '/allowed/') {
        request.response.statusCode = 207;
        request.response.write(multi(entry('/allowed/', props: rootProps)));
      } else {
        request.response.statusCode = 403;
      }
      await request.response.close();
    });
    final service = WebDavService();
    try {
      expect(
          await service.connect(
              baseUrl: 'http://127.0.0.1:${server.port}',
              username: '',
              password: '',
              probePath: '/allowed'),
          isTrue);
      await expectLater(service.listFiles('/'), throwsStateError);
      expect(service.isConnected, isTrue);
      expect(await service.listFiles('/allowed'), isEmpty);
    } finally {
      await service.disconnect();
      await server.close(force: true);
    }
  });

  test(
      'disconnect cancels an in-flight response instead of waiting for the network timeout',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    final requested = Completer<void>();
    server.listen((request) async {
      if (request.method == 'PROPFIND') {
        request.response.statusCode = 207;
        request.response.write(multi(''));
        await request.response.close();
      } else {
        requested.complete();
      }
    });
    final service = WebDavService();
    try {
      await service.connect(
          baseUrl: 'http://127.0.0.1:${server.port}',
          username: '',
          password: '');
      final reading =
          expectLater(service.getFileStream('/slow'), throwsA(anything));
      await requested.future;
      await service.disconnect();
      await reading.timeout(const Duration(seconds: 2));
      expect(service.isConnected, isFalse);
    } finally {
      await service.disconnect();
      await server.close(force: true);
    }
  });
}
