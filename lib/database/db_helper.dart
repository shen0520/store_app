import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import '../models/goods.dart';

class DBHelper {
  static final DBHelper _instance = DBHelper._internal();
  factory DBHelper() => _instance;
  DBHelper._internal();

  static Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB();
    return _database!;
  }

  Future<Database> _initDB() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'store_price.db');

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    // 开启 WAL 模式提升并发性能
    await db.execute('PRAGMA journal_mode=WAL;');

    await db.execute('''
      CREATE TABLE goods (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        barcode VARCHAR(50) NOT NULL UNIQUE,
        goods_name VARCHAR(200) NOT NULL,
        brand VARCHAR(100),
        spec VARCHAR(100),
        goods_img VARCHAR(500),
        purchase_price DECIMAL(10,2),
        sell_price DECIMAL(10,2) NOT NULL,
        remark VARCHAR(200),
        create_time DATETIME NOT NULL,
        update_time DATETIME NOT NULL
      )
    ''');

    await db.execute('''
      CREATE INDEX idx_barcode ON goods(barcode)
    ''');

    await _createScanHistoryTable(db);
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // 开启 WAL 模式
      await db.execute('PRAGMA journal_mode=WAL;');

      // 创建扫码历史表
      await _createScanHistoryTable(db);

      // 为 goods 表添加 barcode UNIQUE 约束（SQLite 不支持直接 ADD CONSTRAINT）
      await db.transaction((txn) async {
        // 创建新表（含 UNIQUE）
        await txn.execute('''
          CREATE TABLE goods_new (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            barcode VARCHAR(50) NOT NULL UNIQUE,
            goods_name VARCHAR(200) NOT NULL,
            brand VARCHAR(100),
            spec VARCHAR(100),
            goods_img VARCHAR(500),
            purchase_price DECIMAL(10,2),
            sell_price DECIMAL(10,2) NOT NULL,
            remark VARCHAR(200),
            create_time DATETIME NOT NULL,
            update_time DATETIME NOT NULL
          )
        ''');

        // 复制数据（重复 barcode 保留 update_time 最新的）
        await txn.execute('''
          INSERT OR REPLACE INTO goods_new
          SELECT * FROM goods
          ORDER BY update_time DESC
        ''');

        // 删除旧表
        await txn.execute('DROP TABLE goods');

        // 重命名
        await txn.execute('ALTER TABLE goods_new RENAME TO goods');

        // 重建索引
        await txn.execute('CREATE INDEX idx_barcode ON goods(barcode)');
      });
    }
  }

  Future<void> _createScanHistoryTable(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS scan_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        barcode VARCHAR(50) NOT NULL,
        goods_name VARCHAR(200),
        sell_price DECIMAL(10,2),
        scan_time DATETIME NOT NULL
      )
    ''');
    await db.execute('''
      CREATE INDEX idx_scan_time ON scan_history(scan_time DESC)
    ''');
  }

  Future<int> insertGoods(Goods goods) async {
    final db = await database;
    return await db.insert('goods', goods.toMap());
  }

  Future<int> updateGoods(Goods goods) async {
    final db = await database;
    return await db.update(
      'goods',
      goods.toMap(),
      where: 'id = ?',
      whereArgs: [goods.id],
    );
  }

  Future<int> deleteGoods(int id) async {
    final db = await database;
    return await db.delete(
      'goods',
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<Goods?> getGoodsByBarcode(String barcode) async {
    final db = await database;
    final results = await db.query(
      'goods',
      where: 'barcode = ?',
      whereArgs: [barcode],
    );
    if (results.isEmpty) return null;
    return Goods.fromMap(results.first);
  }

  Future<Goods?> getGoodsById(int id) async {
    final db = await database;
    final results = await db.query(
      'goods',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (results.isEmpty) return null;
    return Goods.fromMap(results.first);
  }

  Future<List<Goods>> getAllGoods({
    String? searchQuery,
    int limit = 50,
    int offset = 0,
  }) async {
    final db = await database;
    if (searchQuery != null && searchQuery.isNotEmpty) {
      final results = await db.query(
        'goods',
        where: 'goods_name LIKE ? OR barcode LIKE ?',
        whereArgs: ['%$searchQuery%', '%$searchQuery%'],
        orderBy: 'update_time DESC',
        limit: limit,
        offset: offset,
      );
      return results.map((e) => Goods.fromMap(e)).toList();
    }
    final results = await db.query(
      'goods',
      orderBy: 'update_time DESC',
      limit: limit,
      offset: offset,
    );
    return results.map((e) => Goods.fromMap(e)).toList();
  }

  Future<bool> barcodeExists(String barcode) async {
    final db = await database;
    final results = await db.rawQuery(
      'SELECT COUNT(*) as count FROM goods WHERE barcode = ?',
      [barcode],
    );
    return (results.first['count'] as int) > 0;
  }

  Future<int> getGoodsCount() async {
    final db = await database;
    final results = await db.rawQuery('SELECT COUNT(*) as count FROM goods');
    return (results.first['count'] as int);
  }

  Future<void> close() async {
    final db = await database;
    await db.close();
    _database = null;
  }

  /// 批量导入商品
  /// [goodsList] 要导入的商品列表
  /// [conflictStrategy] 冲突处理策略: 'skip'(跳过), 'overwrite'(覆盖), 'merge'(智能合并)
  /// 返回 {inserted: 新增数, updated: 更新数, skipped: 跳过数}
  Future<Map<String, int>> importGoods(
    List<Goods> goodsList, {
    String conflictStrategy = 'skip',
  }) async {
    final db = await database;
    int inserted = 0;
    int updated = 0;
    int skipped = 0;

    await db.transaction((txn) async {
      for (final goods in goodsList) {
        final existing = await txn.query(
          'goods',
          where: 'barcode = ?',
          whereArgs: [goods.barcode],
        );

        if (existing.isEmpty) {
          // 条码不存在，直接插入
          await txn.insert('goods', goods.toMap());
          inserted++;
        } else {
          // 条码已存在，根据策略处理
          final existingId = existing.first['id'] as int;

          switch (conflictStrategy) {
            case 'skip':
              skipped++;
              break;
            case 'overwrite':
              await txn.update(
                'goods',
                goods.toMap(),
                where: 'id = ?',
                whereArgs: [existingId],
              );
              updated++;
              break;
            case 'merge':
              // 智能合并：保留 update_time 较新的
              final existingUpdateTime = DateTime.parse(
                existing.first['update_time'] as String,
              );
              if (goods.updateTime.isAfter(existingUpdateTime)) {
                await txn.update(
                  'goods',
                  goods.toMap(),
                  where: 'id = ?',
                  whereArgs: [existingId],
                );
                updated++;
              } else {
                skipped++;
              }
              break;
            default:
              skipped++;
          }
        }
      }
    });

    return {'inserted': inserted, 'updated': updated, 'skipped': skipped};
  }

  /// 导出全部商品数据
  Future<List<Map<String, dynamic>>> exportAllGoods() async {
    final db = await database;
    return await db.query('goods', orderBy: 'update_time DESC');
  }

  /// 清空数据库（导入前可选）
  Future<void> clearAllGoods() async {
    final db = await database;
    await db.delete('goods');
    await db.delete('scan_history');
  }

  // ==================== 扫码历史记录 ====================

  /// 插入扫码记录
  Future<int> insertScanHistory({
    required String barcode,
    String? goodsName,
    double? sellPrice,
  }) async {
    final db = await database;
    // 清理超过 50 条的旧记录
    final countResult = await db.rawQuery('SELECT COUNT(*) as count FROM scan_history');
    final count = (countResult.first['count'] as int);
    if (count >= 50) {
      await db.rawDelete(
        'DELETE FROM scan_history WHERE id IN (SELECT id FROM scan_history ORDER BY scan_time ASC LIMIT ?)',
        [count - 49],
      );
    }
    return await db.insert('scan_history', {
      'barcode': barcode,
      'goods_name': goodsName,
      'sell_price': sellPrice,
      'scan_time': DateTime.now().toIso8601String(),
    });
  }

  /// 获取最近扫码历史
  Future<List<Map<String, dynamic>>> getScanHistory({int limit = 20}) async {
    final db = await database;
    return await db.query(
      'scan_history',
      orderBy: 'scan_time DESC',
      limit: limit,
    );
  }
}
