import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'credential_store.dart';

class PrivateMedia {
  final String id, name, file;
  final int bytes;
  PrivateMedia(this.id, this.name, this.file, this.bytes);
  Map<String, Object> toJson() =>
      {'id': id, 'name': name, 'file': file, 'bytes': bytes};
}

class PrivateSpace extends ChangeNotifier {
  static final instance = PrivateSpace();
  final Future<Directory> Function() directory;
  final Future<String?> Function() readSecret;
  final Future<void> Function(String) writeSecret;
  PrivateSpace(
      {Future<Directory> Function()? directory,
      Future<String?> Function()? readSecret,
      Future<void> Function(String)? writeSecret})
      : directory = directory ??
            (() async => Directory(p.join(
                (await getApplicationSupportDirectory()).path,
                'private-space'))),
        readSecret =
            readSecret ?? (() => CredentialStore.read('private-space-v1')),
        writeSecret = writeSecret ??
            ((value) => CredentialStore.write('private-space-v1', value));
  bool configured = false, unlocked = false;
  int _epoch = 0;
  List<PrivateMedia> items = [];
  Map<String, dynamic>? _secret;
  Directory? _root;
  bool _initialized = false;
  Future<void> _tail = Future.value();
  Future<T> _serial<T>(Future<T> Function() action) {
    final next = _tail.then((_) => action());
    _tail = next.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return next;
  }

  Future<void> initialize() => _serial(() async {
        _initialized = false;
        _root ??= await directory();
        await _root!.create(recursive: true);
        final stored = await readSecret();
        _secret =
            stored == null ? null : jsonDecode(stored) as Map<String, dynamic>;
        configured = _secret != null;
        if (!configured &&
            await File(p.join(_root!.path, 'index.json')).exists()) {
          throw StateError('隐私空间安全凭据不可用，无法重设密码覆盖已有空间。');
        }
        _initialized = true;
      });
  void lock() {
    unlocked = false;
    items = [];
    _epoch++;
    notifyListeners();
  }

  void _requireOpen() {
    if (!unlocked) throw StateError('请先解锁隐私空间');
  }

  Future<void> _saveSecret(Map<String, dynamic> value) async {
    await writeSecret(jsonEncode(value));
    _secret = value;
  }

  Future<void> configure(String pin) => _serial(() async {
        final generation = _epoch;
        if (!_initialized) throw StateError('隐私空间尚未初始化');
        if (configured) throw StateError('隐私空间已设置密码');
        if (!RegExp(r'^\d{6}$').hasMatch(pin))
          throw StateError('请设置 6 位数字 PIN');
        // The PIN record is encrypted by the existing platform secure credential store.
        await _saveSecret({'pin': pin, 'failures': 0, 'retryAt': 0});
        configured = true;
        unlocked = generation == _epoch;
        notifyListeners();
      });
  Future<bool> unlock(String pin) => _serial(() async {
        if (_secret == null) throw StateError('请先设置密码');
        final generation = _epoch;
        final retryAt = _secret!['retryAt'] as int? ?? 0;
        if (DateTime.now().millisecondsSinceEpoch < retryAt)
          throw StateError('尝试过于频繁，请稍后再试');
        final expected = _secret!['pin'] as String;
        var difference = pin.length ^ expected.length;
        for (var i = 0; i < expected.length; i++) {
          difference |=
              expected.codeUnitAt(i) ^ (i < pin.length ? pin.codeUnitAt(i) : 0);
        }
        if (difference != 0) {
          final failures = (_secret!['failures'] as int? ?? 0) + 1;
          await _saveSecret({
            ..._secret!,
            'failures': failures,
            'retryAt': failures >= 5
                ? DateTime.now()
                    .add(const Duration(seconds: 30))
                    .millisecondsSinceEpoch
                : 0
          });
          return false;
        }
        await _saveSecret({..._secret!, 'failures': 0, 'retryAt': 0});
        if (generation != _epoch) return false;
        unlocked = true;
        try {
          await _reload();
        } catch (_) {
          lock();
          rethrow;
        }
        if (generation != _epoch) {
          items = [];
          return false;
        }
        notifyListeners();
        return true;
      });
  Future<void> changePin(String oldPin, String nextPin) async {
    if (!RegExp(r'^\d{6}$').hasMatch(nextPin))
      throw StateError('请输入 6 位数字 PIN');
    if (!await unlock(oldPin)) throw StateError('原 PIN 不正确');
    await _serial(() async {
      _requireOpen();
      await _saveSecret({..._secret!, 'pin': nextPin});
    });
  }

  Future<void> _reload() async {
    final index = File(p.join(_root!.path, 'index.json'));
    if (!await index.exists()) {
      items = [];
      return;
    }
    final rows = jsonDecode(await index.readAsString()) as List;
    items = rows.map((row) {
      final item = PrivateMedia(row['id'] as String, row['name'] as String,
          row['file'] as String, row['bytes'] as int);
      if (p.basename(item.file) != item.file ||
          !RegExp(r'^[a-f0-9]{32}\.[a-z0-9]+$').hasMatch(item.file))
        throw StateError('隐私空间索引损坏');
      return item;
    }).toList();
  }

  Future<void> _saveIndex(List<PrivateMedia> next) async {
    final temp = File(p.join(_root!.path, 'index.pending'));
    await temp.writeAsString(
        jsonEncode(next.map((item) => item.toJson()).toList()),
        flush: true);
    await temp.rename(p.join(_root!.path, 'index.json'));
    items = unlocked ? next : [];
    notifyListeners();
  }

  Future<PrivateMedia> importFile(String source, {String? name}) =>
      _serial(() async {
        _requireOpen();
        final generation = _epoch;
        final existing = List<PrivateMedia>.of(items);
        final input = File(source);
        final title = name ?? p.basename(source);
        final extension =
            p.extension(title).toLowerCase().replaceFirst('.', '');
        if (!RegExp(r'^[a-z0-9]{1,10}$').hasMatch(extension))
          throw StateError('请选择带扩展名的媒体文件');
        final id = List.generate(
            16,
            (_) => Random.secure()
                .nextInt(256)
                .toRadixString(16)
                .padLeft(2, '0')).join();
        final destination = File(p.join(_root!.path, '$id.$extension'));
        final pending = File('${destination.path}.pending');
        try {
          await input.copy(pending.path);
          if (await input.length() != await pending.length() ||
              (await sha256.bind(input.openRead()).first).toString() !=
                  (await sha256.bind(pending.openRead()).first).toString())
            throw StateError('文件复制校验失败，原文件已保留');
          if (!unlocked || generation != _epoch)
            throw StateError('隐私空间已锁定，请解锁后重新导入');
          await pending.rename(destination.path);
          final item = PrivateMedia(id, title, p.basename(destination.path),
              await destination.length());
          if (!unlocked || generation != _epoch)
            throw StateError('隐私空间已锁定，请解锁后重新导入');
          await _saveIndex([...existing, item]);
          return item;
        } catch (_) {
          if (await pending.exists()) await pending.delete();
          if (await destination.exists()) await destination.delete();
          rethrow;
        }
      });
  String sourceFor(PrivateMedia item) {
    _requireOpen();
    if (!items.any((entry) => identical(entry, item)))
      throw StateError('媒体不在隐私空间中');
    return p.join(_root!.path, item.file);
  }

  Future<void> delete(PrivateMedia item) => _serial(() async {
        final source = sourceFor(item);
        final next = items.where((entry) => entry.id != item.id).toList();
        if (await File(source).exists()) await File(source).delete();
        await _saveIndex(next);
      });
}
