import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/libsmb2_service/libsmb2_bindings.dart';
import 'package:aloeplayer/libsmb2_service/libsmb2_service.dart';
import 'package:aloeplayer/libsmb2_service/libsmb2_file.dart';
import 'package:aloeplayer/libsmb2_service/smb_worker.dart';
import 'package:aloeplayer/services/smb_service.dart';

class _WireBackend implements SmbWorkerBackend {
  late final Libsmb2Service service;
  _WireBackend() {
    final winsock = ffi.DynamicLibrary.open('ws2_32.dll');
    final startup = winsock.lookupFunction<
        ffi.Int32 Function(ffi.Uint16, ffi.Pointer<ffi.Void>),
        int Function(int, ffi.Pointer<ffi.Void>)>('WSAStartup');
    final data = calloc<ffi.Uint8>(512);
    try {
      if (startup(0x202, data.cast()) != 0)
        throw StateError('Winsock startup failed');
    } finally {
      calloc.free(data);
    }
    service = Libsmb2Service(
        bindings: Libsmb2Bindings(
            library: ffi.DynamicLibrary.open(
                File('build/smb-test-native/lib/libsmb2.dll').absolute.path)));
  }
  @override
  Future<bool> connect(Map<String, dynamic> options) => service.connect(
      host: options['host'],
      username: options['username'],
      password: options['password'],
      domain: options['domain'],
      signingRequired: options['signingRequired'],
      anonymousLogin: options['anonymousLogin'],
      encryption: options['encryption']);
  @override
  Future<List<Libsmb2File>> list(String path) => service.listFiles(path);
  @override
  Future<Libsmb2File> stat(String path) => service.getFile(path);
  @override
  Future<Stream<Uint8List>> range(String path, int start, int? end) =>
      service.getRangeStream(path, start: start, end: end);
  @override
  Future<void> disconnect() => service.disconnect();
}

void _wireEntry(SendPort output) => serveSmbWorker(output, _WireBackend());

void main() {
  const enabled = bool.fromEnvironment('SMB_LOOPBACK_TEST');
  test('real SMB worker reads stay byte-exact while a separate worker browses',
      () async {
    final config = jsonDecode(
        await File('build/smb-loopback-data/server.json').readAsString());
    final source = SmbService.forTesting(SmbWorker.forTesting(_wireEntry),
        readerFactory: () => SmbWorker.forTesting(_wireEntry));
    try {
      await source.connect(
          host: config['host'],
          username: config['username'],
          password: config['password'],
          domain: '');
      final file = (await source.listFiles('/Videos'))
          .firstWhere((f) => f.name == 'clip #100% 中文.mkv');
      var browses = 0;
      final browsing = () async {
        for (var i = 0; i < 20; i++) {
          expect(
              (await source.listFiles('/Other')).single.name, 'sub clip.mkv');
          browses++;
        }
      }();
      var bytes = 0;
      await for (final chunk in await source.getFileStream(file.path)) {
        for (var i = 0; i < chunk.length; i++) {
          expect(chunk[i], (bytes + i) % 256);
        }
        bytes += chunk.length;
      }
      await browsing;
      expect(bytes, 8 * 1024 * 1024);
      expect(browses, 20);
      expect(
          await (await source.getRangeStream(file.path,
                  start: 65530, end: 65550))
              .expand((x) => x)
              .toList(),
          List.generate(20, (i) => (65530 + i) % 256));
    } finally {
      await source.disconnect();
    }
  },
      skip: !enabled || !Platform.isWindows,
      timeout: const Timeout(Duration(minutes: 2)));
  test(
      'real SMB2 loopback enumerates shares, browses Unicode, reads ranges and crosses shares',
      () async {
    final config = jsonDecode(
        await File('build/smb-loopback-data/server.json').readAsString());
    expect(config['host'], startsWith('127.0.0.1:'));
    final winsock = ffi.DynamicLibrary.open('ws2_32.dll');
    final startup = winsock.lookupFunction<
        ffi.Int32 Function(ffi.Uint16, ffi.Pointer<ffi.Void>),
        int Function(int, ffi.Pointer<ffi.Void>)>('WSAStartup');
    final wsaData = calloc<ffi.Uint8>(512);
    expect(startup(0x202, wsaData.cast()), 0);
    calloc.free(wsaData);
    final library = ffi.DynamicLibrary.open(
        File('build/smb-test-native/lib/libsmb2.dll').absolute.path);
    final service = Libsmb2Service(bindings: Libsmb2Bindings(library: library));
    try {
      expect(
          await service.connect(
              host: config['host'],
              username: config['username'],
              password: config['password'],
              domain: ''),
          isTrue);
      final shares = await service.listFiles('/');
      expect(shares.map((f) => f.name.toLowerCase()),
          containsAll(['videos', 'other']));
      final videos =
          shares.firstWhere((f) => f.name.toLowerCase() == 'videos').path;
      final other =
          shares.firstWhere((f) => f.name.toLowerCase() == 'other').path;
      final files = await service.listFiles(videos);
      final video = files.firstWhere((f) => f.name == 'clip #100% 中文.mkv');
      expect(video.size, 8 * 1024 * 1024);
      expect((await service.getFile(videos)).isDirectory, isTrue);
      expect((await service.getFile(video.path)).size, video.size);
      final stream = StreamIterator(await service.getRangeStream(video.path,
          start: 65530, end: 65550, chunkSize: 7));
      expect(await stream.moveNext(), isTrue);
      final first = stream.current.toList();
      expect(
          (await service.listFiles(other)).any((f) => f.name == 'sub clip.mkv'),
          isTrue);
      while (await stream.moveNext()) {
        first.addAll(stream.current);
      }
      expect(first, List.generate(20, (i) => (65530 + i) % 256));
      await stream.cancel();
      final empty = files.firstWhere((f) => f.name == 'empty.mp4');
      expect(await (await service.getFileStream(empty.path)).toList(), isEmpty);
      final clock = Stopwatch()..start();
      var count = 0, chunks = 0;
      await for (final bytes in await service.getFileStream(video.path)) {
        for (var i = 0; i < bytes.length; i++) {
          expect(bytes[i], (count + i) % 256);
        }
        count += bytes.length;
        chunks++;
      }
      clock.stop();
      expect(count, video.size);
      print(
          'LOOPBACK_READ bytes=$count chunks=$chunks elapsedMs=${clock.elapsedMilliseconds}');
      final strict =
          Libsmb2Service(bindings: Libsmb2Bindings(library: library));
      try {
        expect(
            await strict.connect(
                host: '${config['host']}/Videos',
                username: config['username'],
                password: config['password'],
                domain: '',
                signingRequired: true),
            isTrue);
        expect((await strict.listFiles('/')).any((f) => f.name == video.name),
            isTrue);
      } finally {
        await strict.disconnect();
      }
      final invalid =
          Libsmb2Service(bindings: Libsmb2Bindings(library: library));
      await expectLater(
          invalid.connect(
              host: '${config['host']}/Videos',
              username: config['username'],
              password: 'wrong-test-password',
              domain: ''),
          throwsA(anyOf(isA<Exception>(), isA<StateError>())));
      expect(invalid.isConnected, isFalse);
      final sealed =
          Libsmb2Service(bindings: Libsmb2Bindings(library: library));
      try {
        await expectLater(
            sealed.connect(
                host: '${config['host']}/Videos',
                username: config['username'],
                password: config['password'],
                domain: '',
                encryption: true),
            throwsA(anyOf(isA<Exception>(), isA<StateError>())));
        expect(sealed.isConnected, isFalse);
      } finally {
        await sealed.disconnect();
      }
    } finally {
      await service.disconnect();
    }
  },
      skip: !enabled || !Platform.isWindows,
      timeout: const Timeout(Duration(minutes: 2)));
}
