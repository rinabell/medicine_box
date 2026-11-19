import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../models/medicine.dart';
import 'search_query.dart';

/// 本地存储层：所有药品资料都存在手机里的 SQLite 数据库，
/// 不上传、不需要账号、不需要云同步。联网只用于「查一次说明书」，结果立刻落库。
class DatabaseHelper {
  DatabaseHelper._({DatabaseFactory? factory, String? dbName})
      : _factory = factory,
        _dbName = dbName ?? 'medicine_box.db';

  static final DatabaseHelper instance = DatabaseHelper._();

  /// 测试专用：注入 ffi 工厂和独立库名，避免污染真机数据库。
  @visibleForTesting
  factory DatabaseHelper.forTesting(
    DatabaseFactory factory, {
    String? dbName,
  }) =>
      DatabaseHelper._(factory: factory, dbName: dbName);

  final DatabaseFactory? _factory;
  final String _dbName;

  static const int _dbVersion = 1;
  static const String _table = 'medicines';

  DatabaseFactory get _activeFactory => _factory ?? databaseFactory;

  @visibleForTesting
  String get dbName => _dbName;

  Database? _db;

  Future<Database> get database async {
    _db ??= await _open();
    return _db!;
  }

  Future<Database> _open() async {
    final dir = await _activeFactory.getDatabasesPath();
    final dbPath = p.join(dir, _dbName);
    return _activeFactory.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: _dbVersion,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE $_table (
              code        TEXT PRIMARY KEY,
              name        TEXT NOT NULL,
              ingredient  TEXT NOT NULL DEFAULT '',
              leaflet     TEXT NOT NULL DEFAULT '',
              note        TEXT NOT NULL DEFAULT '',
              count       INTEGER NOT NULL DEFAULT 1,
              source      TEXT NOT NULL DEFAULT 'manual',
              created_at  INTEGER NOT NULL,
              updated_at  INTEGER NOT NULL
            )
          ''');
          await db.execute('CREATE INDEX idx_medicines_name ON $_table(name)');
        },
      ),
    );
  }

  @visibleForTesting
  Future<void> closeForTest() async {
    await _db?.close();
    _db = null;
  }

  static int _now() => DateTime.now().millisecondsSinceEpoch;

  Future<List<Medicine>> all() async {
    final db = await database;
    final rows = await db.query(_table, orderBy: 'updated_at DESC');
    return rows.map(Medicine.fromMap).toList();
  }

  Future<Medicine?> findByCode(String code) async {
    final db = await database;
    final rows = await db.query(
      _table,
      where: 'code = ?',
      whereArgs: [code],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return Medicine.fromMap(rows.first);
  }

  Future<void> insert(Medicine m) async {
    final db = await database;
    await db.insert(
      _table,
      m.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// 需求②：同一个编码再次被扫到 → 件数 +1，不重复建档。
  Future<int> increment(String code) async {
    final db = await database;
    return db.rawUpdate(
      'UPDATE $_table SET count = count + 1, updated_at = ? WHERE code = ?',
      [_now(), code],
    );
  }

  Future<void> updateCount(String code, int count) async {
    final db = await database;
    await db.update(
      _table,
      {'count': count < 0 ? 0 : count, 'updated_at': _now()},
      where: 'code = ?',
      whereArgs: [code],
    );
  }

  Future<void> update(Medicine m) async {
    final db = await database;
    await db.update(_table, m.toMap(), where: 'code = ?', whereArgs: [m.code]);
  }

  Future<void> delete(String code) async {
    final db = await database;
    await db.delete(_table, where: 'code = ?', whereArgs: [code]);
  }

  /// 需求④：模糊 / 精准双模式搜索，覆盖 药名、成分、说明书、备注（编码也一起搜）。
  /// 具体 SQL 由 [SearchQuery] 构造，便于单测。
  Future<List<Medicine>> search(String keyword, {required bool exact}) async {
    final query = SearchQuery.build(keyword, exact: exact);
    if (query.isEmpty) return all();

    final db = await database;
    final rows = await db.rawQuery(
      'SELECT * FROM $_table WHERE ${query.where} ORDER BY updated_at DESC',
      query.args,
    );
    return rows.map(Medicine.fromMap).toList();
  }
}
