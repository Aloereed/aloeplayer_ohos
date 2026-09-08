import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:async';
import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/libsmb2_service/libsmb2_bindings.dart';
import 'package:aloeplayer/libsmb2_service/smb_share_enum.dart';
import 'package:aloeplayer/libsmb2_service/libsmb2_service.dart';

void main() {
  test('denied IPC does not prevent authenticated access to a known share',
      () async {
    final library = ffi.DynamicLibrary.open(
        File('build/smb_enum_fixture.dll').absolute.path);
    final reset = library.lookupFunction<ffi.Void Function(ffi.Int32),
        void Function(int)>('fixture_reset');
    final contexts =
        library.lookupFunction<ffi.Int32 Function(), int Function()>(
            'fixture_contexts');
    final service = Libsmb2Service(bindings: Libsmb2Bindings(library: library));
    reset(6);
    try {
      await service.connect(
          host: 'nas', username: '', password: '', domain: '');
      expect(contexts(), 0); // No IPC dependency for a virtual root.
      await expectLater(service.listFiles('/'), throwsException);
      expect(service.isConnected, isTrue);
      expect((await service.listFiles('/Videos')).single.path,
          '/Videos/clip #100%.mkv');
      expect(
          await (await service.getRangeStream('/Videos/clip', start: 0))
              .expand((x) => x)
              .toList(),
          [0, 1, 2, 3, 4, 5]);
      // Enumeration retry may acquire a new IPC context without replacing data shares.
      reset(0);
      expect((await service.listFiles('/')).length, 2);
    } finally {
      await service.disconnect();
      reset(0);
    }
    expect(contexts(), 0);
  },
      skip: !Platform.isWindows ||
          !File('build/smb_enum_fixture.dll').existsSync());
  test('SMB negotiation deadline aborts pending callback before releasing it',
      () {
    final library = ffi.DynamicLibrary.open(
        File('build/smb_enum_fixture.dll').absolute.path);
    final reset = library.lookupFunction<ffi.Void Function(ffi.Int32),
        void Function(int)>('fixture_reset');
    final abort = library.lookupFunction<
        ffi.Void Function(ffi.Pointer<Smb2Context>),
        void Function(ffi.Pointer<Smb2Context>)>('fixture_abort');
    final aborted =
        library.lookupFunction<ffi.Int32 Function(), int Function()>(
            'fixture_aborted');
    final text = 'test'.toNativeUtf8();
    reset(5);
    try {
      final context = ffi.Pointer<Smb2Context>.fromAddress(1);
      expect(
          () => connectSmbShare(
              library, context, text, text, text, () => abort(context),
              timeout: const Duration(milliseconds: 20)),
          throwsStateError);
      expect(aborted(), 1);
    } finally {
      calloc.free(text);
      reset(0);
    }
  },
      skip: !Platform.isWindows ||
          !File('build/smb_enum_fixture.dll').existsSync());
  final fixture = File('build/smb_enum_fixture.dll');
  final unavailable = !Platform.isWindows || !fixture.existsSync()
      ? 'Build test/native/smb_enum_fixture.c first'
      : false;
  test(
      'SMB respects negotiated read limits and reduces native calls for capable servers',
      () async {
    final library = ffi.DynamicLibrary.open(fixture.absolute.path);
    final mode = library.lookupFunction<ffi.Void Function(ffi.Int32),
        void Function(int)>('fixture_read_mode');
    final reads = library
        .lookupFunction<ffi.Int32 Function(), int Function()>('fixture_reads');
    final service = Libsmb2Service(bindings: Libsmb2Bindings(library: library));
    try {
      await service.connect(
          host: 'nas/Videos', username: '', password: '', domain: '');
      for (final value in [3, 4]) {
        mode(value);
        var bytes = 0;
        await for (final chunk in await service.getFileStream('/large')) {
          expect(chunk.first, bytes % 256);
          expect(chunk.last, (bytes + chunk.length - 1) % 256);
          bytes += chunk.length;
        }
        expect(bytes, 8 * 1024 * 1024);
        expect(reads(), value == 3 ? 8 : 128);
      }
    } finally {
      mode(0);
      await service.disconnect();
    }
  }, skip: unavailable);
  test('SMB closes handles after stat failure and reports early EOF', () async {
    final library = ffi.DynamicLibrary.open(fixture.absolute.path);
    final mode = library.lookupFunction<ffi.Void Function(ffi.Int32),
        void Function(int)>('fixture_read_mode');
    final handles =
        library.lookupFunction<ffi.Int32 Function(), int Function()>(
            'fixture_handles');
    final service = Libsmb2Service(bindings: Libsmb2Bindings(library: library));
    try {
      await service.connect(
          host: 'nas/Videos', username: '', password: '', domain: '');
      mode(1);
      await expectLater(
          service.getRangeStream('/clip', start: 0), throwsException);
      expect(handles(), 0);
      mode(2);
      await expectLater(
          (await service.getRangeStream('/clip', start: 0)).drain<void>(),
          throwsStateError);
      expect(handles(), 0);
      mode(0);
      expect(await (await service.getRangeStream('/clip', start: 6)).toList(),
          isEmpty);
      expect(
          await (await service.getRangeStream('/clip', start: 3, end: 100))
              .expand((c) => c)
              .toList(),
          [3, 4, 5]);
      await expectLater(
          (await service.getRangeStream('/clip', start: 0, chunkSize: 0))
              .drain<void>(),
          throwsArgumentError);
      expect(handles(), 0);
    } finally {
      mode(0);
      await service.disconnect();
    }
  }, skip: unavailable);
  test(
      'native SRVSVC ABI, filtering, failures and cancellation callback lifetime',
      () {
    final library = ffi.DynamicLibrary.open(fixture.absolute.path);
    final reset = library.lookupFunction<ffi.Void Function(ffi.Int32),
        void Function(int)>('fixture_reset');
    final freed = library
        .lookupFunction<ffi.Int32 Function(), int Function()>('fixture_freed');
    final aborted =
        library.lookupFunction<ffi.Int32 Function(), int Function()>(
            'fixture_aborted');
    final replySize =
        library.lookupFunction<ffi.Int32 Function(), int Function()>(
            'fixture_reply_size');
    final entrySize =
        library.lookupFunction<ffi.Int32 Function(), int Function()>(
            'fixture_entry_size');
    final abort = library.lookupFunction<
        ffi.Void Function(ffi.Pointer<Smb2Context>),
        void Function(ffi.Pointer<Smb2Context>)>('fixture_abort');
    final context = ffi.Pointer<Smb2Context>.fromAddress(1);
    expect(ffi.sizeOf<ShareEnumReply>(), replySize());
    expect(ffi.sizeOf<ShareInfo1>(), entrySize());
    reset(0);
    expect(enumerateSmbShares(library, context, () => abort(context)),
        ['C\$', 'Videos']);
    expect(freed(), 1);
    for (final mode in [1, 2, 3, 4]) {
      reset(mode);
      expect(() => enumerateSmbShares(library, context, () => abort(context)),
          throwsStateError);
      expect(freed(), mode <= 2 ? 1 : 0);
      expect(aborted(), mode == 4 ? 1 : 0);
    }
  }, skip: unavailable);
  test(
      'server root routes stat/list/stream across independent shares and bounds idle connections',
      () async {
    final library = ffi.DynamicLibrary.open(fixture.absolute.path);
    final reset = library.lookupFunction<ffi.Void Function(ffi.Int32),
        void Function(int)>('fixture_reset');
    final contexts =
        library.lookupFunction<ffi.Int32 Function(), int Function()>(
            'fixture_contexts');
    final lastPath = library.lookupFunction<ffi.Pointer<Utf8> Function(),
        ffi.Pointer<Utf8> Function()>('fixture_last_path');
    reset(0);
    final service = Libsmb2Service(bindings: Libsmb2Bindings(library: library));
    try {
      expect(
          await service.connect(
              host: 'smb://nas/',
              username: 'user',
              password: 'pass',
              domain: ''),
          isTrue);
      expect((await service.listFiles('/')).map((file) => file.path),
          ['/C\$', '/Videos']);
      expect((await service.getFile('/')).isDirectory, isTrue);
      expect((await service.getFile('/Videos')).isDirectory, isTrue);
      final file = (await service.listFiles('/Videos')).single;
      expect(file.path, '/Videos/clip #100%.mkv');
      expect(lastPath().toDartString(), '');
      final reader = StreamIterator(await service.getRangeStream(file.path,
          start: 1, end: 5, chunkSize: 2));
      expect(await reader.moveNext(), isTrue);
      expect(reader.current, [1, 2]);
      expect((await service.listFiles('/Other/Folder')).single.path,
          '/Other/Folder/clip #100%.mkv');
      expect(lastPath().toDartString(), 'Folder');
      await expectLater(service.listFiles('/Denied'), throwsException);
      // More shares than the idle limit must not evict the live Videos reader.
      for (var i = 0; i < 12; i++) {
        await service.listFiles('/Share$i');
      }
      expect(contexts(), 9); // IPC$ + at most eight data shares.
      expect(await reader.moveNext(), isTrue);
      expect(reader.current, [3, 4]);
      await reader.cancel();
      expect((await service.listFiles('/')).length, 2);
      await service.disconnect();
      expect(contexts(), 0);
      expect(
          await service.connect(
              host: r'\\nas\Videos\nested',
              username: '',
              password: '',
              domain: ''),
          isTrue);
      expect((await service.listFiles('/')).single.path, '/clip #100%.mkv');
      expect(lastPath().toDartString(), 'nested');
      await service.getFile('/literal%20.mkv');
      expect(lastPath().toDartString(), 'nested/literal%20.mkv');
    } finally {
      await service.disconnect();
    }
    expect(contexts(), 0);
  }, skip: unavailable);
}
