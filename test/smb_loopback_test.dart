import 'dart:async';
import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/libsmb2_service/libsmb2_bindings.dart';
import 'package:aloeplayer/libsmb2_service/libsmb2_service.dart';

void main() {
  const enabled = bool.fromEnvironment('SMB_LOOPBACK_TEST');
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
    } finally {
      await service.disconnect();
    }
  },
      skip: !enabled || !Platform.isWindows,
      timeout: const Timeout(Duration(minutes: 2)));
}
