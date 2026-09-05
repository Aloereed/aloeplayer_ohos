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
}
