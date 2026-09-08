import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/services/webdav_service.dart';
import 'package:aloeplayer/services/webdav_retry.dart';
import 'package:aloeplayer/services/network_connection_probe.dart';
import 'package:aloeplayer/services/file_service.dart';
import 'package:aloeplayer/models/server_config.dart';
import 'webdav_compatibility_test.dart' show entry, multi, rootProps;

class _ProbeSource implements FileService {
  bool connected = false, closed = false, denied = false;
  bool failClose = false;
  String? path;
  @override
  bool get isConnected => connected;
  @override
  Future<bool> connect(ServerConfig config) async => connected = true;
  @override
  Future<void> disconnect() async {
    closed = true;
    connected = false;
    if (failClose) throw StateError('close failed');
  }

  @override
  Future<List<FileItem>> listFiles(String path) async {
    this.path = path;
    if (denied) throw StateError('denied');
    return [];
  }

  @override
  Future<FileItem?> getFile(String path) async => null;
  @override
  Future<Stream<Uint8List>> getFileStream(String path,
          {int? start, int? end}) async =>
      const Stream.empty();
}

void main() {
  test(
      'connection probe checks the actual protocol directory and always closes',
      () async {
    for (final type in ServerType.values) {
      final source = _ProbeSource();
      final config = ServerConfig(
          id: 'probe',
          name: 'probe',
          type: type,
          host: 'nas',
          username: '',
          password: '',
          initialPath: '/Videos',
          createdAt: DateTime(2026));
      expect(await probeNetworkConnection(config, source: source), 0);
      expect(source.path, type == ServerType.smb ? '/' : '/Videos');
      expect(source.closed, isTrue);
      source
        ..denied = true
        ..closed = false;
      await expectLater(
          probeNetworkConnection(config, source: source), throwsStateError);
      expect(source.closed, isTrue);
      source.failClose = true;
      await expectLater(
          probeNetworkConnection(config, source: source),
          throwsA(isA<StateError>()
              .having((e) => e.message, 'original failure', 'denied')));
    }
  });
  test('retry delay respects short server delays and declines long cooldowns',
      () {
    expect(webDavRetryDelay('2', 0), const Duration(seconds: 2));
    expect(webDavRetryDelay('30', 0), isNull);
    expect(webDavRetryDelay('-1', 0), isNull);
    final now = DateTime.utc(2026, 1, 1);
    expect(
        webDavRetryDelay(
            HttpDate.format(now.add(const Duration(seconds: 1))), 0,
            now: now),
        const Duration(seconds: 1));
  });
  test(
      'transient PROPFIND and range GET retry before bytes and preserve conditions',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var props = 0, gets = 0;
    server.listen((request) async {
      request.response.headers.set('retry-after', '0');
      if (request.method == 'PROPFIND') {
        props++;
        request.response.statusCode = props < 3 ? 503 : 207;
        if (props == 3)
          request.response.write(multi(entry('/', props: rootProps)));
      } else {
        gets++;
        expect(request.headers.value('range'), 'bytes=3-5');
        expect(request.headers.value('if-match'), '"v1"');
        request.response.statusCode = gets == 1 ? 502 : 206;
        if (gets == 2) {
          request.response.headers.set('content-range', 'bytes 3-5/6');
          request.response.add([3, 4, 5]);
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
      expect(props, 3);
      expect(
          await (await service.getFileStream('/clip',
                  start: 3, end: 5, expectedEtag: '"v1"'))
              .expand((x) => x)
              .toList(),
          [3, 4, 5]);
      expect(gets, 2);
    } finally {
      await service.disconnect();
      await server.close(force: true);
    }
  });
  test('disconnect cancels retry backoff and long Retry-After is not ignored',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var calls = 0;
    var delay = '2';
    final first = Completer<void>();
    server.listen((request) async {
      calls++;
      request.response.statusCode = 503;
      request.response.headers.set('retry-after', delay);
      await request.response.close();
      if (!first.isCompleted) first.complete();
    });
    final service = WebDavService();
    try {
      final pending = expectLater(
          service.connect(
              baseUrl: 'http://127.0.0.1:${server.port}',
              username: '',
              password: ''),
          throwsA(anything));
      await first.future;
      await service.disconnect();
      await pending;
      expect(calls, 1);
      delay = '30';
      await expectLater(
          service.connect(
              baseUrl: 'http://127.0.0.1:${server.port}',
              username: '',
              password: ''),
          throwsStateError);
      expect(calls, 2);
    } finally {
      await service.disconnect();
      await server.close(force: true);
    }
  });
}
