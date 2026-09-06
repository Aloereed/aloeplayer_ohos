import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aloeplayer/services/member_access.dart';
import 'package:aloeplayer/services/download_manager.dart';
import 'package:aloeplayer/models/download_task.dart';
import 'package:aloeplayer/models/server_config.dart';
import 'download_manager_test.dart' show TestFile, TestSource, waitForStatus;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('batch is gated, deduplicates selections and accepted downloads resume after expiry', () async {
    SharedPreferences.setMockInitialValues({});
    var clock = DateTime.utc(2026, 9, 6);
    final access = MemberAccess(now: () => clock, paid: () => false);
    final directory = await Directory.systemTemp.createTemp('aloe-member-batch-');
    final manager = DownloadManager.forTesting(directory: directory.path,
      openSource: (_) async => TestSource([]), access: access);
    final config = ServerConfig(id: 'server', name: 'NAS', type: ServerType.webdav,
      host: 'localhost', username: '', password: '', createdAt: DateTime(2026));
    try {
      await expectLater(manager.addBatch(config, [TestFile()]), throwsA(isA<MemberAccessRequired>()));
      expect(manager.tasks, isEmpty);
      await access.startTrial();
      final result = await manager.addBatch(config, [TestFile(), TestFile()]);
      expect(result, (added: 1, skipped: 1, failed: 0));
      await waitForStatus(manager, DownloadStatus.failed);
      clock = clock.add(const Duration(days: 8));
      await expectLater(manager.addBatch(config, [TestFile()]), throwsA(isA<MemberAccessRequired>()));
      await manager.resume(manager.tasks.single);
      await waitForStatus(manager, DownloadStatus.completed);
      final file = File(manager.tasks.single.destination);
      expect(await file.readAsBytes(), [1, 2, 3, 4, 5, 6]);
      await manager.removeFinished();
      expect(await file.exists(), isTrue);
    } finally { manager.dispose(); await directory.delete(recursive: true); }
  });
}
