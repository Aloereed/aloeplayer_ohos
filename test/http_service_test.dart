import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/services/http_service.dart';
import 'package:aloeplayer/services/file_service.dart';
import 'package:aloeplayer/models/server_config.dart';

class _File implements FileItem {
  @override String get name => '片段 #1.mp4';
  @override String get path => '/片段 #1.mp4';
  @override int get size => 10;
  @override bool get isDirectory => false;
  @override DateTime? get modified => null;
}
class _Source extends FileService {
  int reads = 0;
  @override bool get isConnected => true;
  @override Future<bool> connect(ServerConfig config) async => true;
  @override Future<void> disconnect() async {}
  @override Future<FileItem?> getFile(String path) async => path == _File().path ? _File() : null;
  @override Future<List<FileItem>> listFiles(String path) async => [_File()];
  @override Future<Stream<Uint8List>> getFileStream(String filePath, {int? start, int? end}) async {
    reads++;
    return Stream.value(Uint8List.fromList(utf8.encode('0123456789').sublist(start ?? 0, end == null ? null : end + 1)));
  }
}
void main() {
  test('loopback proxy enforces file grants and handles suffix ranges and HEAD', () async {
    final source = _Source();
    final proxy = HttpService.forTesting(source);
    final client = HttpClient();
    try {
      expect(await proxy.startServer(), isTrue);
      final url = Uri.parse(proxy.getFileUrlLocalhost(_File().path));
      expect(url.host, '127.0.0.1');
      final denied = await (await client.getUrl(url.replace(query: ''))).close();
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
    } finally { client.close(force: true); await proxy.stopServer(); }
  });
  test('LAN grants are isolated and stopping sharing preserves local playback', () async {
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
    } finally { client.close(force: true); await proxy.stopServer(); }
  });

}
