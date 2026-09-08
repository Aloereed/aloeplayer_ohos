import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/libsmb2_service/smb_worker.dart';
import 'package:aloeplayer/services/smb_service.dart';
import 'package:aloeplayer/services/file_service.dart';
import 'package:aloeplayer/models/server_config.dart';
import 'package:aloeplayer/libsmb2_service/libsmb2_file.dart';
import 'package:aloeplayer/libsmb2_service/smb_operation_error.dart';

class _Backend implements SmbWorkerBackend {
  bool closed = false;
  Map<String, dynamic> options = {};
  @override
  Future<bool> connect(Map<String, dynamic> options) async {
    this.options = options;
    sleep(const Duration(milliseconds: 150));
    return true;
  }

  @override
  Future<void> disconnect() async {}
  @override
  Future<List<Libsmb2File>> list(String path) async {
    if (path == '/slow') sleep(const Duration(milliseconds: 750));
    return [await stat(path)];
  }

  @override
  Future<Libsmb2File> stat(String path) async {
    if (path == '/absent') throw SmbOperationError(-2, 'not found');
    if (path == '/denied') throw SmbOperationError(-13, 'access denied');
    if (path == 'missing') throw StateError('missing');
    return Libsmb2File(
        name: path == 'closed' ? '$closed' : '片段.mp4',
        path: path,
        isDirectory: false,
        size: 6);
  }

  @override
  Future<Stream<Uint8List>> range(String path, int start, int? end) async =>
      path == '/flags'
          ? Stream.value(Uint8List.fromList([
              options['signingRequired'] == true ? 1 : 0,
              options['anonymousLogin'] == true ? 1 : 0,
              options['encryption'] == true ? 1 : 0
            ]))
          : _read(start, end ?? 6);
  Stream<Uint8List> _read(int start, int end) async* {
    try {
      for (var offset = start; offset < end; offset += 2) {
        yield Uint8List.fromList(List<int>.generate(
            end - offset < 2 ? end - offset : 2, (i) => offset + i));
      }
    } finally {
      closed = true;
    }
  }
}

void _entry(SendPort output) => serveSmbWorker(output, _Backend());

void main() {
  test(
      'SMB media reads remain independent of slow directory work and preserve security options',
      () async {
    var readers = 0;
    final service =
        SmbService.forTesting(SmbWorker.forTesting(_entry), readerFactory: () {
      readers++;
      return SmbWorker.forTesting(_entry);
    });
    try {
      await service.connect(
          host: 'nas',
          username: '',
          password: '',
          domain: '',
          signingRequired: true,
          anonymousLogin: true,
          encryption: true);
      expect(readers, 0); // Directory-only browsing starts no reader worker.
      expect(
          await (await service.getFileStream('/flags'))
              .expand((x) => x)
              .toList(),
          [1, 1, 1]);
      var directoryFinished = false;
      final directory = service.listFiles('/slow').then((value) {
        directoryFinished = true;
        return value;
      });
      final stream = await service.getRangeStream('/clip', start: 1, end: 4);
      expect(await stream.expand((x) => x).toList(), [1, 2, 3]);
      expect(directoryFinished, isFalse);
      expect(readers, 1);
      await directory;
      final stale = await service.getFileStream('/old');
      await service.disconnect();
      await service.connect(
          host: 'new', username: '', password: '', domain: '');
      await expectLater(stale.drain<void>(), throwsStateError);
      expect(
          await (await service.getFileStream('/flags'))
              .expand((x) => x)
              .toList(),
          [0, 0, 0]);
      expect(readers, 2);
    } finally {
      await service.disconnect();
    }
  });

  test(
      'disconnect during lazy SMB reader startup closes it and rejects the pending read',
      () async {
    final service = SmbService.forTesting(SmbWorker.forTesting(_entry),
        readerFactory: () => SmbWorker.forTesting(_entry));
    await service.connect(host: 'nas', username: '', password: '', domain: '');
    final pending =
        expectLater(service.getFileStream('/clip'), throwsStateError);
    await service.disconnect();
    await pending;
    expect(service.isConnected, isFalse);
    await service.connect(host: 'nas', username: '', password: '', domain: '');
    expect(
        await (await service.getRangeStream('/clip', start: 2, end: 4))
            .expand((x) => x)
            .toList(),
        [2, 3]);
    await service.disconnect();
  });
  test('old streams cannot read or close reused reader IDs after reconnect',
      () async {
    final worker = SmbWorker.forTesting(_entry);
    try {
      await worker.connect(host: 'nas', username: '', password: '', domain: '');
      final old = StreamIterator(await worker.getRangeStream('/old', start: 0));
      expect(await old.moveNext(), isTrue);
      final delayed =
          await worker.getRangeStream('/not-yet-listened', start: 0);
      await worker.disconnect();
      await worker.connect(host: 'nas', username: '', password: '', domain: '');
      final current =
          StreamIterator(await worker.getRangeStream('/new', start: 0));
      expect(await current.moveNext(), isTrue);
      await expectLater(old.moveNext(), throwsStateError);
      await expectLater(delayed.drain<void>(), throwsStateError);
      expect(await current.moveNext(), isTrue);
      expect(current.current, [2, 3]);
      await old.cancel();
      await current.cancel();
    } finally {
      await worker.disconnect();
    }
  });
  test(
      'SMB worker isolates blocking work, transfers bounded chunks and survives operation errors',
      () async {
    final worker = SmbWorker.forTesting(_entry);
    var ticks = 0;
    final timer =
        Timer.periodic(const Duration(milliseconds: 10), (_) => ticks++);
    try {
      expect(
          await worker.connect(
              host: 'nas', username: '', password: '', domain: ''),
          isTrue);
      expect(ticks, greaterThan(5));
      expect((await worker.listFiles('/')).single.name, '片段.mp4');
      await expectLater(worker.getFile('missing'), throwsStateError);
      expect((await worker.getFile('/')).size, 6);
      final stream = await worker.getRangeStream('/video', start: 1, end: 5);
      expect(await stream.expand((chunk) => chunk).toList(), [1, 2, 3, 4]);
      final partial =
          StreamIterator(await worker.getRangeStream('/video', start: 0));
      expect(await partial.moveNext(), isTrue);
      expect(partial.current, [0, 1]);
      await partial.cancel();
      expect((await worker.getFile('closed')).name, 'true');
      await worker.disconnect();
      expect(worker.isConnected, isFalse);
      expect(
          await worker.connect(
              host: 'nas', username: '', password: '', domain: ''),
          isTrue);
      expect((await worker.getFile('/')).size, 6);
    } finally {
      timer.cancel();
      await worker.disconnect();
    }
  });
  test(
      'file-service adapter preserves inclusive range semantics through worker',
      () async {
    final service = SmbFileService(
        service: SmbService.forTesting(SmbWorker.forTesting(_entry),
            readerFactory: () => SmbWorker.forTesting(_entry)));
    try {
      final config = ServerConfig(
          id: 'server',
          name: 'NAS',
          type: ServerType.smb,
          host: 'nas',
          username: '',
          password: '',
          createdAt: DateTime(2026));
      expect(await service.connect(config), isTrue);
      expect((await service.listFiles('/')).single.name, '片段.mp4');
      expect(await service.getFile('/absent'), isNull);
      await expectLater(
          service.getFile('/denied'),
          throwsA(
              isA<SmbOperationError>().having((e) => e.code, 'errno', -13)));
      expect(
          await (await service.getFileStream('/video', start: 1, end: 3))
              .expand((chunk) => chunk)
              .toList(),
          [1, 2, 3]);
    } finally {
      await service.disconnect();
    }
  });
}
