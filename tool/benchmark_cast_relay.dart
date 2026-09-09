/// Host-only throughput/memory observation, not a TV/Wi-Fi performance claim.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import '../lib/services/cast_media_relay.dart';

Future<void> main() async {
  final root = Directory('build').absolute;
  final temp = await root.createTemp('cast-relay-benchmark-');
  final file = File('${temp.path}/video.mp4');
  const size = 64 * 1024 * 1024;
  final chunk = Uint8List.fromList(List.generate(1024 * 1024, (i) => i % 256));
  final writer = await file.open(mode: FileMode.write);
  for (var i = 0; i < 64; i++) { await writer.writeFrom(chunk); }
  await writer.close();
  final expected = await sha256.bind(file.openRead()).first;
  final origin = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  origin.listen((request) async {
    request.response.contentLength = size;
    await request.response.addStream(file.openRead());
    await request.response.close();
  });
  final local = await CastMediaRelay.start(file.path, host: '127.0.0.1');
  final network = await CastMediaRelay.start('http://127.0.0.1:${origin.port}/video.mp4', host: '127.0.0.1');
  final reader = HttpClient();
  final cases = {'origin': 'http://127.0.0.1:${origin.port}/video.mp4', 'local_file_relay': local.url, 'network_relay': network.url};
  try {
    for (final entry in cases.entries) {
      var peakRss = ProcessInfo.currentRss;
      final watchMemory = Timer.periodic(const Duration(milliseconds: 10), (_) => peakRss = max(peakRss, ProcessInfo.currentRss));
      final watch = Stopwatch()..start();
      final response = await (await reader.getUrl(Uri.parse(entry.value))).close();
      if (response.statusCode != 200 || response.contentLength != size) throw StateError('Unexpected response');
      final received = await sha256.bind(response).first;
      watch.stop(); watchMemory.cancel();
      if (received != expected) throw StateError('Media hash mismatch');
      print(jsonEncode({'case':entry.key, 'bytes':size, 'ms':watch.elapsedMilliseconds,
        'MiB_per_second': 64 / (watch.elapsedMicroseconds / 1e6), 'process_peak_MiB':peakRss / 1048576, 'sha256':received.toString()}));
    }
  } finally {
    reader.close(force: true); await local.close(); await network.close(); await origin.close(force: true);
    if (temp.absolute.parent.path != root.path || !temp.path.contains('cast-relay-benchmark-')) throw StateError('Unexpected cleanup target');
    await temp.delete(recursive: true);
  }
}
