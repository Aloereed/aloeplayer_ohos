import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/services/private_space.dart';

void main() {
  late Directory temp;
  String? secret;
  late PrivateSpace space;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('private-space-test-');
    secret = null;
    space = PrivateSpace(
        directory: () async => Directory('${temp.path}/vault'),
        readSecret: () async => secret,
        writeSecret: (value) async {
          secret = value;
        });
    await space.initialize();
  });
  tearDown(() async {
    space.dispose();
    await temp.delete(recursive: true);
  });
  test(
      'PIN protects import, rejects guesses and persists cooldown across restart',
      () async {
    await expectLater(
        space.importFile('${temp.path}/missing.mp4'), throwsStateError);
    await space.configure('123456');
    space.lock();
    for (var i = 0; i < 5; i++) {
      expect(await space.unlock('000000'), isFalse);
    }
    final restarted = PrivateSpace(
        directory: () async => Directory('${temp.path}/vault'),
        readSecret: () async => secret,
        writeSecret: (value) async {
          secret = value;
        });
    addTearDown(restarted.dispose);
    await restarted.initialize();
    await expectLater(restarted.unlock('123456'), throwsStateError);
    expect(restarted.unlocked, isFalse);
  });
  test(
      'import copies and verifies bytes, private index excludes credentials, unlock restores list',
      () async {
    await space.configure('654321');
    final source = await File('${temp.path}/中文 #电影.mp4')
        .writeAsBytes(List.generate(65539, (i) => i % 256));
    final item = await space.importFile(source.path);
    expect(await File(space.sourceFor(item)).readAsBytes(),
        await source.readAsBytes());
    expect(await source.exists(), isTrue);
    expect(item.file, isNot(contains('电影')));
    final index = await File('${temp.path}/vault/index.json').readAsString();
    expect(index, isNot(contains('654321')));
    space.lock();
    expect(space.items, isEmpty);
    expect(() => space.sourceFor(item), throwsStateError);
    expect(await space.unlock('654321'), isTrue);
    expect(space.items.single.name, '中文 #电影.mp4');
    await space.delete(space.items.single);
    expect(space.items, isEmpty);
    expect(await source.exists(), isTrue);
  });
  test('failed source import leaves no index or partial files', () async {
    await space.configure('123456');
    await expectLater(space.importFile('${temp.path}/missing.mp4'),
        throwsA(isA<FileSystemException>()));
    expect(await Directory('${temp.path}/vault').list().toList(), isEmpty);
  });
  test('lost credentials cannot recreate PIN over an existing index', () async {
    await space.configure('123456');
    final source = await File('${temp.path}/test.mp4').writeAsBytes([1]);
    await space.importFile(source.path);
    secret = null;
    final restarted = PrivateSpace(
        directory: () async => Directory('${temp.path}/vault'),
        readSecret: () async => secret,
        writeSecret: (value) async {
          secret = value;
        });
    addTearDown(restarted.dispose);
    await expectLater(restarted.initialize(), throwsStateError);
    await expectLater(restarted.configure('111111'), throwsStateError);
  });
  test('path traversal in index fails closed', () async {
    await space.configure('123456');
    space.lock();
    await File('${temp.path}/vault/index.json').writeAsString(jsonEncode([
      {'id': 'x', 'name': 'x', 'file': '../outside.mp4', 'bytes': 1}
    ]));
    await expectLater(space.unlock('123456'), throwsStateError);
    expect(space.unlocked, isFalse);
    expect(space.items, isEmpty);
  });
  test('lock during pending authentication cannot reopen the space', () async {
    await space.configure('123456');
    space.lock();
    final gate = Completer<void>();
    final delayed = PrivateSpace(
        directory: () async => Directory('${temp.path}/vault'),
        readSecret: () async => secret,
        writeSecret: (_) => gate.future);
    addTearDown(delayed.dispose);
    await delayed.initialize();
    final pending = delayed.unlock('123456');
    await Future<void>.delayed(Duration.zero);
    delayed.lock();
    gate.complete();
    expect(await pending, isFalse);
    expect(delayed.unlocked, isFalse);
  });
  test('PIN change checks old PIN and secure storage failures never unlock',
      () async {
    await space.configure('123456');
    await expectLater(space.changePin('000000', '654321'), throwsStateError);
    await space.changePin('123456', '654321');
    space.lock();
    expect(await space.unlock('123456'), isFalse);
    expect(await space.unlock('654321'), isTrue);
    final failed = PrivateSpace(
        directory: () async => Directory('${temp.path}/failed'),
        readSecret: () async => null,
        writeSecret: (_) async => throw StateError('keystore unavailable'));
    addTearDown(failed.dispose);
    await failed.initialize();
    await expectLater(failed.configure('123456'), throwsStateError);
    expect(failed.unlocked, isFalse);
  });
  test('locking during file operations preserves unrelated private entries',
      () async {
    await space.configure('123456');
    final source = await File('${temp.path}/first.mp4').writeAsBytes([1, 2, 3]);
    await space.importFile(source.path);
    await space.importFile(source.path, name: 'second.mp4');
    final removal = space.delete(space.items.first);
    await Future<void>.delayed(Duration.zero);
    space.lock();
    await removal;
    expect(space.items, isEmpty);
    expect(await space.unlock('123456'), isTrue);
    expect(space.items.single.name, 'second.mp4');
    final large = await File('${temp.path}/large.mp4')
        .writeAsBytes(List.filled(4 * 1024 * 1024, 7));
    final importing = space.importFile(large.path);
    final check = expectLater(importing, throwsStateError);
    await Future<void>.delayed(Duration.zero);
    space.lock();
    await check;
    expect(await space.unlock('123456'), isTrue);
    expect(space.items.single.name, 'second.mp4');
    expect(await large.exists(), isTrue);
    expect(
        (await Directory('${temp.path}/vault').list().toList())
            .where((file) => file.path.endsWith('.pending')),
        isEmpty);
  });
}
