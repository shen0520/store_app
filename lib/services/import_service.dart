import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import '../database/db_helper.dart';
import '../models/goods.dart';

class ImportService {
  /// 支持的文件格式
  static const List<String> supportedExtensions = ['json', 'csv'];

  /// 选择并导入文件
  /// [conflictStrategy] 冲突处理策略: 'skip', 'overwrite', 'merge'
  /// 返回 {success: bool, message: String, result: Map?}
  Future<Map<String, dynamic>> importFromFile({
    String conflictStrategy = 'skip',
  }) async {
    // 1. 选择文件
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: supportedExtensions,
    );

    if (result == null || result.files.isEmpty) {
      return {'success': false, 'message': '未选择文件'};
    }

    final filePath = result.files.first.path;
    if (filePath == null) {
      return {'success': false, 'message': '文件路径无效'};
    }

    final ext = filePath.split('.').last.toLowerCase();

    try {
      List<Goods> goodsList;

      if (ext == 'json') {
        goodsList = await _parseJsonFile(filePath);
      } else if (ext == 'csv') {
        goodsList = await _parseCsvFile(filePath);
      } else {
        return {'success': false, 'message': '不支持的文件格式: .$ext'};
      }

      if (goodsList.isEmpty) {
        return {'success': false, 'message': '文件中没有找到商品数据'};
      }

      // 导入到数据库
      final db = DBHelper();
      final importResult = await db.importGoods(
        goodsList,
        conflictStrategy: conflictStrategy,
      );

      return {
        'success': true,
        'message': '导入完成\n'
            '新增: ${importResult['inserted']} 条\n'
            '更新: ${importResult['updated']} 条\n'
            '跳过: ${importResult['skipped']} 条',
        'result': importResult,
      };
    } catch (e) {
      return {'success': false, 'message': '导入失败: $e'};
    }
  }

  /// 解析 JSON 文件
  Future<List<Goods>> _parseJsonFile(String filePath) async {
    final file = File(filePath);
    final content = await file.readAsString();
    final jsonData = jsonDecode(content);

    List<dynamic> goodsArray;
    if (jsonData is Map && jsonData.containsKey('goods')) {
      goodsArray = jsonData['goods'] as List;
    } else if (jsonData is List) {
      goodsArray = jsonData;
    } else {
      throw Exception('JSON 格式不正确，未找到商品数据');
    }

    return goodsArray.map((item) {
      // 兼容导出时的字段名和数据库字段名
      final map = Map<String, dynamic>.from(item as Map);
      _normalizeFieldNames(map);
      return Goods.fromMap(map);
    }).toList();
  }

  /// 解析 CSV 文件
  Future<List<Goods>> _parseCsvFile(String filePath) async {
    final file = File(filePath);
    final lines = await file.readAsLines();

    if (lines.isEmpty) return [];

    // 跳过表头
    final dataLines = lines.skip(1).toList();
    final goodsList = <Goods>[];

    for (final line in dataLines) {
      if (line.trim().isEmpty) continue;
      final fields = _parseCsvLine(line);
      if (fields.length < 6) continue;

      final now = DateTime.now();
      goodsList.add(Goods(
        barcode: fields[0],
        goodsName: fields[1],
        brand: fields[2].isNotEmpty ? fields[2] : null,
        spec: fields[3].isNotEmpty ? fields[3] : null,
        purchasePrice: fields[4].isNotEmpty ? double.tryParse(fields[4]) : null,
        sellPrice: double.tryParse(fields[5]) ?? 0,
        remark: fields.length > 6 && fields[6].isNotEmpty ? fields[6] : null,
        createTime: now,
        updateTime: now,
      ));
    }

    return goodsList;
  }

  /// 标准化字段名（兼容不同来源的数据）
  void _normalizeFieldNames(Map<String, dynamic> map) {
    final fieldMappings = {
      'goods_name': ['name', 'productName', 'title', '商品名称'],
      'barcode': ['code', 'ean', 'sku', '条码'],
      'brand': ['trademark', 'manufacturer', '品牌'],
      'spec': ['specification', 'standard', '规格'],
      'goods_img': ['img', 'image', 'pic', 'imageUrl', 'photo'],
      'purchase_price': ['cost', 'buyPrice', '进货价'],
      'sell_price': ['price', 'salePrice', '售价'],
      'remark': ['notes', 'comment', '备注'],
    };

    for (final entry in fieldMappings.entries) {
      final targetKey = entry.key;
      if (map.containsKey(targetKey)) continue;

      for (final altKey in entry.value) {
        if (map.containsKey(altKey)) {
          map[targetKey] = map[altKey];
          break;
        }
      }
    }

    // 确保时间字段存在
    if (!map.containsKey('create_time')) {
      map['create_time'] = DateTime.now().toIso8601String();
    }
    if (!map.containsKey('update_time')) {
      map['update_time'] = DateTime.now().toIso8601String();
    }
  }

  /// 解析 CSV 行（处理引号包裹的字段）
  List<String> _parseCsvLine(String line) {
    final result = <String>[];
    final buffer = StringBuffer();
    bool inQuotes = false;

    for (int i = 0; i < line.length; i++) {
      final char = line[i];

      if (char == '"') {
        if (inQuotes && i + 1 < line.length && line[i + 1] == '"') {
          buffer.write('"');
          i++; // 跳过下一个引号
        } else {
          inQuotes = !inQuotes;
        }
      } else if (char == ',' && !inQuotes) {
        result.add(buffer.toString());
        buffer.clear();
      } else {
        buffer.write(char);
      }
    }

    result.add(buffer.toString());
    return result;
  }
}
