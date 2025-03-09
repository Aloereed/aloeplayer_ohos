import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class FavoriteItem {
  final int? id;
  final String path;
  final String name;
  final String type; // 'video' 或 'audio'
  final int timestamp;

  FavoriteItem({
    this.id,
    required this.path,
    required this.name,
    required this.type,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'path': path,
      'name': name,
      'type': type,
      'timestamp': timestamp,
    };
  }

  factory FavoriteItem.fromMap(Map<String, dynamic> map) {
    return FavoriteItem(
      id: map['id'],
      path: map['path'],
      name: map['name'],
      type: map['type'],
      timestamp: map['timestamp'],
    );
  }
}

class FavoritesDatabase {
  static final FavoritesDatabase instance = FavoritesDatabase._init();
  static Database? _database;

  FavoritesDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('favorites.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 1,
      onCreate: _createDB,
    );
  }

  Future _createDB(Database db, int version) async {
    const idType = 'INTEGER PRIMARY KEY AUTOINCREMENT';
    const textType = 'TEXT NOT NULL';
    const intType = 'INTEGER NOT NULL';

    await db.execute('''
      CREATE TABLE favorites (
        id $idType,
        path $textType,
        name $textType,
        type $textType,
        timestamp $intType
      )
    ''');
  }

  // 添加到收藏
  Future<int> addFavorite(FavoriteItem favorite) async {
    final db = await instance.database;
    
    // 先检查是否已经收藏
    final existing = await db.query(
      'favorites',
      where: 'path = ?',
      whereArgs: [favorite.path],
    );
    
    if (existing.isNotEmpty) {
      return existing.first['id'] as int; // 已存在，返回现有ID
    }
    
    return await db.insert('favorites', favorite.toMap());
  }

  // 从收藏中移除
  Future<int> removeFavorite(String path) async {
    final db = await instance.database;
    return await db.delete(
      'favorites',
      where: 'path = ?',
      whereArgs: [path],
    );
  }

  // 检查是否已收藏
  Future<bool> isFavorite(String path) async {
    final db = await instance.database;
    final result = await db.query(
      'favorites',
      where: 'path = ?',
      whereArgs: [path],
    );
    return result.isNotEmpty;
  }

  // 获取所有收藏
  Future<List<FavoriteItem>> getAllFavorites() async {
    final db = await instance.database;
    final result = await db.query(
      'favorites',
      orderBy: 'timestamp DESC',
    );
    return result.map((json) => FavoriteItem.fromMap(json)).toList();
  }

  // 获取特定类型的收藏
  Future<List<FavoriteItem>> getFavoritesByType(String type) async {
    final db = await instance.database;
    final result = await db.query(
      'favorites',
      where: 'type = ?',
      whereArgs: [type],
      orderBy: 'timestamp DESC',
    );
    return result.map((json) => FavoriteItem.fromMap(json)).toList();
  }

  // 关闭数据库
  Future close() async {
    final db = await instance.database;
    db.close();
  }
}