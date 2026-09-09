import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aloeplayer/services/media_server_client.dart';
import 'package:aloeplayer/services/media_server_download.dart';
import 'package:aloeplayer/services/download_manager.dart';
import 'package:aloeplayer/models/download_task.dart';

void main() {
  test(
      'original download validates range/revision and falls back when HEAD is unsupported',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var mode = 'correct';
    var headSupported = true;
    var downloadsAllowed = true;
    var playbackInfoRequests = 0;
    final conditionals = <String?>[];
    final body = [1, 2, 3, 4, 5, 6];
    server.listen((request) async {
      await request.drain<void>();
      expect(request.headers.value('X-Emby-Token'), 'fixture-token');
      expect(request.uri.queryParameters.containsKey('api_key'), isFalse);
      final response = request.response;
      if (request.uri.path.endsWith('/PlaybackInfo')) {
        playbackInfoRequests++;
        response.headers.contentType = ContentType.json;
        response.write(jsonEncode({
          'MediaSources': [
            {'Id': 'version', 'Container': 'mkv'}
          ]
        }));
      } else if (request.uri.path.endsWith('/Users/u')) {
        response.headers.contentType = ContentType.json;
        response.write(jsonEncode({
          'Policy': {'EnableContentDownloading': downloadsAllowed}
        }));
      } else if (request.uri.path.endsWith('/Items/item')) {
        response.headers.contentType = ContentType.json;
        response.write(
            jsonEncode({'Id': 'item', 'Name': 'Movie', 'Type': 'Movie'}));
      } else {
        response.headers.contentType = ContentType('video', 'x-matroska');
        response.headers.set('etag', mode == 'changed' ? '"v2"' : '"v1"');
        if (request.method == 'HEAD') {
          response.statusCode = headSupported ? 200 : 405;
          response.contentLength = headSupported ? 6 : 0;
        } else {
          conditionals.add(request.headers.value('if-range') ??
              request.headers.value('if-match'));
          final range = RegExp(r'^bytes=(\d+)-(\d+)$')
              .firstMatch(request.headers.value('range') ?? '');
          final start =
              range == null || mode == 'ignore' ? 0 : int.parse(range[1]!);
          final end =
              range == null || mode == 'ignore' ? 5 : int.parse(range[2]!);
          if (range != null && mode != 'ignore') {
            response.statusCode = 206;
            response.headers.set('content-range',
                'bytes ${mode == 'bad-range' ? 0 : start}-$end/6');
          }
          response.contentLength = end - start + 1;
          response.add(body.sublist(start, end + 1));
        }
      }
      await response.close();
    });
    final connection = MediaServerConnection(
        id: 'device',
        name: 'Test',
        url: 'http://127.0.0.1:${server.port}/proxy',
        userId: 'u',
        username: 'u',
        token: 'fixture-token',
        kind: 'Jellyfin');
    final source = MediaServerDownloadSource(connection);
    const item = MediaServerItem(id: 'item', name: 'Movie', type: 'Movie');
    final directory =
        await Directory.systemTemp.createTemp('aloe-server-download-');
    try {
      var file = await source.prepare(item);
      final beforeDenied = playbackInfoRequests;
      downloadsAllowed = false;
      await expectLater(source.prepare(item), throwsStateError);
      expect(playbackInfoRequests, beforeDenied);
      downloadsAllowed = true;
      expect(
          await (await source.getFileStreamForRevision(file))
              .expand((bytes) => bytes)
              .toList(),
          body);
      expect(conditionals.last, '"v1"');
      expect(
          await (await source.getFileStreamForRevision(file, start: 3))
              .expand((bytes) => bytes)
              .toList(),
          [4, 5, 6]);
      for (final failure in ['ignore', 'bad-range', 'changed']) {
        mode = failure;
        await expectLater(
            source.getFileStreamForRevision(file, start: 3), throwsStateError);
      }
      mode = 'correct';
      headSupported = false;
      file = await source.prepare(item);
      expect(file.size, 6);
      expect(file.etag, '"v1"');
      expect((await source.getFile(file.path))?.path, file.path);
      SharedPreferences.setMockInitialValues({});
      final manager = DownloadManager.forTesting(
          directory: directory.path,
          openSource: (id) async {
            expect(id, 'media-server:device');
            return MediaServerDownloadSource(connection);
          });
      await manager.addMediaServer(connection.id, file);
      final task = manager.tasks.single;
      final deadline = DateTime.now().add(const Duration(seconds: 5));
      while (task.status != DownloadStatus.completed &&
          task.status != DownloadStatus.failed &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      expect(task.status, DownloadStatus.completed, reason: task.error);
      expect(await File(task.destination).readAsBytes(), body);
      final offline = await manager.offlineMedia('aloe-server://device/item');
      expect(offline?.url, task.destination);
      expect(offline?.id, 'aloe-server://device/item');
      expect(await manager.offlineMedia('aloe-server://other-device/item'),
          isNull);
      expect(await manager.offlineMedia('aloe-server://device/other-item'),
          isNull);
      await File(task.destination).writeAsBytes([1, 2]);
      expect(await manager.offlineMedia('aloe-server://device/item'), isNull);
      final persisted = (await SharedPreferences.getInstance())
          .getString('download.tasks.v1')!;
      expect(persisted, isNot(contains('fixture-token')));
      expect(persisted, isNot(contains('127.0.0.1')));
      expect(persisted, contains('media-server:device'));
    } finally {
      await source.disconnect();
      await server.close(force: true);
      await directory.delete(recursive: true);
    }
  });
}
