import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// Sequential cache writer. A completed wait only promises the requested bytes;
/// the growing file must not be treated as fully downloaded by a random-access player.
class StreamCacheService {
  static final StreamCacheService instance = StreamCacheService._();
  StreamCacheService._();
  final Map<String, _CacheTask> _activeTasks = {};
  Future<Directory> _directory() async {
    final directory = Directory(path.join((await getTemporaryDirectory()).path, 'stream-cache'));
    await directory.create(recursive: true);
    return directory;
  }
  Future<String> startStreamCache({required Stream<Uint8List> stream, required String fileName, required int fileSize}) async {
    final directory = await _directory();
    final file = File(path.join(directory.path, '${DateTime.now().microsecondsSinceEpoch}_${path.basename(fileName)}'));
    final task = _CacheTask(stream, await file.open(mode: FileMode.write), fileSize);
    _activeTasks[file.path] = task;
    task.run();
    return file.path;
  }
  double getCacheProgress(String cachePath) => _activeTasks[cachePath]?.progress ?? 0;
  Future<void> waitForMinimumCache(String cachePath, {int minBytes = 5 * 1024 * 1024}) async {
    final task = _activeTasks[cachePath];
    if (task == null) throw StateError('缓存任务不存在');
    await task.waitForBytes(minBytes);
  }
  Future<void> stopCache(String cachePath, {bool deleteFile = true}) async {
    final task = _activeTasks.remove(cachePath);
    await task?.stop();
    if (deleteFile && await File(cachePath).exists()) await File(cachePath).delete();
  }
  Future<void> clearAllCache() async {
    for (final key in _activeTasks.keys.toList()) { await stopCache(key); }
    final directory = await _directory();
    await for (final entry in directory.list()) { if (entry is File) await entry.delete(); }
  }
}
class _CacheTask {
  final StreamIterator<Uint8List> iterator;
  final RandomAccessFile file;
  final int expected;
  final List<_ByteWaiter> waiters = [];
  final Completer<void> closed = Completer();
  int written = 0;
  bool stopped = false;
  bool done = false;
  Object? error;
  _CacheTask(Stream<Uint8List> stream, this.file, this.expected) : iterator = StreamIterator(stream);
  double get progress => done && error == null ? 1 : expected > 0 ? (written / expected).clamp(0.0, 1.0) : 0;
  Future<void> run() async {
    try {
      while (!stopped && await iterator.moveNext()) {
        final chunk = iterator.current;
        await file.writeFrom(chunk);
        written += chunk.length;
        _notify();
      }
      if (!stopped && expected > 0 && written != expected) throw StateError('下载长度不符');
      await file.flush();
    } catch (issue) { error = issue; }
    finally {
      if (stopped) error ??= StateError('缓存已取消');
      done = true;
      await iterator.cancel();
      try { await file.close(); } catch (_) {}
      _notify();
      closed.complete();
    }
  }
  Future<void> waitForBytes(int bytes) async {
    if (error != null) throw error!;
    final target = expected > 0 && bytes > expected ? expected : bytes;
    if (written >= target || done) return;
    final waiter = _ByteWaiter(target);
    waiters.add(waiter);
    await waiter.ready.future;
  }
  void _notify() {
    for (final waiter in waiters.toList()) {
      if (error != null || written >= waiter.target || done) {
        waiters.remove(waiter);
        if (error != null) { waiter.ready.completeError(error!); } else { waiter.ready.complete(); }
      }
    }
  }
  Future<void> stop() async {
    stopped = true;
    await iterator.cancel();
    await closed.future;
  }
}
class _ByteWaiter {
  final int target;
  final Completer<void> ready = Completer();
  _ByteWaiter(this.target);
}
