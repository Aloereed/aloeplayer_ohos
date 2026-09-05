import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/libsmb2_service/smb_worker.dart';
import 'package:aloeplayer/libsmb2_service/libsmb2_file.dart';

class _Backend implements SmbWorkerBackend {
  bool closed = false;
  @override Future<bool> connect(Map<String, dynamic> options) async { sleep(const Duration(milliseconds: 150)); return true; }
  @override Future<void> disconnect() async {}
  @override Future<List<Libsmb2File>> list(String path) async => [await stat(path)];
  @override Future<Libsmb2File> stat(String path) async {
    if (path == 'missing') throw StateError('missing');
    return Libsmb2File(name: path == 'closed' ? '$closed' : '片段.mp4', path: path, isDirectory: false, size: 6);
  }
  @override Future<Stream<Uint8List>> range(String path, int start, int? end) async => _read(start, end ?? 6);
  Stream<Uint8List> _read(int start, int end) async* {
    try {
      for (var offset = start; offset < end; offset += 2) {
        yield Uint8List.fromList(List<int>.generate(end - offset < 2 ? end - offset : 2, (i) => offset + i));
      }
    } finally { closed = true; }
  }
}
void _entry(SendPort output) => serveSmbWorker(output, _Backend());

void main() {
  test('SMB worker isolates blocking work, transfers bounded chunks and survives operation errors', () async {
    final worker = SmbWorker.forTesting(_entry);
    var ticks = 0;
    final timer = Timer.periodic(const Duration(milliseconds: 10), (_) => ticks++);
    try {
      expect(await worker.connect(host: 'nas', username: '', password: '', domain: ''), isTrue);
      expect(ticks, greaterThan(5));
      expect((await worker.listFiles('/')).single.name, '片段.mp4');
      await expectLater(worker.getFile('missing'), throwsStateError);
      expect((await worker.getFile('/')).size, 6);
      final stream = await worker.getRangeStream('/video', start: 1, end: 5);
      expect(await stream.expand((chunk) => chunk).toList(), [1, 2, 3, 4]);
      final partial = StreamIterator(await worker.getRangeStream('/video', start: 0));
      expect(await partial.moveNext(), isTrue);
      expect(partial.current, [0, 1]);
      await partial.cancel();
      expect((await worker.getFile('closed')).name, 'true');
      await worker.disconnect();
      expect(worker.isConnected, isFalse);
      expect(await worker.connect(host: 'nas', username: '', password: '', domain: ''), isTrue);
      expect((await worker.getFile('/')).size, 6);
    } finally { timer.cancel(); await worker.disconnect(); }
  });
}
