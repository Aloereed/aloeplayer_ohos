import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:aloeplayer/services/shortcut_source.dart';

void main() {
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('shortcut-source-');
  });
  tearDown(() => temp.delete(recursive: true));

  test('legacy paths encode delimiters and preserve literal percent sequences',
      () {
    for (final name in ['中文 #1?.mp4', '100%25.mp4', 'movie:part1.mp4']) {
      final path = '/storage/Users/currentUser/Download/$name';
      final original =
          Uri(scheme: 'file', host: 'docs', pathSegments: path.split('/'))
              .toString();
      expect(shortcutPermissionUri(path), original);
      expect(shortcutPermissionUri(original), original);
      expect(shortcutPlaybackSource(original), path);
    }
    expect(shortcutPlaybackSource('file://media/Photos/1/abc.mp4'),
        'file://media/Photos/1/abc.mp4');
    expect(shortcutPermissionUri('/Photos/1/abc.mp4'),
        'file://media/Photos/1/abc.mp4');
  });

  test('playback waits for activation and preserves picker URI exactly',
      () async {
    const source =
        'file://docs/storage/Users/currentUser/Download/movie%20%231%3F.mp4';
    final link = await File('${temp.path}/movie.lnk').writeAsString(source);
    final gate = Completer<bool>();
    var finished = false;
    final resolved = resolveMediaShortcut(link.path, checkReadable: false,
        activatePermission: (uri) {
      expect(uri, source);
      return gate.future;
    }).then((value) {
      finished = true;
      return value;
    });
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(finished, isFalse);
    gate.complete(true);
    expect(await resolved, '/storage/Users/currentUser/Download/movie #1?.mp4');
  });

  test('legacy link fails explicitly when permission was revoked', () async {
    final link = await File('${temp.path}/movie.lnk')
        .writeAsString('/storage/Users/currentUser/Download/a #1.mp4');
    await expectLater(
        resolveMediaShortcut(link.path, activatePermission: (uri) async {
          expect(uri, contains('a%20%231.mp4'));
          return false;
        }),
        throwsA(isA<FileSystemException>()
            .having((e) => e.message, 'message', contains('重新添加'))));
  });

  test('nonresponding permission channel times out with actionable message',
      () async {
    final link = await File('${temp.path}/movie.lnk')
        .writeAsString('file://docs/storage/test.mp4');
    await expectLater(
        resolveMediaShortcut(link.path,
            activatePermission: (_) => Completer<bool>().future,
            timeout: const Duration(milliseconds: 20)),
        throwsA(isA<FileSystemException>()
            .having((e) => e.message, 'message', contains('超时'))));
  });

  test(
      'permission platform failure is surfaced instead of opening the link file',
      () async {
    final link = await File('${temp.path}/movie.lnk')
        .writeAsString('file://docs/storage/test.mp4');
    await expectLater(
        resolveMediaShortcut(link.path,
            activatePermission: (_) async =>
                throw PlatformException(code: 'denied')),
        throwsA(isA<FileSystemException>()));
  });

  test(
      'empty and deleted targets fail; readable target preserves original bytes',
      () async {
    final link = await File('${temp.path}/movie.LNK').writeAsString('');
    await expectLater(
        resolveMediaShortcut(link.path), throwsA(isA<FileSystemException>()));
    final target =
        await File('${temp.path}/中文 #1%.mp4').writeAsBytes([1, 2, 3]);
    await link.writeAsString(target.path);
    expect(await resolveMediaShortcut(link.path), target.path);
    expect(await target.readAsBytes(), [1, 2, 3]);
    await target.delete();
    await expectLater(
        resolveMediaShortcut(link.path), throwsA(isA<FileSystemException>()));
  });

  test(
      'http targets do not request file permission and direct URLs stay intact',
      () async {
    const url = 'https://example.com/media.mp4?token=abc#part';
    final link = await File('${temp.path}/movie.lnk').writeAsString(url);
    expect(
        await resolveMediaShortcut(link.path,
            activatePermission: (_) async =>
                throw StateError('must not activate')),
        url);
    expect(await resolveMediaShortcut(url), url);
  });
}
