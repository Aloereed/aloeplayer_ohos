import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/services/audio_scan_service.dart';

List<int> _word(int value) => (ByteData(4)..setUint32(0, value, Endian.little)).buffer.asUint8List();
List<int> _chunk(String type, List<int> body) => [...ascii.encode(type), ..._word(body.length), ...body, if (body.length.isOdd) 0];
List<int> _wave(String title) {
  final format = ByteData(16)..setUint16(0, 1, Endian.little)..setUint16(2, 1, Endian.little)
    ..setUint32(4, 8000, Endian.little)..setUint32(8, 16000, Endian.little)..setUint16(12, 2, Endian.little)..setUint16(14, 16, Endian.little);
  final body = [...ascii.encode('WAVE'), ..._chunk('fmt ', format.buffer.asUint8List()),
    ..._chunk('LIST', [...ascii.encode('INFO'), ..._chunk('INAM', [...utf8.encode(title), 0])]), ..._chunk('data', List<int>.filled(160, 0))];
  return _chunk('RIFF', body);
}
void main() {
  test('audio tags parse in worker isolate and changed files invalidate cache', () async {
    final directory = await Directory.systemTemp.createTemp('aloe-audio-scan-');
    try {
      final file = await File('${directory.path}/test.wav').writeAsBytes(_wave('First'));
      final scanner = AudioScanService();
      expect((await scanner.read(file.path)).title, 'First');
      await file.writeAsBytes(_wave('Replacement title'));
      expect((await scanner.read(file.path)).title, 'Replacement title');
      expect(await readAudioArtwork(file.path), isNull);
    } finally { await directory.delete(recursive: true); }
  });
}
