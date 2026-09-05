import 'dart:async';
import 'package:path/path.dart';
import 'package:sqflite/sqflite.dart';

class HistoryItem {
  final int? id;
  final String filePath;
  final int durationMs; // 播放时长（毫秒）
  final int lastPosition; // 上次播放位置（毫秒）
  final DateTime lastPlayed; // 最后播放时间
  final String mediaType; // 'audio' 或 'video'
  final String? title; // 标题（可选）
  final String? artist; // 艺术家（可选，音频）
  final String? album; // 专辑（可选，音频）
  final String? thumbnailPath; // 缩略图路径（可选）

  HistoryItem({
    this.id,
    required this.filePath,
    required this.durationMs,
    required this.lastPosition,
    required this.lastPlayed,
    required this.mediaType,
    this.title,
    this.artist,
    this.album,
    this.thumbnailPath,
  });

  // 将对象转换为Map
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'filePath': filePath,
      'durationMs': durationMs,
      'lastPosition': lastPosition,
      'lastPlayed': lastPlayed.toIso8601String(),
      'mediaType': mediaType,
      'title': title,
      'artist': artist,
      'album': album,
      'thumbnailPath': thumbnailPath,
    };
  }

  // 从Map创建对象
  factory HistoryItem.fromMap(Map<String, dynamic> map) {
    return HistoryItem(
      id: map['id'],
      filePath: map['filePath'],
      durationMs: map['durationMs'],
      lastPosition: map['lastPosition'],
      lastPlayed: DateTime.parse(map['lastPlayed']),
      mediaType: map['mediaType'],
      title: map['title'],
      artist: map['artist'],
      album: map['album'],
      thumbnailPath: map['thumbnailPath'],
    );
  }

  // 创建对象的副本并更新指定字段
  HistoryItem copyWith({
    int? id,
    String? filePath,
    int? durationMs,
    int? lastPosition,
    DateTime? lastPlayed,
    String? mediaType,
    String? title,
    String? artist,
    String? album,
    String? thumbnailPath,
  }) {
    return HistoryItem(
      id: id ?? this.id,
      filePath: filePath ?? this.filePath,
      durationMs: durationMs ?? this.durationMs,
      lastPosition: lastPosition ?? this.lastPosition,
      lastPlayed: lastPlayed ?? this.lastPlayed,
      mediaType: mediaType ?? this.mediaType,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      thumbnailPath: thumbnailPath ?? this.thumbnailPath,
    );
  }
}

class HistoryService {
  static final HistoryService _instance = HistoryService._internal();
  factory HistoryService() => _instance;
  HistoryService._internal();

  Database? _database;
  final String _tableName = 'play_history';
  Future<Database>? _opening;

  // 获取数据库实例
  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await (_opening ??= _initDatabase().whenComplete(() => _opening = null));
    return _database!;
  }

  // 初始化数据库
  Future<Database> _initDatabase() async {
    String path = join(await getDatabasesPath(), 'player_history.db');
    return await openDatabase(
      path,
      version: 1,
      onCreate: (Database db, int version) async {
        await db.execute('''
          CREATE TABLE $_tableName (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            filePath TEXT NOT NULL,
            durationMs INTEGER NOT NULL,
            lastPosition INTEGER NOT NULL,
            lastPlayed TEXT NOT NULL,
            mediaType TEXT NOT NULL,
            title TEXT,
            artist TEXT,
            album TEXT,
            thumbnailPath TEXT
          )
        ''');
        await db.execute(
          'CREATE UNIQUE INDEX idx_path ON $_tableName (filePath)',
        );
      },
    );
  }

  // 新增或更新播放历史记录
  Future<void> updateHistory(HistoryItem item) async {
    final db = await database;

    await db.transaction((txn) async {
      final existing = await txn.query(_tableName, where: 'filePath = ?', whereArgs: [item.filePath], limit: 1);
      final values = item.toMap()..remove('id');
      if (existing.isNotEmpty) {
        // Opening a file must not erase its saved progress before resume reads it.
        if (item.lastPosition == 0) values['lastPosition'] = existing.first['lastPosition'];
        if (item.durationMs == 0) values['durationMs'] = existing.first['durationMs'];
        for (final field in ['title', 'artist', 'album', 'thumbnailPath']) {
          if (values[field] == null) values.remove(field);
        }
        await txn.update(_tableName, values, where: 'filePath = ?', whereArgs: [item.filePath]);
      } else {
        await txn.insert(_tableName, values);
      }
    });
  }

  // 获取特定文件的播放历史
  Future<HistoryItem?> getHistoryByPath(String filePath) async {
    final db = await database;
    List<Map<String, dynamic>> maps = await db.query(
      _tableName,
      where: 'filePath = ?',
      whereArgs: [filePath],
    );

    if (maps.isNotEmpty) {
      return HistoryItem.fromMap(maps.first);
    }
    return null;
  }

  // 获取最近播放的所有历史记录
  Future<List<HistoryItem>> getRecentHistory({int limit = 20}) async {
    final db = await database;
    List<Map<String, dynamic>> maps = await db.query(
      _tableName,
      orderBy: 'lastPlayed DESC',
      limit: limit,
    );

    return maps.map((map) => HistoryItem.fromMap(map)).toList();
  }

  // 获取最近播放的音频历史记录
  Future<List<HistoryItem>> getRecentAudioHistory({int limit = 20}) async {
    final db = await database;
    List<Map<String, dynamic>> maps = await db.query(
      _tableName,
      where: 'mediaType = ?',
      whereArgs: ['audio'],
      orderBy: 'lastPlayed DESC',
      limit: limit,
    );

    return maps.map((map) => HistoryItem.fromMap(map)).toList();
  }

  // 获取最近播放的视频历史记录
  Future<List<HistoryItem>> getRecentVideoHistory({int limit = 20}) async {
    final db = await database;
    List<Map<String, dynamic>> maps = await db.query(
      _tableName,
      where: 'mediaType = ?',
      whereArgs: ['video'],
      orderBy: 'lastPlayed DESC',
      limit: limit,
    );

    return maps.map((map) => HistoryItem.fromMap(map)).toList();
  }

  // 删除特定的历史记录
  Future<void> deleteHistory(String filePath) async {
    final db = await database;
    await db.delete(
      _tableName,
      where: 'filePath = ?',
      whereArgs: [filePath],
    );
  }

  // 清空所有历史记录
  Future<void> clearAllHistory() async {
    final db = await database;
    await db.delete(_tableName);
  }

  // 清空特定类型的历史记录（音频或视频）
  Future<void> clearHistoryByType(String mediaType) async {
    final db = await database;
    await db.delete(
      _tableName,
      where: 'mediaType = ?',
      whereArgs: [mediaType],
    );
  }

  Future<List<HistoryItem>> getContinueWatching({int limit = 100}) async {
    final db = await database;
    final rows = await db.query(_tableName, where: 'lastPosition > 0 AND (durationMs = 0 OR lastPosition < durationMs * 0.95)', orderBy: 'lastPlayed DESC', limit: limit);
    return rows.map(HistoryItem.fromMap).toList();
  }

  Future<void> markCompleted(String filePath) async {
    final db = await database;
    await db.rawUpdate('UPDATE $_tableName SET lastPosition = durationMs WHERE filePath = ?', [filePath]);
  }

  Future<void> relocate(String oldPath, String newPath) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(_tableName, where: 'filePath = ?', whereArgs: [newPath]);
      await txn.update(_tableName, {'filePath': newPath}, where: 'filePath = ?', whereArgs: [oldPath]);
    });
  }

  // 快速记录当前播放位置（无需加载完整对象）
  Future<void> updatePosition(String filePath, int positionMs) async {
    final db = await database;
    await db.rawUpdate('''
      UPDATE $_tableName
      SET lastPosition = ?, lastPlayed = ?
      WHERE filePath = ?
    ''', [positionMs, DateTime.now().toIso8601String(), filePath]);
  }

  // 快速记录媒体总时长（无需加载完整对象）
  Future<void> updateDuration(String filePath, int durationMs) async {
    final db = await database;
    await db.rawUpdate('''
      UPDATE $_tableName
      SET durationMs = ?
      WHERE filePath = ?
    ''', [durationMs, filePath]);
  }

  // 检查文件是否存在于历史记录中
  Future<bool> exists(String filePath) async {
    final db = await database;
    List<Map<String, dynamic>> result = await db.query(
      _tableName,
      where: 'filePath = ?',
      whereArgs: [filePath],
    );
    return result.isNotEmpty;
  }
}