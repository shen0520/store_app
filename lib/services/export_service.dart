import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../database/db_helper.dart';
import '../models/goods.dart';

class ExportService {
  static const String _exportFileName = 'store_goods_export';

  /// 获取导出目录，优先使用外部存储的 Download 目录
  Future<Directory> _getExportDirectory() async {
    // 尝试外部存储 Download 目录
    if (Platform.isAndroid) {
      final extDir = await getExternalStorageDirectory();
      if (extDir != null) {
        final downloadDir = Directory('${extDir.path}/Download');
        if (!await downloadDir.exists()) {
          await downloadDir.create(recursive: true);
        }
        return downloadDir;
      }
    }
    // 回退到应用文档目录
    return await getApplicationDocumentsDirectory();
  }

  /// 导出全部商品为 JSON 文件
  /// 返回导出文件的路径
  Future<String> exportToJson() async {
    final db = DBHelper();
    final rawData = await db.exportAllGoods();
    final goodsList = rawData.map((e) => Goods.fromMap(e)).toList();

    final exportData = {
      'export_time': DateTime.now().toIso8601String(),
      'app_name': '小店扫码查价',
      'app_version': '1.0.0',
      'total_count': goodsList.length,
      'goods': goodsList.map((g) => g.toMap()).toList(),
    };

    final jsonStr = const JsonEncoder.withIndent('  ').convert(exportData);

    final dir = await _getExportDirectory();
    final timeStr = _formatDateTime(DateTime.now());
    final filePath = '${dir.path}/${_exportFileName}_$timeStr.json';
    final file = File(filePath);
    await file.writeAsString(jsonStr);

    return filePath;
  }

  /// 导出全部商品为 CSV 文件
  /// 返回导出文件的路径
  Future<String> exportToCsv() async {
    final db = DBHelper();
    final rawData = await db.exportAllGoods();
    final goodsList = rawData.map((e) => Goods.fromMap(e)).toList();

    // CSV 表头
    final headers = [
      '条码',
      '商品名称',
      '品牌',
      '规格',
      '进货价',
      '本店售价',
      '备注',
      '创建时间',
      '更新时间',
    ];

    final buffer = StringBuffer();
    buffer.writeln(headers.join(','));

    for (final goods in goodsList) {
      final row = [
        _escapeCsv(goods.barcode),
        _escapeCsv(goods.goodsName),
        _escapeCsv(goods.brand ?? ''),
        _escapeCsv(goods.spec ?? ''),
        goods.purchasePrice?.toString() ?? '',
        goods.sellPrice.toString(),
        _escapeCsv(goods.remark ?? ''),
        goods.createTime.toIso8601String(),
        goods.updateTime.toIso8601String(),
      ];
      buffer.writeln(row.join(','));
    }

    final dir = await _getExportDirectory();
    final timeStr = _formatDateTime(DateTime.now());
    final filePath = '${dir.path}/${_exportFileName}_$timeStr.csv';
    final file = File(filePath);
    await file.writeAsString(buffer.toString());

    return filePath;
  }

  /// 分享导出文件
  Future<void> shareExportedFile(String filePath) async {
    await Share.shareXFiles(
      [XFile(filePath)],
      text: '小店扫码查价 - 商品数据备份',
    );
  }

  /// CSV 特殊字符转义
  String _escapeCsv(String value) {
    if (value.contains(',') || value.contains('"') || value.contains('\n')) {
      return '"${value.replaceAll('"', '""')}"';
    }
    return value;
  }

  /// 格式化日期时间为文件名格式
  String _formatDateTime(DateTime dt) {
    return '${dt.year}${_pad(dt.month)}${_pad(dt.day)}_${_pad(dt.hour)}${_pad(dt.minute)}${_pad(dt.second)}';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}
