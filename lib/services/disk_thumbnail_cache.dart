import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as path;

/// Only owns revision-hash JPEG files in its directory; sidecars and media are
/// never candidates for eviction. Operations serialize to avoid evicting writes.
class DiskThumbnailCache {
  final Directory directory;
  final int maxBytes;
  final Map<String, ({int bytes, DateTime used})> _entries = {};
  Future<void> _tail = Future.value();
  bool _loaded = false;
  static final _owned = RegExp(r'^[a-f0-9]{64}\.jpg$');
  DiskThumbnailCache(this.directory, {this.maxBytes = 256 * 1024 * 1024});

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  Future<void> _load() async {
    if (_loaded) return;
    await directory.create(recursive: true);
    await for (final entry in directory.list(followLinks: false)) {
      if (entry is! File || !_owned.hasMatch(path.basename(entry.path))) continue;
      final stat = await entry.stat();
      _entries[path.basenameWithoutExtension(entry.path)] = (bytes: stat.size, used: stat.modified);
    }
    _loaded = true;
    await _prune();
  }

  File _file(String key) {
    if (!_owned.hasMatch('$key.jpg')) throw ArgumentError('Invalid thumbnail key');
    return File(path.join(directory.path, '$key.jpg'));
  }

  Future<Uint8List?> read(String key) => _serial(() async {
    await _load();
    final file = _file(key);
    if (!await file.exists()) { _entries.remove(key); return null; }
    final bytes = await file.readAsBytes();
    final now = DateTime.now();
    if (now.difference(_entries[key]?.used ?? DateTime(1970)).inHours >= 1) await file.setLastModified(now);
    _entries[key] = (bytes: bytes.length, used: now);
    return bytes;
  });

  Future<void> write(String key, Uint8List bytes) => _serial(() async {
    await _load();
    if (bytes.length > maxBytes) return;
    final file = _file(key);
    await directory.create(recursive: true);
    final temporary = File('${file.path}.part');
    try {
      await temporary.writeAsBytes(bytes, flush: true);
      await temporary.rename(file.path);
      _entries[key] = (bytes: bytes.length, used: DateTime.now());
      await _prune();
    } finally { if (await temporary.exists()) await temporary.delete(); }
  });

  Future<void> _prune() async {
    var total = _entries.values.fold<int>(0, (sum, item) => sum + item.bytes);
    final oldest = _entries.keys.toList()..sort((a, b) => _entries[a]!.used.compareTo(_entries[b]!.used));
    for (final key in oldest) {
      if (total <= maxBytes) break;
      final file = _file(key);
      if (await file.exists()) await file.delete();
      total -= _entries.remove(key)!.bytes;
    }
  }
}
