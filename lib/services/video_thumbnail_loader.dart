import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as path;
import 'disk_thumbnail_cache.dart';
import 'thumbnail_cache.dart';

/// Cache failures must never hide a successfully decoded image. Legacy caches
/// used basenames, so only reuse them when the library has one matching file.
class VideoThumbnailLoader {
  final DiskThumbnailCache disk;
  final ThumbnailCache memory;
  final Directory library;
  final Future<Uint8List?> Function(String source) decode;
  Future<Map<String, int>>? _legacyNames;
  VideoThumbnailLoader(
      {required this.disk,
      required this.memory,
      required this.library,
      required this.decode});

  Future<Map<String, int>> _names() async {
    final names = <String, int>{};
    await for (final entry
        in library.list(recursive: true, followLinks: false)) {
      if (entry is File)
        names.update(path.basename(entry.path), (n) => n + 1,
            ifAbsent: () => 1);
    }
    return names;
  }

  Future<Uint8List?> load(File file) async {
    final source = file.path.endsWith('.lnk')
        ? (await file.readAsString()).trim()
        : file.path;
    var stat = await file.stat();
    try {
      // file://docs is a provider URI, not a regular Dart file URI.
      final uri = Uri.tryParse(source);
      final target = uri?.scheme == 'file' && uri!.host.isEmpty
          ? File.fromUri(uri)
          : File(source);
      final targetStat = await target.stat();
      if (targetStat.type == FileSystemEntityType.file) stat = targetStat;
    } catch (_) {/* Provider access can still work in the native decoder. */}
    final key = ThumbnailCache.key(
        source, stat.size, stat.modified.millisecondsSinceEpoch);
    final cached = memory.get(key);
    if (cached != null) return cached;
    try {
      final bytes = await disk.read(key);
      if (bytes != null && bytes.isNotEmpty) {
        memory.put(key, bytes);
        return bytes;
      }
    } catch (_) {/* A read-only or unavailable cache is optional. */}
    Uint8List? bytes;
    try {
      bytes = await decode(source);
    } catch (_) {}
    if (bytes == null || bytes.isEmpty) {
      try {
        final legacy = File(
            path.join(disk.directory.path, '${path.basename(file.path)}.jpg'));
        if (await legacy.exists() &&
            !(await legacy.lastModified()).isBefore(stat.modified)) {
          final names = await (_legacyNames ??= _names());
          if (names[path.basename(file.path)] == 1)
            bytes = await legacy.readAsBytes();
        }
      } catch (_) {
        _legacyNames = null;
      }
    }
    if (bytes == null || bytes.isEmpty) return null;
    memory.put(key, bytes);
    try {
      await disk.write(key, bytes);
    } catch (_) {}
    return bytes;
  }
}
