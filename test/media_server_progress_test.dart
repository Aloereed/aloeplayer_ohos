import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aloeplayer/models/playback_media.dart';
import 'package:aloeplayer/services/media_server_client.dart';
import 'package:aloeplayer/services/media_server_progress.dart';

void main() {
  test(
      'offline outbox persists failures, isolates accounts and retains newer in-flight checkpoints',
      () async {
    SharedPreferences.setMockInitialValues({});
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    var fail = true, posts = 0;
    Completer<void>? arrived, release;
    DateTime? lastPlayed;
    server.listen((request) async {
      request.response.headers.contentType = ContentType.json;
      if (request.method == 'GET') {
        request.response.write(jsonEncode({
          'Id': 'movie',
          'Type': 'Movie',
          'RunTimeTicks': 100000000,
          'UserData': {
            if (lastPlayed != null)
              'LastPlayedDate': lastPlayed.toIso8601String()
          }
        }));
      } else {
        posts++;
        await request.drain<void>();
        arrived?.complete();
        if (release != null) await release.future;
        request.response.statusCode = fail ? 503 : 200;
        request.response.write('{}');
      }
      await request.response.close();
    });
    MediaServerConnection connection(String user) => MediaServerConnection(
        id: 'server',
        name: 'Fixture',
        url: 'http://127.0.0.1:${server.port}/prefix',
        userId: user,
        username: user,
        token: 'never-persist-this-token',
        kind: 'Jellyfin');
    final client = MediaServerClient(connection('one'));
    final other = MediaServerClient(connection('two'));
    const media = PlaybackMedia(
        id: 'aloe-server://server/movie',
        url: '/offline/movie.mkv',
        title: 'Movie');
    final date = DateTime.now().toUtc();
    try {
      final store = MediaServerProgressStore();
      await store.record(client.connection, media, 2000, observed: date);
      expect((await store.sync(client)).pending, 1);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(MediaServerProgressStore.storageKey),
          isNot(contains('never-persist')));
      expect(prefs.getString(MediaServerProgressStore.storageKey),
          isNot(contains('127.0.0.1')));
      final reopened = MediaServerProgressStore();
      expect((await reopened.sync(other)).pending, 0);
      expect(posts, 1);
      fail = false;
      arrived = Completer<void>();
      release = Completer<void>();
      final pending = reopened.sync(client);
      await arrived.future.timeout(const Duration(seconds: 5));
      await reopened.record(client.connection, media, 6000,
          observed: date.add(const Duration(seconds: 1)));
      release.complete();
      expect((await pending).pending, 1);
      arrived = null;
      release = null;
      final sent = await reopened.sync(client);
      expect(sent.sent, 1);
      expect(sent.pending, 0);
      await reopened.record(client.connection, media, 3000, observed: date);
      lastPlayed = date.add(const Duration(minutes: 1));
      final previousPosts = posts;
      final conflict = await reopened.sync(client);
      expect(conflict.superseded, 1);
      expect(conflict.pending, 0);
      expect(posts, previousPosts);
      await reopened.record(client.connection, media, 5000,
          observed: date.add(const Duration(seconds: 10)));
      await reopened.acknowledge(client.connection, media, date);
      expect(jsonDecode(prefs.getString(MediaServerProgressStore.storageKey)!),
          hasLength(1));
      await reopened.acknowledge(
          client.connection, media, date.add(const Duration(seconds: 10)));
      await reopened.record(client.connection, media, 0);
      expect(jsonDecode(prefs.getString(MediaServerProgressStore.storageKey)!),
          isEmpty);
    } finally {
      await client.close();
      await other.close();
      await server.close(force: true);
    }
  });
}
