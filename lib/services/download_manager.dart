import 'member_access.dart';
import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';
import '../models/download_task.dart';
import '../models/server_config.dart';
import 'file_service.dart';
import 'server_config_service.dart';

String downloadBackgroundFailure(Object error) {
  if (error is TimeoutException) return '后台下载服务响应超时，请保持应用在前台；中断后可继续';
  if (error is PlatformException) {
    if (error.details == 1600004) return '通知权限未开启，请在系统设置中允许通知后重试；目前可前台下载';
    final code = error.details is num ? '${error.details}' : error.code;
    return '后台下载申请失败（$code），请保持应用在前台；中断后可继续';
  }
  return '后台下载服务暂不可用，请保持应用在前台；中断后可继续';
}

class DownloadManager extends ChangeNotifier {
  static final instance = DownloadManager._();
  static const _device = MethodChannel('aloeplayer/device-tools');
  String? backgroundNotice;
  final MemberAccess access;
  DownloadManager._() : access = MemberAccess.instance;
  @visibleForTesting
  DownloadManager.forTesting({required String directory, required Future<FileService> Function(String serverId) openSource, MemberAccess? access}) : access = access ?? MemberAccess.instance {
    _directoryOverride = directory;
    _openSourceOverride = openSource;
  }
  String? _directoryOverride;
  Future<FileService> Function(String serverId)? _openSourceOverride;
  Completer<void>? _activeDone;
  final List<DownloadTask> tasks = [];
  Future<void>? _initializing;
  bool _running = false;
  bool _updatingBackground = false;
  DateTime _lastBackgroundProgress = DateTime.fromMillisecondsSinceEpoch(0);
  StreamIterator<Uint8List>? _iterator;
  String? _activeId;
  Future<void> _writes = Future.value();
  Future<void> initialize() => _initializing ??= _load();
  Future<void> _load() async {
    if (Platform.operatingSystem == 'ohos') {
      _device.setMethodCallHandler((call) async {
        if (call.method == 'downloadBackgroundCanceled') {
          backgroundNotice = '系统已结束后台下载任务，下载已暂停，可返回后继续';
          final active = tasks.where((t) => t.id == _activeId).firstOrNull;
          for (final task in tasks.where((t) => t.status == DownloadStatus.queued)) { task.status = DownloadStatus.paused; }
          if (active != null) await pause(active);
          else await _persist();
          notifyListeners();
        }
      });
    }
    final raw = (await SharedPreferences.getInstance()).getString('download.tasks.v1');
    if (raw != null) {
      tasks.addAll((jsonDecode(raw) as List).map((e) => DownloadTask.fromJson(e as Map<String, dynamic>)));
    }
    notifyListeners();
  }
  Future<void> _persist() {
    final snapshot = jsonEncode(tasks.map((t) => t.toJson()).toList());
    _writes = _writes.catchError((_) {}).then((_) async {
      await (await SharedPreferences.getInstance()).setString('download.tasks.v1', snapshot);
    });
    return _writes;
  }
  /// Once accepted, tasks can finish or resume even after membership expires.
  Future<({int added, int skipped, int failed})> addBatch(ServerConfig config, List<FileItem> files) async {
    await access.require(MemberFeature.batchDownload);
    if (files.isEmpty || files.length > 100 || files.any((f) => f.isDirectory || f.size < 0)) {
      throw ArgumentError('每批请选择 1 至 100 个已知大小的文件');
    }
    await initialize();
    var added = 0, skipped = 0, failed = 0;
    final paths = <String>{};
    for (final file in files) {
      if (!paths.add(file.path) || tasks.any((t) => t.serverId == config.id && t.remotePath == file.path && t.status != DownloadStatus.canceled)) {
        skipped++;
        continue;
      }
      try { await add(config, file); added++; } catch (_) { failed++; }
    }
    return (added: added, skipped: skipped, failed: failed);
  }

  Future<void> add(ServerConfig config, FileItem file) async {
    await initialize();
    if (tasks.any((t) => t.serverId == config.id && t.remotePath == file.path && t.status != DownloadStatus.canceled && t.status != DownloadStatus.completed)) {
      throw StateError('该文件已在下载列表中');
    }
    if (file.isDirectory || file.size < 0) throw StateError('无法下载目录或未知大小的文件');
    final id = const Uuid().v4();
    final audio = {'.mp3', '.flac', '.m4a', '.wav', '.ogg', '.aac', '.opus'}.contains(path.extension(file.name).toLowerCase());
    final directory = Directory(_directoryOverride ?? '/storage/Users/currentUser/Download/com.aloereed.aloeplayer/${audio ? 'Audios' : 'Videos'}/Downloads');
    await directory.create(recursive: true);
    var safeName = path.basename(file.name).replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
    if (safeName.isEmpty || safeName == '.' || safeName == '..') safeName = 'download-$id';
    var destination = path.join(directory.path, safeName);
    if (await File(destination).exists() || tasks.any((t) => t.destination == destination)) {
      destination = path.join(directory.path, '${path.basenameWithoutExtension(safeName)}-${id.substring(0, 8)}${path.extension(safeName)}');
    }
    if (tasks.any((t) => t.serverId == config.id && t.remotePath == file.path && t.status != DownloadStatus.canceled && t.status != DownloadStatus.completed)) {
      throw StateError('该文件已在下载列表中');
    }
    tasks.add(DownloadTask(id: id, serverId: config.id, remotePath: file.path, name: file.name, destination: destination,
      size: file.size, modifiedMs: file.modified?.millisecondsSinceEpoch));
    await _persist();
    notifyListeners();
    unawaited(_pump());
  }
  Future<void> pause(DownloadTask task) async {
    task.status = DownloadStatus.paused;
    if (_activeId == task.id) { final done = _activeDone?.future; await _iterator?.cancel(); await done; }
    await _persist();
    notifyListeners();
  }
  Future<void> resume(DownloadTask task) async {
    if (_activeId == task.id) return;
    task.status = DownloadStatus.queued;
    task.error = null;
    await _persist();
    notifyListeners();
    unawaited(_pump());
  }
  Future<void> cancel(DownloadTask task) async {
    task.status = DownloadStatus.canceled;
    if (_activeId == task.id) {
      final done = _activeDone?.future;
      await _iterator?.cancel();
      await done;
    } else {
      final part = File(task.partialPath);
      if (await part.exists()) await part.delete();
    }
    await _persist();
    notifyListeners();
  }
  Future<void> removeFinished() async {
    await initialize();
    tasks.removeWhere((task) => task.status == DownloadStatus.completed || task.status == DownloadStatus.canceled);
    await _persist();
    notifyListeners();
  }
  Future<void> _pump() async {
    if (_running) return;
    _running = true;
    try {
      if (Platform.operatingSystem == 'ohos') {
        try {
          // User interaction must not be cut off by the service startup timeout.
          await _device.invokeMethod<void>('requestDownloadNotificationPermission');
          final started = await _device.invokeMethod<bool>('startDownloadBackground').timeout(const Duration(seconds: 10));
          if (started != true) throw StateError('Background task did not start');
          backgroundNotice = null;
        } catch (error) { backgroundNotice = downloadBackgroundFailure(error); }
        notifyListeners();
      }
      while (true) {
        final next = tasks.where((t) => t.status == DownloadStatus.queued).firstOrNull;
        if (next == null) break;
        _activeId = next.id;
        final done = Completer<void>();
        _activeDone = done;
        try { await _download(next); }
        catch (error) {
          next.status = DownloadStatus.failed;
          next.error = '下载任务保存或清理失败: $error';
          try { await _persist(); } catch (_) {}
        } finally { _activeId = null; done.complete(); _activeDone = null; }
      }
    } finally {
      if (Platform.operatingSystem == 'ohos') {
        try { await _device.invokeMethod<void>('stopDownloadBackground').timeout(const Duration(seconds: 10)); } catch (_) {}
      }
      _running = false; _activeId = null; notifyListeners();
      // A new job may have been added while the native background task stopped.
      if (tasks.any((t) => t.status == DownloadStatus.queued)) unawaited(_pump());
    }
  }
  Future<void> _updateBackgroundProgress(DownloadTask task) async {
    if (Platform.operatingSystem != 'ohos' || _updatingBackground ||
        DateTime.now().difference(_lastBackgroundProgress).inSeconds < 3) return;
    _updatingBackground = true;
    _lastBackgroundProgress = DateTime.now();
    try {
      await _device.invokeMethod<void>('updateDownloadBackground', {
        'name': task.name, 'progress': task.size > 0 ? (task.received * 100 ~/ task.size) : 0,
      }).timeout(const Duration(seconds: 5));
    } catch (error) {
      if (_activeId == task.id) {
        backgroundNotice = '下载通知更新失败，请保持前台下载；系统可能暂停后台任务';
        notifyListeners();
      }
    } finally { _updatingBackground = false; }
  }
  Future<void> _download(DownloadTask task) async {
    FileService? files;
    RandomAccessFile? writer;
    final part = File(task.partialPath);
    task.status = DownloadStatus.downloading;
    try {
      await _persist();
      notifyListeners();
      if (_openSourceOverride != null) {
        files = await _openSourceOverride!(task.serverId);
      } else {
        final config = await ServerConfigService().getConfig(task.serverId);
        if (config == null) throw StateError('服务器配置已删除');
        files = FileServiceFactory.createService(config.type);
        if (!await files.connect(config)) throw StateError('无法连接服务器');
      }
      final source = await files.getFile(task.remotePath);
      if (source == null || source.size != task.size || (task.modifiedMs != null && source.modified?.millisecondsSinceEpoch != task.modifiedMs)) {
        throw StateError('远端文件已变化，请取消任务后重新下载');
      }
      task.received = await part.exists() ? await part.length() : 0;
      _lastBackgroundProgress = DateTime.fromMillisecondsSinceEpoch(0);
      unawaited(_updateBackgroundProgress(task));
      if (task.received > task.size) throw StateError('临时文件大小不符');
      if (Platform.operatingSystem == 'ohos') {
        final free = await const MethodChannel('aloeplayer/device-tools').invokeMethod<int>('freeBytes');
        if (free != null && free < task.size - task.received + 32 * 1024 * 1024) throw StateError('存储空间不足');
      }
      if (task.status != DownloadStatus.downloading) return;
      writer = await part.open(mode: FileMode.append);
      if (task.received < task.size) {
        final stream = await files.getFileStream(task.remotePath, start: task.received == 0 ? null : task.received);
        final iterator = StreamIterator(stream);
        _iterator = iterator;
        var checkpoint = DateTime.now();
        var lastNotification = DateTime.now();
        while (task.status == DownloadStatus.downloading && await iterator.moveNext()) {
          if (task.status != DownloadStatus.downloading) break;
          if (task.received + iterator.current.length > task.size) throw StateError('服务器返回的文件大小不符');
          await writer.writeFrom(iterator.current);
          task.received += iterator.current.length;
          if (DateTime.now().difference(lastNotification).inMilliseconds >= 500) {
            lastNotification = DateTime.now();
            notifyListeners();
            unawaited(_updateBackgroundProgress(task));
            if (DateTime.now().difference(checkpoint).inSeconds >= 2) { await _persist(); checkpoint = DateTime.now(); }
          }
        }
      }
      await writer.flush();
      await writer.close();
      writer = null;
      if (task.status == DownloadStatus.downloading) {
        if (task.received != task.size) throw StateError('连接提前结束，可重试继续下载');
        if (await File(task.destination).exists()) throw StateError('目标文件已存在，请另存');
        await part.rename(task.destination);
        task.status = DownloadStatus.completed;
      }
    } catch (e) {
      if (task.status == DownloadStatus.downloading) { task.status = DownloadStatus.failed; task.error = e.toString(); }
    } finally {
      try { await _iterator?.cancel(); } catch (_) {}
      _iterator = null;
      try { await writer?.close(); } catch (_) {}
      try { await files?.disconnect(); } catch (_) {}
      if (task.status == DownloadStatus.canceled && await part.exists()) await part.delete();
      await _persist();
      notifyListeners();
    }
  }
}
