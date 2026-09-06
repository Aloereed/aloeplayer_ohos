import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as path;
import '../models/catalog_item.dart';
import 'catalog_scanner.dart';

class MediaCatalog extends ChangeNotifier {
  static final instance = MediaCatalog._();
  MediaCatalog._() : roots = defaultRoots;
  @visibleForTesting
  MediaCatalog.forTesting(Database database, this.roots) : _db = database;
  static const defaultRoots = [
    '/storage/Users/currentUser/Download/com.aloereed.aloeplayer/Videos',
    '/storage/Users/currentUser/Download/com.aloereed.aloeplayer/Audios',
  ];
  final List<String> roots;
  Database? _db;
  Future<void>? _loading;
  List<CatalogItem> items = [];
  bool scanning = false;
  bool cancelled = false;
  int scanned = 0;
  int skipped = 0;
  int unavailableRoots = 0;
  int _generation = 0;
  String? error;
  DateTime? lastScan;

  Future<void> initialize() async {
    try {
      await (_loading ??= _load());
    } catch (_) {
      _loading = null;
      rethrow;
    }
  }

  Future<void> _load() async {
    _db ??= await openDatabase(
        path.join(await getDatabasesPath(), 'media_catalog.db'),
        version: 1, onCreate: (db, version) async {
      await db.execute(
          'CREATE TABLE catalog(filePath TEXT PRIMARY KEY, title TEXT NOT NULL, series TEXT, plot TEXT, poster TEXT, year INTEGER, season INTEGER, episode INTEGER, revision TEXT NOT NULL)');
      await db.execute('CREATE INDEX catalog_title ON catalog(title)');
    });
    await _reload();
  }

  Future<void> _reload() async {
    items =
        (await _db!.query('catalog', orderBy: 'series, season, episode, title'))
            .map(CatalogItem.fromMap)
            .toList();
    notifyListeners();
  }

  void cancel() {
    if (!scanning || cancelled) return;
    cancelled = true;
    _generation++;
    notifyListeners();
  }

  Future<void> scan() async {
    if (scanning) return;
    scanning = true;
    cancelled = false;
    scanned = 0;
    skipped = 0;
    unavailableRoots = 0;
    error = null;
    final generation = ++_generation;
    notifyListeners();
    try {
      await initialize();
      final existing = {for (final item in items) item.filePath: item};
      final scanner = CatalogScanner();
      final prune = <String>[];
      for (final rootPath in roots) {
        if (_generation != generation) break;
        final root = Directory(rootPath);
        final seen = <String>{};
        var complete = true;
        try {
          if (!await root.exists()) {
            unavailableRoots++;
            continue;
          }
          await for (final entry
              in root.list(recursive: true, followLinks: false)) {
            if (_generation != generation) {
              complete = false;
              break;
            }
            if (entry is! File || !scanner.accepts(entry)) continue;
            seen.add(entry.path);
            CatalogItem? item;
            try {
              item = await scanner.read(entry, root);
            } catch (_) {
              skipped++;
            }
            if (_generation != generation) {
              complete = false;
              break;
            }
            if (item != null &&
                existing[entry.path]?.revision != item.revision) {
              await _db!.insert('catalog', item.toMap(),
                  conflictAlgorithm: ConflictAlgorithm.replace);
            }
            scanned++;
            if (scanned % 20 == 0) await _reload();
          }
        } on FileSystemException {
          complete = false;
          unavailableRoots++;
        }
        // Prune only enumerated roots. An absent audio root must not block
        // video cleanup or erase its own existing records.
        if (complete && _generation == generation) {
          prune.addAll(existing.keys.where(
              (key) => path.isWithin(rootPath, key) && !seen.contains(key)));
        }
      }
      if (_generation == generation) {
        await _db!.transaction((txn) async {
          for (final missing in prune) {
            await txn
                .delete('catalog', where: 'filePath = ?', whereArgs: [missing]);
          }
        });
        lastScan = DateTime.now();
      }
      if (unavailableRoots > 0 || skipped > 0) {
        error = [
          if (unavailableRoots > 0) '$unavailableRoots 个目录尚未创建或无法访问',
          if (skipped > 0) '$skipped 个文件暂时无法读取',
          '已保留相关索引'
        ].join('，');
      }
    } catch (_) {
      error = '媒体索引暂时无法更新，请重试';
    } finally {
      scanning = false;
      try {
        if (_db != null) await _reload();
      } catch (_) {
        error = '媒体索引暂时无法读取，请重试';
      }
      notifyListeners();
    }
  }
}
