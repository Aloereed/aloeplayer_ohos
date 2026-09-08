import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/services/http_service.dart';
import 'package:aloeplayer/services/file_service.dart';
import 'package:aloeplayer/models/server_config.dart';
import 'package:aloeplayer/services/network_playback.dart';

class _File implements FileItem {
  @override
  String get name => '片段 #1.mp4';
  @override
  String get path => '/片段 #1.mp4';
  @override
  int get size => 10;
  @override
  bool get isDirectory => false;
  @override
  DateTime? get modified => null;
}

class _Source extends FileService {
  int reads = 0;
  int stats = 0;
  final String payload;
  _Source([this.payload = '0123456789']);
  @override
  bool get isConnected => true;
  @override
  Future<bool> connect(ServerConfig config) async => true;
  @override
  Future<void> disconnect() async {}
  @override
  Future<FileItem?> getFile(String path) async {
    stats++;
    await Future<void>.delayed(const Duration(milliseconds: 10));
    return path == _File().path ? _File() : null;
  }

  @override
  Future<List<FileItem>> listFiles(String path) async => [_File()];
  @override
  Future<Stream<Uint8List>> getFileStream(String filePath,
      {int? start, int? end}) async {
    reads++;
    return Stream.value(Uint8List.fromList(utf8
        .encode(payload)
        .sublist(start ?? 0, end == null ? null : end + 1)));
  }
}

void main() {
  test('proxy coalesces metadata and pins reused grants to the original source',
      () async {
    final first = _Source();
    final second = _Source('abcdefghij');
    final proxy = HttpService.forTesting(first);
    final client = HttpClient();
    Future<String> read(Uri url) async =>
        utf8.decoder.bind(await (await client.getUrl(url)).close()).join();
    try {
      await proxy.startServer();
      final old = Uri.parse(proxy.getFileUrlLocalhost(_File().path));
      expect(proxy.getFileUrlLocalhost(_File().path), old.toString());
      await Future.wait(List.generate(12, (_) async {
        final response = await (await client.openUrl('HEAD', old)).close();
        expect(response.statusCode, 200);
        await response.drain<void>();
      }));
      expect(first.stats, 1);
      expect(first.reads, 0);
      proxy.setFileService(second);
      final latest = Uri.parse(proxy.getFileUrlLocalhost(_File().path));
      expect(latest, isNot(old));
      expect(await read(old), '0123456789');
      expect(await read(latest), 'abcdefghij');
      expect(first.stats, 1);
      expect(second.stats, 1);
    } finally {
      client.close(force: true);
      await proxy.stopServer();
    }
  });

  test('large network queues index subtitle prefixes and reuse playback grants',
      () async {
    final proxy = HttpService.forTesting(_Source());
    final config = ServerConfig(
        id: 'nas',
        name: 'NAS',
        type: ServerType.smb,
        host: 'nas',
        username: '',
        password: '',
        createdAt: DateTime(2026));
    final files = <FileItem>[];
    for (var i = 0; i < 5000; i++) {
      files.add(_NamedFile('/season/episode.$i.mkv', name: '第 $i 集'));
      files.add(_NamedFile('/season/episode.$i.zh.ass'));
    }
    files.add(_NamedFile('/season/episode.0.en.srt'));
    try {
      await proxy.startServer();
      final clock = Stopwatch()..start();
      final queue = networkQueue(config, files, proxy);
      clock.stop();
      expect(queue.length, 5000);
      expect(queue.first.subtitles.length, 2);
      expect(queue.last.subtitles.length, 1);
      final repeated = networkQueue(config, files, proxy);
      expect(repeated.first.url, queue.first.url);
      expect(repeated.first.subtitles, queue.first.subtitles);
      print(
          'NETWORK_QUEUE media=5000 subtitles=5001 elapsedMs=${clock.elapsedMilliseconds}');
    } finally {
      await proxy.stopServer();
    }
  });
  test('loopback proxy enforces file grants and handles suffix ranges and HEAD',
      () async {
    final source = _Source();
    final proxy = HttpService.forTesting(source);
    final client = HttpClient();
    try {
      expect(await proxy.startServer(), isTrue);
      final url = Uri.parse(proxy.getFileUrlLocalhost(_File().path));
      expect(url.host, '127.0.0.1');
      final denied =
          await (await client.getUrl(url.replace(query: ''))).close();
      expect(denied.statusCode, 403);
      await denied.drain<void>();
      final request = await client.getUrl(url);
      request.headers.set('Range', 'bytes=-3');
      final response = await request.close();
      expect(response.statusCode, 206);
      expect(response.headers.value('content-range'), 'bytes 7-9/10');
      expect(await utf8.decoder.bind(response).join(), '789');
      final head = await (await client.openUrl('HEAD', url)).close();
      expect(head.contentLength, 10);
      expect(await head.fold<int>(0, (size, chunk) => size + chunk.length), 0);
      expect(source.reads, 1);
      final invalid = await client.getUrl(url);
      invalid.headers.set('Range', 'bytes=10-');
      final rejected = await invalid.close();
      expect(rejected.statusCode, 416);
      expect(rejected.headers.value('content-range'), 'bytes */10');
      await rejected.drain<void>();
    } finally {
      client.close(force: true);
      await proxy.stopServer();
    }
  });
  test('LAN grants are isolated and stopping sharing preserves local playback',
      () async {
    final proxy = HttpService.forTesting(_Source(), lanAddress: '127.0.0.1');
    final client = HttpClient();
    Future<int> status(Uri uri) async {
      final response = await (await client.getUrl(uri)).close();
      await response.drain<void>();
      return response.statusCode;
    }

    try {
      await proxy.startServer();
      final local = Uri.parse(proxy.getFileUrlLocalhost(_File().path));
      await proxy.enableLanSharing();
      final shared = Uri.parse(proxy.getFileUrl(_File().path));
      expect(shared.port, isNot(local.port));
      expect(await status(local), 200);
      expect(await status(shared), 200);
      expect(await status(local.replace(port: shared.port)), 403);
      expect(await status(shared.replace(port: local.port)), 403);
      await proxy.disableLanSharing();
      expect(await status(local), 200);
      await proxy.enableLanSharing();
      final renewed = Uri.parse(proxy.getFileUrl(_File().path));
      expect(await status(shared.replace(port: renewed.port)), 403);
      expect(await status(renewed), 200);
    } finally {
      client.close(force: true);
      await proxy.stopServer();
    }
  });
}

class _NamedFile implements FileItem {
  @override
  final String path;
  @override
  final String name;
  _NamedFile(this.path, {String? name}) : name = name ?? path.split('/').last;
  @override
  int get size => 10;
  @override
  bool get isDirectory => false;
  @override
  DateTime? get modified => null;
}
