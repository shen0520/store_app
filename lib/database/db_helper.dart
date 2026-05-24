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
      version: 1,
      onCreate: _createDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE goods (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        barcode VARCHAR(50) NOT NULL,
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

  Future<List<Goods>> getAllGoods({String? searchQuery}) async {
    final db = await database;
    if (searchQuery != null && searchQuery.isNotEmpty) {
      final results = await db.query(
        'goods',
        where: 'goods_name LIKE ? OR barcode LIKE ?',
        whereArgs: ['%$searchQuery%', '%$searchQuery%'],
        orderBy: 'update_time DESC',
      );
      return results.map((e) => Goods.fromMap(e)).toList();
    }
    final results = await db.query(
      'goods',
      orderBy: 'update_time DESC',
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
}
