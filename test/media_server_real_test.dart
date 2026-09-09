import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:aloeplayer/services/media_server_client.dart';
import 'package:aloeplayer/services/media_server_catalog.dart';
import 'package:aloeplayer/services/media_server_playback.dart';
import 'package:aloeplayer/services/media_server_download.dart';
import 'package:crypto/crypto.dart';
import 'package:aloeplayer/services/media_server_query.dart';
import 'package:aloeplayer/services/media_server_sequence.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aloeplayer/services/media_server_progress.dart';
import 'package:aloeplayer/models/playback_media.dart';
import 'package:aloeplayer/services/media_server_diagnostics.dart';

void main() {
  for (final kind in ['Jellyfin', 'Emby']) {
    test(
        'real $kind: login, versions, tracks, subtitles, decode, watched and resume',
        () async {
      final fixture = Directory('build/media-server-fixtures').absolute;
      final auth = jsonDecode(await File(
              '${fixture.path}/${kind == 'Jellyfin' ? 'jellyfin-12-runtime' : 'emby-4.10-runtime'}/test-auth.json')
          .readAsString()) as Map;
      final uri = Uri.parse(auth['url'] as String);
      expect(uri.host, '127.0.0.1');
      expect(uri.scheme, 'http');
      final connection = await MediaServerClient.login(
          url: uri.toString(),
          username: auth['username'] as String,
          password: auth['password'] as String,
          kind: kind);
      final client = MediaServerClient(connection);
      final ffmpeg = '${fixture.path}/jellyfin-12-bin/jellyfin/ffmpeg.exe';
      final reader = HttpClient();
      Future<String> decode(String input, {int audio = 0}) async {
        final result = await Process.run(ffmpeg, [
          '-hide_banner',
          '-loglevel',
          'error',
          '-nostdin',
          '-ss',
          '5',
          '-i',
          input,
          '-t',
          '3',
          '-map',
          '0:v:0',
          '-map',
          '0:a:$audio',
          '-c:v',
          'rawvideo',
          '-c:a',
          'pcm_s16le',
          '-f',
          'streamhash',
          '-hash',
          'sha256',
          '-'
        ]);
        expect(result.exitCode, 0,
            reason: 'Media decode failed: ${result.stderr}');
        final output = (result.stdout as String).trim();
        expect(output.split('\n'), hasLength(2));
        return output;
      }

      try {
        final diagnostics =
            await MediaServerDiagnostics(client).run(CancelToken()).toList();
        expect(diagnostics, hasLength(4));
        expect(
            diagnostics
                .where((r) => r.status == MediaServerDiagnosticStatus.failed),
            isEmpty);
        final diagnosticSummary =
            mediaServerDiagnosticSummary(kind, diagnostics);
        expect(diagnosticSummary, contains(auth['version']));
        expect(diagnosticSummary, isNot(contains(connection.token)));
        expect(diagnosticSummary, isNot(contains(connection.url)));
        final libraries = await client.shelf(MediaServerShelf.libraries);
        expect(libraries.items, hasLength(3));
        final music = libraries.items
            .firstWhere((item) => item.name == 'Aloe Fixture Music');
        final tracks = await client.itemPage(
            parent: music.id,
            query: const MediaServerQuery(
                type: MediaServerTypeFilter.audio,
                sort: MediaServerSort.track));
        expect(tracks.items.map((item) => item.name),
            ['Zebra', 'Alpha', 'Middle']);
        final firstTrack = await client.details(tracks.items.first.id);
        expect(firstTrack.albumId, isNotEmpty);
        final album = await client.details(firstTrack.albumId!);
        expect(album.type, 'MusicAlbum');
        final albumTracks = await client.itemPage(
            parent: album.id,
            query: const MediaServerQuery().forParent(album.type));
        expect(albumTracks.items.map((item) => item.name),
            ['Zebra', 'Alpha', 'Middle']);
        expect((await client.adjacentTrack(firstTrack, forward: true))?.name,
            'Alpha');
        expect(await client.adjacentTrack(firstTrack, forward: false), isNull);
        expect(
            (await client.adjacentTrack(tracks.items.last, forward: false))
                ?.name,
            'Alpha');
        expect(await client.adjacentTrack(tracks.items.last, forward: true),
            isNull);
        final song = await client.playback(firstTrack,
            options: const MediaServerPlaybackOptions(
                mode: MediaServerPlayMode.original));
        expect(song.mediaType, 'audio');
        Future<String> audioHash(String input) async {
          final result = await Process.run(ffmpeg, [
            '-hide_banner',
            '-loglevel',
            'error',
            '-nostdin',
            '-ss',
            '3',
            '-i',
            input,
            '-t',
            '3',
            '-map',
            '0:a:0',
            '-c:a',
            'pcm_s16le',
            '-f',
            'streamhash',
            '-hash',
            'sha256',
            '-'
          ]);
          expect(result.exitCode, 0, reason: '${result.stderr}');
          return (result.stdout as String).trim();
        }

        expect(
            await audioHash(song.url),
            await audioHash(
                '${fixture.path}/library/Music/Aloe Artist/Aloe Album/1-01 Zebra.flac'));
        final musicSequence = MediaServerSequence(
            client: client,
            cancelToken: CancelToken(),
            item: firstTrack,
            media: song);
        expect(musicSequence.enabled, isTrue);
        final secondSong = (await musicSequence.adjacent(song, true))!;
        expect(secondSong.title, 'Alpha');
        final thirdSong = (await musicSequence.adjacent(secondSong, true))!;
        expect(thirdSong.title, 'Middle');
        expect(await musicSequence.adjacent(thirdSong, true), isNull);
        await client.discardPlayback(song);
        await client.discardPlayback(secondSong);
        await client.discardPlayback(thirdSong);
        final movies = libraries.items
            .firstWhere((item) => item.name == 'Aloe Fixture Movies');
        final page = await client.itemPage(parent: movies.id, limit: 1);
        expect(page.items, hasLength(1));
        expect(page.hasMore, isFalse);
        var movieEntry = page.items.single;
        // Emby may expose the physical movie directory before the movie itself.
        // Exercise folder traversal rather than requiring Jellyfin's flat layout.
        for (var depth = 0; movieEntry.isFolder && depth < 5; depth++) {
          final children = await client.itemPage(parent: movieEntry.id);
          expect(children.items, isNotEmpty);
          movieEntry = children.items.first;
        }
        expect(movieEntry.type, 'Movie');
        final movie = await client.details(movieEntry.id);
        final sources = await client.playbackSources(movie);
        expect(sources, hasLength(2));
        final source = sources.firstWhere(
            (s) => s.streams.where((t) => t.type == 'Audio').length == 2);
        final audio = source.streams.where((t) => t.type == 'Audio').last;
        final subtitle = source.streams.firstWhere((t) =>
            t.type == 'Subtitle' && ['zho', 'zh'].contains(t.data['Language']));
        final direct = await client.playback(movie,
            options: MediaServerPlaybackOptions(
                sourceId: source.id,
                audioIndex: audio.index,
                subtitleIndex: subtitle.index,
                mode: MediaServerPlayMode.original));
        expect(direct.preferredAudioTrack, '2');
        expect(direct.subtitles, hasLength(1));
        final subResponse =
            await (await reader.getUrl(Uri.parse(direct.subtitles.single)))
                .close();
        expect(subResponse.statusCode, 200);
        expect(await utf8.decoder.bind(subResponse).join(), contains('中文字幕测试'));
        final original =
            await File(source.data['Path'] as String).resolveSymbolicLinks();
        expect(path.isWithin('${fixture.path}/library', original), isTrue);
        final download = MediaServerDownloadSource(connection);
        try {
          final userRoute = 'Users/${Uri.encodeComponent(connection.userId)}';
          final user = await client.dio.get<Map<String, dynamic>>(userRoute);
          final policy = Map<String, dynamic>.from(user.data!['Policy'] as Map);
          try {
            await client.dio.post('$userRoute/Policy',
                data: {...policy, 'EnableContentDownloading': false});
            await expectLater(
                download.prepare(movie, sourceId: source.id), throwsStateError);
          } finally {
            await client.dio.post('$userRoute/Policy', data: policy);
          }
          final file = await download.prepare(movie, sourceId: source.id);
          final subtitleDirectory =
              await Directory.systemTemp.createTemp('aloe-real-subtitle-');
          try {
            final saved = await download
                .saveSubtitles('${subtitleDirectory.path}/movie.mkv');
            expect(saved.error, isNull);
            expect(saved.files, hasLength(2));
            final texts = await Future.wait(
                saved.files.keys.map((name) => File(name).readAsString()));
            expect(texts.any((text) => text.contains('中文字幕测试')), isTrue);
            expect(
                texts.any((text) => text.contains('English fixture subtitle')),
                isTrue);
            final retried = await download.saveSubtitles(
                '${subtitleDirectory.path}/movie.mkv',
                existing: saved.files);
            expect(retried.files.keys.toSet(), saved.files.keys.toSet());
          } finally {
            await subtitleDirectory.delete(recursive: true);
          }
          expect(file.size, await File(original).length());
          final full = await download.getFileStreamForRevision(file);
          expect((await sha256.bind(full).first).toString(),
              (await sha256.bind(File(original).openRead()).first).toString());
          final resumedDownload =
              await download.getFileStreamForRevision(file, start: 4096);
          expect(
              (await sha256.bind(resumedDownload).first).toString(),
              (await sha256.bind(File(original).openRead(4096)).first)
                  .toString());
        } finally {
          await download.disconnect();
        }
        final expected = await decode(original, audio: 1);
        final actual = await decode(direct.url, audio: 1);
        expect(actual, expected);
        await client.report(direct, 6000, false, true);
        await client.report(direct, 7000, true, false);
        final resumed = await client.details(movie.id);
        expect(resumed.resumeMs, 7000);
        expect(
            (await client.shelf(MediaServerShelf.resume))
                .items
                .any((m) => m.id == movie.id),
            isTrue);
        await client.setFavorite(movie.id, true);
        expect(
            (await client.shelf(MediaServerShelf.favorites))
                .items
                .any((m) => m.id == movie.id),
            isTrue);
        await client.setFavorite(movie.id, false);
        await client.setPlayed(movie.id, true);
        expect(
            (await client.itemPage(
                    parent: movies.id,
                    query: const MediaServerQuery(
                        type: MediaServerTypeFilter.movies,
                        watched: MediaServerWatchFilter.unwatched)))
                .items,
            isEmpty);
        expect(
            (await client.itemPage(
                    parent: movies.id,
                    query: const MediaServerQuery(
                        type: MediaServerTypeFilter.movies,
                        watched: MediaServerWatchFilter.watched)))
                .items
                .single
                .id,
            movie.id);
        await client.setPlayed(movie.id, false);
        final transcoded = await client.playback(movie,
            options: MediaServerPlaybackOptions(
                sourceId: source.id,
                audioIndex: audio.index,
                subtitleIndex: -1,
                maxBitrate: 2000000,
                mode: MediaServerPlayMode.transcode));
        expect(transcoded.preferredSubtitleTrack, 'no');
        await decode(transcoded.url);
        await client.report(transcoded, 8000, true, false);
        final shows = libraries.items
            .firstWhere((item) => item.name == 'Aloe Fixture Shows');
        final series = (await client.itemPage(parent: shows.id))
            .items
            .firstWhere((m) => m.type == 'Series');
        for (final sort in MediaServerSort.values) {
          final sorted = await client.itemPage(
              parent: shows.id,
              query: MediaServerQuery(
                  type: MediaServerTypeFilter.episodes, sort: sort));
          expect(sorted.items, hasLength(3));
        }
        final seasons = await client.seasons(series.id);
        expect(seasons.items, hasLength(1));
        final episodes = await client.episodes(series.id,
            seasonId: seasons.items.single.id, limit: 2);
        expect(episodes.items, hasLength(2));
        expect(episodes.hasMore, isTrue);
        final last = await client.episodes(series.id,
            seasonId: seasons.items.single.id, start: 2, limit: 2);
        expect(last.items, hasLength(1));
        expect(last.hasMore, isFalse);
        expect(
            (await client.adjacentEpisode(episodes.items.first, forward: true))
                ?.id,
            episodes.items[1].id);
        expect(
            await client.adjacentEpisode(episodes.items.first, forward: false),
            isNull);
        expect(
            (await client.adjacentEpisode(last.items.single, forward: false))
                ?.id,
            episodes.items[1].id);
        expect(await client.adjacentEpisode(last.items.single, forward: true),
            isNull);
        await client.setPlayed(episodes.items.first.id, true);
        expect((await client.details(episodes.items.first.id)).played, isTrue);
        // Emby's NextUp also needs actual playback history (LastPlayedDate),
        // which its manual watched toggle intentionally does not create.
        final episodePlayback = await client.playback(episodes.items.first);
        await client.report(episodePlayback, 0, false, true);
        await client.report(episodePlayback, 23500, true, false);
        expect(
            (await client.shelf(MediaServerShelf.nextUp))
                .items
                .any((m) => m.id == episodes.items[1].id),
            isTrue);
        await client.setPlayed(episodes.items.first.id, false);
        await client.setFavorite(movie.id, true);
        final offlineDate = DateTime.now().toUtc();
        expect(
            await client.syncOfflineProgress(movie.id, 9000, offlineDate,
                actionId: 'offline-${offlineDate.microsecondsSinceEpoch}'),
            isTrue);
        final afterOffline = await client.details(movie.id);
        expect(afterOffline.resumeMs, 9000);
        expect(afterOffline.favorite, isTrue);
        expect(
            await client.syncOfflineProgress(
                movie.id, 2000, offlineDate.subtract(const Duration(hours: 1)),
                actionId: 'old-offline'),
            isFalse);
        expect((await client.details(movie.id)).resumeMs, 9000);
        SharedPreferences.setMockInitialValues({});
        final offlineQueue = MediaServerProgressStore();
        await offlineQueue.record(
            client.connection,
            PlaybackMedia(
                id: Uri(
                    scheme: 'aloe-server',
                    host: client.connection.id,
                    pathSegments: [movie.id]).toString(),
                url: '/offline/movie.mkv',
                title: movie.name),
            10000);
        final synced = await offlineQueue.sync(client);
        expect(synced.sent, 1);
        expect(synced.pending, 0);
        expect((await client.details(movie.id)).resumeMs, 10000);
        expect(
            await client.syncOfflineProgress(
                movie.id, movie.durationMs, DateTime.now().toUtc(),
                actionId: 'complete-${offlineDate.microsecondsSinceEpoch}'),
            isTrue);
        expect((await client.details(movie.id)).played, isTrue);
        await client.setPlayed(movie.id, false);
        await client.setFavorite(movie.id, false);
        print(
            'REAL $kind PASS: ${auth['version']}; 2 versions, 2 audio tracks, authenticated Chinese subtitle, direct decode hash, HLS transcode seek/decode, resume/favorite, season pagination/next-up');
      } finally {
        await client.close();
        reader.close(force: true);
      }
    },
        skip: Platform.environment['ALOE_REAL_${kind.toUpperCase()}'] != '1',
        timeout: const Timeout(Duration(minutes: 3)));
  }
}
