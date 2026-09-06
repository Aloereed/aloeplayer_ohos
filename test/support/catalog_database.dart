import 'package:sqflite/sqflite.dart';

class CatalogMemoryDatabase implements Database {
  final Map<String, Map<String, Object?>> rows = {};
  int inserts = 0;
  int deletes = 0;
  int queryFailures = 0;
  @override
  Future<List<Map<String, Object?>>> query(String table,
      {bool? distinct,
      List<String>? columns,
      String? where,
      List<Object?>? whereArgs,
      String? groupBy,
      String? having,
      String? orderBy,
      int? limit,
      int? offset}) async {
    if (queryFailures > 0) {
      queryFailures--;
      throw StateError('Cannot open index');
    }
    return rows.values.map((e) => Map<String, Object?>.from(e)).toList();
  }

  @override
  Future<int> insert(String table, Map<String, Object?> values,
      {String? nullColumnHack, ConflictAlgorithm? conflictAlgorithm}) async {
    rows[values['filePath']! as String] = Map.of(values);
    return ++inserts;
  }

  @override
  Future<T> transaction<T>(Future<T> Function(Transaction txn) action,
          {bool? exclusive}) async =>
      action(_CatalogTransaction(this));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CatalogTransaction implements Transaction {
  final CatalogMemoryDatabase db;
  _CatalogTransaction(this.db);
  @override
  Future<int> delete(String table,
      {String? where, List<Object?>? whereArgs}) async {
    final removed = db.rows.remove(whereArgs!.first);
    if (removed != null) db.deletes++;
    return removed == null ? 0 : 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
