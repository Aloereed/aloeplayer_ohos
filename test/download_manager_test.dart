import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aloeplayer/models/download_task.dart';
import 'package:aloeplayer/models/server_config.dart';
import 'package:aloeplayer/services/download_manager.dart';
import 'package:aloeplayer/services/file_service.dart';

class TestFile implements FileItem {
  @override String get name => 'movie.mp4';
  @override String get path => '/movie.mp4';
  @override int get size => 6;
  @override bool get isDirectory => false;
  @override DateTime? get modified => null;
}
class TestSource extends FileService {
  final List<int> offsets;
  TestSource(this.offsets);
  @override bool get isConnected => true;
  @override Future<bool> connect(ServerConfig config) async => true;
  @override Future<void> disconnect() async {}
  @override Future<FileItem?> getFile(String path) async => TestFile();
  @override Future<List<FileItem>> listFiles(String path) async => [TestFile()];
  @override Future<Stream<Uint8List>> getFileStream(String filePath, {int? start, int? end}) async {
    offsets.add(start ?? 0);
    return _stream(start ?? 0);
  }
  Stream<Uint8List> _stream(int start) async* {
    if (start == 0) {
      yield Uint8List.fromList([1, 2, 3]);
      throw const SocketException('connection interrupted');
    }
    yield Uint8List.fromList([4, 5, 6]);
  }
}
class SlowSource extends TestSource {
  bool canceled = false, disconnected = false;
  SlowSource() : super([]);
  @override Future<Stream<Uint8List>> getFileStream(String filePath, {int? start, int? end}) async {
    final controller = StreamController<Uint8List>(onCancel: () { canceled = true; });
    controller.add(Uint8List.fromList([1, 2, 3]));
    return controller.stream;
  }
  @override Future<void> disconnect() async { disconnected = true; }
}
Future<void> waitForStatus(DownloadManager manager, DownloadStatus status) async {
  if (manager.tasks.single.status == status) return;
  final ready = Completer<void>();
  void listener() { if (manager.tasks.single.status == status && !ready.isCompleted) ready.complete(); }
  manager.addListener(listener);
  try { await ready.future.timeout(const Duration(seconds: 5)); } finally { manager.removeListener(listener); }
}
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('interrupted download resumes exact byte offset and atomically enters library', () async {
    SharedPreferences.setMockInitialValues({});
    final directory = await Directory.systemTemp.createTemp('aloe-download-test-');
    final offsets = <int>[];
    final manager = DownloadManager.forTesting(directory: directory.path, openSource: (_) async => TestSource(offsets));
    try {
      final config = ServerConfig(id: 'server', name: 'NAS', type: ServerType.webdav, host: 'localhost', username: '', password: '', createdAt: DateTime(2026));
      await manager.add(config, TestFile());
      await waitForStatus(manager, DownloadStatus.failed);
      final task = manager.tasks.single;
      expect(await File(task.partialPath).readAsBytes(), [1, 2, 3]);
      expect(await File(task.destination).exists(), isFalse);
      await manager.resume(task);
      await waitForStatus(manager, DownloadStatus.completed);
      expect(offsets, [0, 3]);
      expect(await File(task.destination).readAsBytes(), [1, 2, 3, 4, 5, 6]);
      expect(await File(task.partialPath).exists(), isFalse);
    } finally {
      manager.dispose();
      await directory.delete(recursive: true);
    }
  });
  for (final cancel in [false, true]) {
    test('${cancel ? "cancel" : "pause"} waits for stream cancellation and releases connection', () async {
      SharedPreferences.setMockInitialValues({});
      final directory = await Directory.systemTemp.createTemp('aloe-download-stop-');
      final source = SlowSource();
      final manager = DownloadManager.forTesting(directory: directory.path, openSource: (_) async => source);
      try {
        final config = ServerConfig(id: 'server', name: 'NAS', type: ServerType.webdav, host: 'localhost', username: '', password: '', createdAt: DateTime(2026));
        await manager.add(config, TestFile());
        final task = manager.tasks.single;
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (task.received < 3 && DateTime.now().isBefore(deadline)) { await Future<void>.delayed(const Duration(milliseconds: 10)); }
        expect(task.received, 3);
        if (cancel) { await manager.cancel(task); } else { await manager.pause(task); }
        expect(source.canceled, isTrue);
        expect(source.disconnected, isTrue);
        expect(task.status, cancel ? DownloadStatus.canceled : DownloadStatus.paused);
        expect(await File(task.destination).exists(), isFalse);
        expect(await File(task.partialPath).exists(), !cancel);
        if (!cancel) expect(await File(task.partialPath).readAsBytes(), [1, 2, 3]);
      } finally { manager.dispose(); await directory.delete(recursive: true); }
    });
  }

}
