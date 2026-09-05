import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;
import '../models/catalog_item.dart';
import 'network_playback.dart';

class MediaCatalog extends ChangeNotifier {
  static final instance = MediaCatalog._();
  MediaCatalog._();
  Database? _db;
  Future<void>? _loading;
  List<CatalogItem> items = [];
  bool scanning = false;
  int scanned = 0;
  int _generation = 0;
  String? error;
  Future<void> initialize() => _loading ??= _load();
  Future<void> _load() async {
    _db = await openDatabase(path.join(await getDatabasesPath(), 'media_catalog.db'), version: 1, onCreate: (db, version) async {
      await db.execute('CREATE TABLE catalog(filePath TEXT PRIMARY KEY, title TEXT NOT NULL, series TEXT, plot TEXT, poster TEXT, year INTEGER, season INTEGER, episode INTEGER, revision TEXT NOT NULL)');
      await db.execute('CREATE INDEX catalog_title ON catalog(title)');
    });
    await _reload();
  }
  Future<void> _reload() async {
    items = (await _db!.query('catalog', orderBy: 'series, season, episode, title')).map(CatalogItem.fromMap).toList();
    notifyListeners();
  }
  void cancel() { _generation++; }
  Future<void> scan() async {
    if (scanning) return;
    scanning = true;
    try { await initialize(); } catch (_) { scanning = false; _loading = null; rethrow; }
    scanned = 0;
    error = null;
    final generation = ++_generation;
    final existing = {for (final item in items) item.filePath: item};
    final seen = <String>{};
    var complete = true;
    notifyListeners();
    try {
      for (final kind in ['Videos', 'Audios']) {
        final root = Directory('/storage/Users/currentUser/Download/com.aloereed.aloeplayer/$kind');
        if (!await root.exists()) { complete = false; continue; }
        await for (final entry in root.list(recursive: true, followLinks: false)) {
          if (_generation != generation) { complete = false; break; }
          if (entry is! File || !mediaExtensions.contains(path.extension(entry.path).toLowerCase())) continue;
          seen.add(entry.path);
          final stat = await entry.stat();
          final stem = path.withoutExtension(entry.path);
          File? nfo;
          for (final candidate in ['$stem.nfo', path.join(entry.parent.path, 'movie.nfo')]) {
            final file = File(candidate);
            if (await file.exists()) { nfo = file; break; }
          }
          File? poster;
          for (final candidate in ['$stem-poster.jpg', '$stem.jpg', '$stem.png', path.join(entry.parent.path, 'poster.jpg'), path.join(entry.parent.path, 'folder.jpg')]) {
            final file = File(candidate);
            if (await file.exists()) { poster = file; break; }
          }
          final nfoStat = await nfo?.stat();
          final posterStat = await poster?.stat();
          final revision = '${stat.size}:${stat.modified.millisecondsSinceEpoch}:${nfoStat?.modified.millisecondsSinceEpoch}:${poster?.path}:${posterStat?.modified.millisecondsSinceEpoch}';
          if (existing[entry.path]?.revision != revision) {
            var metadata = const NfoMetadata();
            if (nfo != null && nfoStat != null && nfoStat.size <= 1024 * 1024) {
              try { metadata = NfoMetadata.parse(await nfo.readAsString()); } catch (_) {}
            }
            final item = CatalogItem(filePath: entry.path, title: metadata.title ?? path.basenameWithoutExtension(entry.path), revision: revision,
              series: metadata.showTitle, plot: metadata.plot, poster: poster?.path, year: metadata.year, season: metadata.season, episode: metadata.episode);
            await _db!.insert('catalog', item.toMap(), conflictAlgorithm: ConflictAlgorithm.replace);
          }
          scanned++;
          if (scanned % 50 == 0) await _reload();
        }
        if (_generation != generation) break;
      }
      // Never prune records after cancellation or an inaccessible root.
      if (complete && _generation == generation) {
        final batch = _db!.batch();
        for (final missing in existing.keys.where((key) => !seen.contains(key))) {
          batch.delete('catalog', where: 'filePath = ?', whereArgs: [missing]);
        }
        await batch.commit(noResult: true);
      }
    } catch (_) { error = '部分目录无法读取，已保留原索引；请检查文件访问权限后重试'; }
    finally { scanning = false; await _reload(); }
  }
}
