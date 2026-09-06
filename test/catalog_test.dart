import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:aloeplayer/history_service.dart';
import 'package:aloeplayer/models/catalog_item.dart';
import 'package:aloeplayer/services/catalog_scanner.dart';
import 'package:aloeplayer/services/catalog_playback.dart';
import 'package:aloeplayer/services/media_catalog.dart';
import 'package:aloeplayer/settings.dart';
import 'support/catalog_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('aloe-catalog-');
  });
  tearDown(() async {
    await root.delete(recursive: true);
  });
  Future<File> create(String name, [String contents = 'video']) async {
    final file = File(path.normalize(path.join(root.path, name)));
    await file.parent.create(recursive: true);
    return file.writeAsString(contents);
  }

  test(
      'default hardware decoding uses recommended mode and preserves explicit choices',
      () async {
    SharedPreferences.setMockInitialValues({});
    final settings = SettingsService();
    expect(await settings.getMpvHardwareDecoding(), 1);
    for (final mode in [0, 2, 1]) {
      await settings.saveMpvHardwareDecoding(mode);
      expect(await settings.getMpvHardwareDecoding(), mode);
    }
    await settings.saveMpvHardwareDecoding(99);
    expect(await settings.getMpvHardwareDecoding(), 1);
  });
  test(
      'scanner inherits show metadata and cover across season folders, NFO takes precedence',
      () async {
    await create('Show/tvshow.nfo',
        '<tvshow><title>星海</title><year>2025</year><plot>故事 &amp; 冒险</plot></tvshow>');
    final poster = await create('Show/POSTER.PNG');
    final episode = await create('Show/Season 02/Show.S02E10.mkv');
    await create('Show/Season 02/Show.S02E10.NFO',
        '<episodedetails><title>归来</title><season>2</season><episode>10</episode></episodedetails>');
    final item = await CatalogScanner().read(episode, root);
    expect(item.title, '归来');
    expect(item.series, '星海');
    expect(item.plot, '故事 & 冒险');
    expect(item.year, 2025);
    expect(item.episode, 10);
    expect(item.poster, poster.path);
    expect(CatalogItem.fromMap(item.toMap()).toMap(), item.toMap());
  });
  test(
      'malformed NFO falls back to filename, shortcut and audio extensions are indexed',
      () async {
    final video = await create('My.Show.S01E02.mkv');
    await create('My.Show.S01E02.nfo', '<not valid xml');
    final scanner = CatalogScanner();
    final item = await scanner.read(video, root);
    expect(item.series, 'My Show');
    expect(item.season, 1);
    expect(item.episode, 2);
    final shortcut = await create('Song.FLAC.lnk', '/music/song.flac');
    expect(scanner.accepts(shortcut), isTrue);
    expect((await scanner.read(shortcut, root)).isAudio, isTrue);
    expect(scanner.accepts(File('${root.path}/pending.mp4.part')), isFalse);
  });
  test(
      'anime release names group without release tags or mistaking movie years for episodes',
      () async {
    final scanner = CatalogScanner();
    final first = await scanner.read(
        await create(
            '[Group] BanG Dream! Ave Mujica - 03 [WebRip 1080p HEVC].mkv'),
        root);
    final second = await scanner.read(
        await create('[Other] BanG Dream! Ave Mujica - 10 [WebRip].mkv'), root);
    expect(first.series, 'BanG Dream! Ave Mujica');
    expect(second.series, first.series);
    expect(first.episode, 3);
    expect(second.episode, 10);
    expect(
        CatalogCollection.group([second, first]).single.items, [first, second]);
    final bracketed = await scanner.read(
        await create('[Sub] Make Heroine ga Oosugiru! [01][WebRip].mkv'), root);
    expect(bracketed.series, 'Make Heroine ga Oosugiru!');
    expect(bracketed.episode, 1);
    final movie =
        await scanner.read(await create('Movie - 2024 [1080p].mp4'), root);
    expect(movie.series, isNull);
    expect(movie.year, 2024);
  });
  test('scanner respects library boundary and notices sidecar removal',
      () async {
    await create('tvshow.nfo', '<tvshow><title>Unrelated</title></tvshow>');
    final file = await create('Movies/Film (2024).mp4');
    final nfo =
        await create('Movies/movie.nfo', '<movie><title>电影</title></movie>');
    final before = await CatalogScanner().read(file, file.parent);
    expect(before.series, isNull);
    expect(before.title, '电影');
    await nfo.delete();
    final after = await CatalogScanner().read(file, file.parent);
    expect(after.year, 2024);
    expect(after.title, 'Film (2024)');
    expect(after.revision, isNot(before.revision));
  });
  test(
      'incremental scan prunes each available root without erasing unavailable roots',
      () async {
    final video = await create('Videos/film.mp4');
    final db = CatalogMemoryDatabase();
    final staleVideo = path.join(root.path, 'Videos', 'gone.mp4');
    final staleAudio = path.join(root.path, 'Audios', 'saved.mp3');
    for (final file in [staleVideo, staleAudio]) {
      db.rows[file] =
          CatalogItem(filePath: file, title: 'old', revision: '').toMap();
    }
    final catalog = MediaCatalog.forTesting(
        db, [video.parent.path, path.join(root.path, 'Audios')]);
    await catalog.scan();
    expect(db.rows.containsKey(staleVideo), isFalse);
    expect(db.rows.containsKey(staleAudio), isTrue);
    expect(db.rows.containsKey(video.path), isTrue);
    expect(catalog.unavailableRoots, 1);
    expect(catalog.scanning, isFalse);
    final writes = db.inserts;
    await catalog.scan();
    expect(db.inserts, writes);
    catalog.dispose();
  });
  test('cancel preserves old rows and completed work; retry completes cleanup',
      () async {
    for (var i = 0; i < 30; i++) {
      await create('Videos/clip$i.mp4');
    }
    final db = CatalogMemoryDatabase();
    final stale = path.join(root.path, 'Videos', 'gone.mp4');
    db.rows[stale] =
        CatalogItem(filePath: stale, title: 'old', revision: '').toMap();
    final catalog =
        MediaCatalog.forTesting(db, [path.join(root.path, 'Videos')]);
    void cancel() {
      if (catalog.scanning && catalog.scanned >= 20) catalog.cancel();
    }

    catalog.addListener(cancel);
    await catalog.scan();
    expect(catalog.cancelled, isTrue);
    expect(catalog.scanned, 20);
    expect(db.rows.containsKey(stale), isTrue);
    expect(db.inserts, 20);
    catalog.removeListener(cancel);
    await catalog.scan();
    expect(catalog.cancelled, isFalse);
    expect(catalog.scanned, 30);
    expect(db.rows.containsKey(stale), isFalse);
    expect(db.rows.length, 30);
    catalog.dispose();
  });
  test('initialization failure can be retried', () async {
    final db = CatalogMemoryDatabase()..queryFailures = 1;
    final catalog = MediaCatalog.forTesting(db, []);
    await expectLater(catalog.initialize(), throwsStateError);
    await catalog.initialize();
    expect(catalog.items, isEmpty);
    catalog.dispose();
  });
  test(
      'series group across seasons, numeric ordering and search preserve full queue',
      () {
    CatalogItem episode(int season, int number) => CatalogItem(
        filePath:
            path.join(root.path, 'Show', 'Season $season', 'ep$number.mkv'),
        title: 'Episode $number',
        series: '星海',
        season: season,
        episode: number,
        revision: '0:1');
    final items = [episode(2, 1), episode(1, 10), episode(1, 2)];
    final collection = CatalogCollection.group(items).single;
    expect(collection.items.map((i) => i.episode), [2, 10, 1]);
    expect(collection.matches('星海 10'), isTrue);
    expect(collection.items.length, 3);
    expect(compareCatalogTitles('Episode 2', 'Episode 10'), lessThan(0));
    final duplicate = CatalogItem(
        filePath: path.join(root.path, 'Other', 'ep1.mkv'),
        title: 'Other',
        series: '星海',
        revision: '');
    expect(CatalogCollection.group([...items, duplicate]).length, 2);
  });
  test('resume uses most recent unfinished episode then next unseen episode',
      () {
    final items = List.generate(
        3,
        (i) => CatalogItem(
            filePath: '/show/$i.mkv',
            title: '$i',
            series: 'Show',
            episode: i + 1,
            revision: ''));
    final collection = CatalogCollection('show', items);
    HistoryItem history(int index, int position) => HistoryItem(
        filePath: items[index].filePath,
        durationMs: 100000,
        lastPosition: position,
        lastPlayed: DateTime(2026, 1, index + 1),
        mediaType: 'video');
    final progress = {
      items[0].filePath: history(0, 50000),
      items[1].filePath: history(1, 60000)
    };
    expect(catalogNext(collection, progress), items[1]);
    progress[items[0].filePath] = history(0, 100000);
    progress[items[1].filePath] = history(1, 100000);
    expect(catalogNext(collection, progress), items[2]);
    expect(catalogResume(progress[items[1].filePath]), isNull);
  });
  test(
      'playback queue skips missing siblings but reports a missing selected file',
      () async {
    final file = await create('present.mkv');
    final present =
        CatalogItem(filePath: file.path, title: 'Present', revision: '');
    final missing = CatalogItem(
        filePath: path.join(root.path, 'missing.mkv'),
        title: 'Missing',
        revision: '');
    expect((await catalogQueue(present, [missing, present])).single.url,
        file.path);
    await expectLater(catalogQueue(missing, [missing, present]),
        throwsA(isA<FileSystemException>()));
  });
}
