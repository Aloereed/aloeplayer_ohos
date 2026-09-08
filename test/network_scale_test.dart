import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/services/file_service.dart';
import 'package:aloeplayer/services/http_service.dart';
import 'package:aloeplayer/services/webdav_service.dart';
import 'package:aloeplayer/models/server_config.dart';
import 'webdav_compatibility_test.dart' show entry, multi, rootProps;

const hugeSize = 5 * 1024 * 1024 * 1024 + 4096;
int pattern(int offset) => ((offset >> 32) ^ offset) & 255;

class _HugeSource implements FileService {
  @override
  bool get isConnected => true;
  @override
  Future<bool> connect(ServerConfig config) async => true;
  @override
  Future<void> disconnect() async {}
  @override
  Future<FileItem?> getFile(String path) async => WebDavFileItem(WebDavFile(
      name: 'large.mkv', path: path, size: hugeSize, isDirectory: false));
  @override
  Future<List<FileItem>> listFiles(String path) async => [];
  @override
  Future<Stream<Uint8List>> getFileStream(String path,
      {int? start, int? end}) async {
    if (start == null || end == null || end - start > 65536)
      throw StateError('Test requires a small explicit range');
    return Stream.value(Uint8List.fromList(
        List.generate(end - start + 1, (i) => pattern(start + i))));
  }
}

void main() {
  test('proxy preserves 64-bit lengths, seeks above 4 GiB and suffix ranges',
      () async {
    final proxy = HttpService.forTesting(_HugeSource());
    final client = HttpClient();
    try {
      await proxy.startServer();
      final url = Uri.parse(proxy.getFileUrlLocalhost('/large.mkv'));
      final head = await (await client.openUrl('HEAD', url)).close();
      expect(head.contentLength, hugeSize);
      await head.drain<void>();
      for (final start in [4 * 1024 * 1024 * 1024 + 123, hugeSize - 17]) {
        final request = await client.getUrl(url);
        request.headers.set(
            'range',
            start == hugeSize - 17
                ? 'bytes=-17'
                : 'bytes=$start-${start + 16}');
        final response = await request.close();
        expect(response.statusCode, 206);
        expect(response.headers.value('content-range'),
            'bytes $start-${start + 16}/$hugeSize');
        expect(await response.expand((x) => x).toList(),
            List.generate(17, (i) => pattern(start + i)));
      }
    } finally {
      client.close(force: true);
      await proxy.stopServer();
    }
  });

  test(
      '20,000-entry DAV directory parses with large sizes and remains asynchronously responsive',
      () async {
    const count = 20000;
    final listing = multi(entry('/', props: rootProps) +
        List.generate(
                count,
                (i) => entry('/episode-$i.mkv',
                    props:
                        '<z:getcontentlength>$hugeSize</z:getcontentlength>'))
            .join());
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) async {
      request.response.statusCode = 207;
      request.response.write(request.headers.value('depth') == '1'
          ? listing
          : multi(entry('/', props: rootProps)));
      await request.response.close();
    });
    final service = WebDavService();
    var ticks = 0;
    Timer? timer;
    try {
      await service.connect(
          baseUrl: 'http://127.0.0.1:${server.port}',
          username: '',
          password: '');
      final clock = Stopwatch()..start();
      timer = Timer.periodic(const Duration(milliseconds: 5), (_) => ticks++);
      final files = await service.listFiles('/');
      clock.stop();
      expect(files.length, count);
      expect(files.last.size, hugeSize);
      expect(files.last.path, '/episode-19999.mkv');
      expect(ticks, greaterThan(0));
      print(
          'DAV_SCALE entries=$count xmlChars=${listing.length} elapsedMs=${clock.elapsedMilliseconds} timerTicks=$ticks');
    } finally {
      timer?.cancel();
      await service.disconnect();
      await server.close(force: true);
    }
  });
}
