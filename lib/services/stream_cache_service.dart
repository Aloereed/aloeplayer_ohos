// lib/services/stream_cache_service.dart
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as path;

/// 流式缓存服务 - 支持边下载边播放
/// 将 SMB/WebDAV Stream 写入临时文件，同时允许播放器读取
class StreamCacheService {
  static final StreamCacheService _instance = StreamCacheService._();
  static StreamCacheService get instance => _instance;
  StreamCacheService._();

  // 缓存目录
  final String _cacheDir = '/storage/Users/currentUser/Download/com.aloereed.aloeplayer/StreamCache';

  // 当前正在缓存的文件列表
  final Map<String, _CacheTask> _activeTasks = {};

  /// 开始流式缓存
  /// [stream] SMB/WebDAV 文件流
  /// [fileName] 文件名（用于创建缓存文件）
  /// [fileSize] 文件总大小（用于预分配空间和进度显示）
  /// 返回本地缓存文件路径，可以直接传给播放器
  Future<String> startStreamCache({
    required Stream<Uint8List> stream,
    required String fileName,
    required int fileSize,
  }) async {
    // 创建缓存目录
    final cacheDirectory = Directory(_cacheDir);
    if (!await cacheDirectory.exists()) {
      await cacheDirectory.create(recursive: true);
    }

    // 生成唯一的缓存文件路径
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final ext = path.extension(fileName);
    final cachePath = path.join(_cacheDir, '${timestamp}_${path.basenameWithoutExtension(fileName)}$ext');

    // 创建缓存文件
    final cacheFile = File(cachePath);

    // 预分配文件空间（可选，有助于减少碎片）
    final randomAccess = await cacheFile.open(mode: FileMode.write);
    if (fileSize > 0) {
      try {
        // 设置文件长度（预分配空间）
        await randomAccess.truncate(fileSize);
        await randomAccess.setPosition(0);
      } catch (e) {
        print('预分配文件空间失败: $e');
      }
    }

    // 创建缓存任务
    final task = _CacheTask(
      stream: stream,
      file: randomAccess,
      fileSize: fileSize,
      cachePath: cachePath,
    );
    _activeTasks[cachePath] = task;

    // 启动后台写入任务
    task.start();

    return cachePath;
  }

  /// 获取缓存进度
  double getCacheProgress(String cachePath) {
    final task = _activeTasks[cachePath];
    if (task == null) return 1.0;
    return task.progress;
  }

  /// 等待最小缓存量（用于播放前的缓冲）
  /// [cachePath] 缓存文件路径
  /// [minBytes] 最小缓存字节数（默认 5MB）
  Future<void> waitForMinimumCache(String cachePath, {int minBytes = 5 * 1024 * 1024}) async {
    final task = _activeTasks[cachePath];
    if (task == null) return;
    await task.waitForBytes(minBytes);
  }

  /// 停止并清理缓存任务
  Future<void> stopCache(String cachePath, {bool deleteFile = true}) async {
    final task = _activeTasks.remove(cachePath);
    if (task != null) {
      await task.stop();

      if (deleteFile) {
        try {
          final file = File(cachePath);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (e) {
          print('删除缓存文件失败: $e');
        }
      }
    }
  }

  /// 清理所有缓存
  Future<void> clearAllCache() async {
    // 停止所有活动任务
    final paths = _activeTasks.keys.toList();
    for (final path in paths) {
      await stopCache(path, deleteFile: true);
    }

    // 清理缓存目录中的残留文件
    try {
      final cacheDirectory = Directory(_cacheDir);
      if (await cacheDirectory.exists()) {
        await for (final entity in cacheDirectory.list()) {
          if (entity is File) {
            try {
              await entity.delete();
            } catch (e) {
              print('删除缓存文件失败: ${entity.path}, $e');
            }
          }
        }
      }
    } catch (e) {
      print('清理缓存目录失败: $e');
    }
  }
}

/// 缓存任务
class _CacheTask {
  final Stream<Uint8List> stream;
  final RandomAccessFile file;
  final int fileSize;
  final String cachePath;

  int _bytesWritten = 0;
  bool _isRunning = false;
  bool _isCompleted = false;
  Exception? _error;

  StreamSubscription<Uint8List>? _subscription;
  final Completer<void> _completedCompleter = Completer<void>();
  final List<Completer<void>> _bytesWaiters = [];

  _CacheTask({
    required this.stream,
    required this.file,
    required this.fileSize,
    required this.cachePath,
  });

  /// 获取下载进度 (0.0 - 1.0)
  double get progress {
    if (_isCompleted) return 1.0;
    if (fileSize <= 0) return 0.0;
    return _bytesWritten / fileSize;
  }

  /// 启动缓存任务
  void start() {
    if (_isRunning) return;
    _isRunning = true;

    print('开始流式缓存: $cachePath, 文件大小: ${_formatSize(fileSize)}');

    _subscription = stream.listen(
      (chunk) async {
        try {
          // 写入数据到文件
          await file.writeFrom(chunk);
          _bytesWritten += chunk.length;

          // 每5MB打印一次进度
          if (_bytesWritten % (5 * 1024 * 1024) < chunk.length) {
            print('缓存进度: ${(_formatSize(_bytesWritten))}/${_formatSize(fileSize)} (${(progress * 100).toStringAsFixed(1)}%)');
          }

          // 通知等待者
          _notifyWaiters();
        } catch (e) {
          print('写入缓存文件失败: $e');
          _error = Exception('写入缓存文件失败: $e');
          await stop();
        }
      },
      onError: (error) {
        print('流式缓存错误: $error');
        _error = Exception('流式缓存错误: $error');
        _isCompleted = true;
        _isRunning = false;
        _completedCompleter.completeError(error);
        _notifyWaiters();
      },
      onDone: () async {
        print('流式缓存完成: $cachePath, 总大小: ${_formatSize(_bytesWritten)}');
        _isCompleted = true;
        _isRunning = false;

        try {
          // 刷新并关闭文件
          await file.flush();
          await file.close();
        } catch (e) {
          print('关闭缓存文件失败: $e');
        }

        _completedCompleter.complete();
        _notifyWaiters();
      },
      cancelOnError: true,
    );
  }

  /// 停止缓存任务
  Future<void> stop() async {
    if (!_isRunning) return;

    print('停止流式缓存: $cachePath');
    _isRunning = false;

    await _subscription?.cancel();
    _subscription = null;

    try {
      await file.flush();
      await file.close();
    } catch (e) {
      print('关闭文件失败: $e');
    }

    if (!_completedCompleter.isCompleted) {
      _completedCompleter.complete();
    }

    _notifyWaiters();
  }

  /// 等待指定字节数被缓存
  Future<void> waitForBytes(int minBytes) async {
    if (_bytesWritten >= minBytes || _isCompleted) {
      return;
    }

    if (_error != null) {
      throw _error!;
    }

    final completer = Completer<void>();
    _bytesWaiters.add(completer);

    // 定期检查
    Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (_bytesWritten >= minBytes || _isCompleted || _error != null) {
        timer.cancel();
        if (!completer.isCompleted) {
          if (_error != null) {
            completer.completeError(_error!);
          } else {
            completer.complete();
          }
        }
      }
    });

    return completer.future;
  }

  /// 通知所有等待者
  void _notifyWaiters() {
    for (final waiter in _bytesWaiters) {
      if (!waiter.isCompleted) {
        if (_error != null) {
          waiter.completeError(_error!);
        } else {
          waiter.complete();
        }
      }
    }
    _bytesWaiters.clear();
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)}KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)}MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)}GB';
  }
}
