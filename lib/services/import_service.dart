import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import '../database/db_helper.dart';
import '../models/goods.dart';

class ImportService {
  /// 支持的文件格式
  static const List<String> supportedExtensions = ['zip', 'json', 'csv'];

  /// 选择并导入文件
  /// [conflictStrategy] 冲突处理策略: 'skip', 'overwrite', 'merge'
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
      int copiedImages = 0;
      int failedImages = 0;

      if (ext == 'zip') {
        final zipResult = await _importFromZip(filePath);
        goodsList = zipResult['goodsList'] as List<Goods>;
        copiedImages = zipResult['copiedImages'] as int;
        failedImages = zipResult['failedImages'] as int;
      } else if (ext == 'json') {
        goodsList = await _parseJsonFile(filePath);
      } else if (ext == 'csv') {
        goodsList = await _parseCsvFile(filePath);
      } else {
        return {'success': false, 'message': '不支持的文件格式: .$ext'};
      }

      if (goodsList.isEmpty) {
        return {'success': false, 'message': '文件中没有找到商品数据'};
      }

      // 校验数据
      final validationResult = _validateGoodsList(goodsList);
      final validList = validationResult['valid'] as List<Goods>;
      final invalidList = validationResult['invalid'] as List<Map<String, dynamic>>;

      if (validList.isEmpty) {
        return {
          'success': false,
          'message': '导入失败：所有数据均校验不通过\n\n共 ${invalidList.length} 条错误:\n${_formatInvalidList(invalidList)}',
        };
      }

      // 导入到数据库
      final db = DBHelper();
      final importResult = await db.importGoods(
        validList,
        conflictStrategy: conflictStrategy,
      );

      final message = StringBuffer();
      message.writeln('导入完成');
      message.writeln('新增: ${importResult['inserted']} 条');
      message.writeln('更新: ${importResult['updated']} 条');
      message.writeln('跳过: ${importResult['skipped']} 条');
      if (copiedImages > 0 || failedImages > 0) {
        message.writeln('图片导入: 成功 $copiedImages 张, 失败 $failedImages 张');
      }
      if (invalidList.isNotEmpty) {
        message.writeln('\n${invalidList.length} 条数据校验失败（已跳过）:');
        message.write(_formatInvalidList(invalidList, maxLines: 5));
      }

      return {
        'success': true,
        'message': message.toString(),
        'result': importResult,
      };
    } catch (e) {
      return {'success': false, 'message': '导入失败: $e'};
    }
  }

  // ==================== ZIP 导入 ====================

  Future<Map<String, dynamic>> _importFromZip(String zipPath) async {
    // 解压到临时目录
    final tempDir = await Directory.systemTemp.createTemp('import_');
    try {
      await extractFileToDisk(zipPath, tempDir.path);

      // 查找数据文件（优先 JSON）
      final jsonFile = File('${tempDir.path}/data.json');
      final List<Goods> goodsList;
      if (await jsonFile.exists()) {
        goodsList = await _parseJsonFile(jsonFile.path);
      } else {
        // 尝试找任意 json 文件
        final jsonFiles = tempDir
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.json'))
            .toList();
        if (jsonFiles.isEmpty) {
          throw Exception('zip 中未找到 data.json 或任何 JSON 文件');
        }
        goodsList = await _parseJsonFile(jsonFiles.first.path);
      }

      // 处理图片：复制 images/ 目录下的图片到本机应用目录
      final imagesDir = Directory('${tempDir.path}/images');
      int copiedImages = 0;
      int failedImages = 0;

      if (await imagesDir.exists()) {
        final appDir = await getApplicationDocumentsDirectory();
        final targetDir = Directory('${appDir.path}/goods_images');
        if (!await targetDir.exists()) {
          await targetDir.create(recursive: true);
        }

        for (final goods in goodsList) {
          final imgPath = goods.goodsImg;
          if (imgPath == null || imgPath.isEmpty) continue;

          // 只处理相对路径（zip 导出的格式）
          if (imgPath.startsWith('images/')) {
            final fileName = imgPath.split('/').last;
            final srcFile = File('${imagesDir.path}/$fileName');
            if (await srcFile.exists()) {
              final destFile = File('${targetDir.path}/$fileName');
              // 避免文件名冲突
              final finalDest = await _ensureUniqueName(destFile);
              await srcFile.copy(finalDest.path);
              goods.goodsImg = finalDest.path;
              copiedImages++;
            } else {
              goods.goodsImg = null;
              failedImages++;
            }
          }
          // http 开头的 URL 保持不变
        }
      }

      return {
        'goodsList': goodsList,
        'copiedImages': copiedImages,
        'failedImages': failedImages,
      };
    } finally {
      // 清理临时目录
      await tempDir.delete(recursive: true);
    }
  }

  /// 确保文件名不冲突，若存在则加数字后缀
  Future<File> _ensureUniqueName(File file) async {
    if (!await file.exists()) return file;

    final dir = file.parent.path;
    final name = file.path.split('/').last;
    final dotIndex = name.lastIndexOf('.');
    final baseName = dotIndex > 0 ? name.substring(0, dotIndex) : name;
    final ext = dotIndex > 0 ? name.substring(dotIndex) : '';

    int counter = 1;
    while (true) {
      final newPath = '$dir/${baseName}_$counter$ext';
      final newFile = File(newPath);
      if (!await newFile.exists()) return newFile;
      counter++;
    }
  }

  // ==================== JSON / CSV 解析 ====================

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

    final result = <Goods>[];
    for (final item in goodsArray.whereType<Map>()) {
      final map = Map<String, dynamic>.from(item);
      _normalizeFieldNames(map);
      _processImportedImagePath(map);
      result.add(Goods.fromMap(map));
    }
    return result;
  }

  Future<List<Goods>> _parseCsvFile(String filePath) async {
    final file = File(filePath);
    final lines = await file.readAsLines();

    if (lines.isEmpty) return [];

    final dataLines = lines.skip(1).toList();
    final goodsList = <Goods>[];

    for (final line in dataLines) {
      if (line.trim().isEmpty) continue;
      final fields = _parseCsvLine(line);
      if (fields.length < 7) continue;

      final now = DateTime.now();
      String? goodsImg = fields[4].isNotEmpty ? fields[4] : null;
      // CSV 导入：本地路径清空，URL 保留
      if (goodsImg != null) {
        if (goodsImg.startsWith('/') || goodsImg.startsWith('images/')) {
          goodsImg = null;
        }
        // http 开头的 URL 保持不变
      }

      goodsList.add(Goods(
        barcode: fields[0],
        goodsName: fields[1],
        brand: fields[2].isNotEmpty ? fields[2] : null,
        spec: fields[3].isNotEmpty ? fields[3] : null,
        goodsImg: goodsImg,
        purchasePrice: fields[5].isNotEmpty ? double.tryParse(fields[5]) : null,
        sellPrice: double.tryParse(fields[6]) ?? 0,
        remark: fields.length > 7 && fields[7].isNotEmpty ? fields[7] : null,
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
      'goods_img': ['img', 'image', 'pic', 'imageUrl', 'photo', '商品图片'],
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

  /// 处理导入数据中的图片路径：
  /// - 以 images/ 开头的相对路径 → 保留，由 zip 导入逻辑处理
  /// - / 开头的本地绝对路径 → 清空（从别的手机导入的路径在此无效）
  /// - http 开头的 URL → 保持不变
  void _processImportedImagePath(Map<String, dynamic> map) {
    final imgValue = map['goods_img'];
    if (imgValue == null || imgValue.toString().isEmpty) return;

    final imgStr = imgValue.toString();

    if (imgStr.startsWith('/')) {
      // 本地绝对路径，在此手机无效
      map['goods_img'] = null;
    }
    // images/ 开头的相对路径：由 zip 导入逻辑处理
    // http 开头的 URL：保持不变
  }

  // ==================== 数据校验 ====================

  Map<String, dynamic> _validateGoodsList(List<Goods> goodsList) {
    final valid = <Goods>[];
    final invalid = <Map<String, dynamic>>[];

    for (int i = 0; i < goodsList.length; i++) {
      final goods = goodsList[i];
      final errors = <String>[];

      // 条码校验
      final barcode = goods.barcode.trim();
      if (barcode.isEmpty) {
        errors.add('条码不能为空');
      } else if (barcode.startsWith('sd')) {
        final numPart = barcode.substring(2);
        if (!RegExp(r'^[0-9]{8}$').hasMatch(numPart)) {
          errors.add('内部编号格式错误，应为 sd + 8位数字');
        }
      } else if (!RegExp(r'^[0-9]+$').hasMatch(barcode)) {
        errors.add('条码只能包含数字');
      } else {
        final len = barcode.length;
        if (len != 8 && len != 12 && len != 13 && len != 14) {
          errors.add('条码长度应为 8/12/13/14 位');
        }
      }

      // 商品名称校验
      if (goods.goodsName.trim().isEmpty) {
        errors.add('商品名称不能为空');
      } else if (goods.goodsName.trim().length > 200) {
        errors.add('商品名称过长（最多200字符）');
      }

      // 售价校验
      if (goods.sellPrice <= 0) {
        errors.add('售价必须大于0');
      }
      if (goods.sellPrice > 999999) {
        errors.add('售价超出合理范围');
      }

      // 进货价校验
      if (goods.purchasePrice != null && goods.purchasePrice! < 0) {
        errors.add('进货价不能为负数');
      }

      if (errors.isEmpty) {
        valid.add(goods);
      } else {
        invalid.add({
          'index': i + 1,
          'barcode': goods.barcode,
          'name': goods.goodsName,
          'errors': errors,
        });
      }
    }

    return {'valid': valid, 'invalid': invalid};
  }

  String _formatInvalidList(List<Map<String, dynamic>> invalidList, {int maxLines = 100}) {
    final buffer = StringBuffer();
    for (int i = 0; i < invalidList.length && i < maxLines; i++) {
      final item = invalidList[i];
      buffer.writeln(
          '第${item['index']}行 ${item['name']}(${item['barcode']}): ${(item['errors'] as List<String>).join(', ')}');
    }
    if (invalidList.length > maxLines) {
      buffer.writeln('... 还有 ${invalidList.length - maxLines} 条');
    }
    return buffer.toString();
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
