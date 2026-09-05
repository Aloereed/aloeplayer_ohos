import 'package:flutter_test/flutter_test.dart';
import 'package:aloeplayer/models/download_task.dart';
void main() {
  test('interrupted downloads restore paused and retain their partial identity', () {
    final task = DownloadTask(id: 'job1', serverId: 'nas', remotePath: '/movie.mkv', name: 'movie.mkv', destination: '/library/movie.mkv', size: 1000, received: 123, status: DownloadStatus.downloading);
    final restored = DownloadTask.fromJson(task.toJson());
    expect(restored.status, DownloadStatus.paused);
    expect(restored.received, 123);
    expect(restored.partialPath, task.partialPath);
    expect(restored.toJson().containsKey('password'), isFalse);
  });
}
