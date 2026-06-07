import 'dart:convert';
import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../database/db_helper.dart';

class ExportService {
  static const String _exportFileName = 'store_goods_export';

  /// 获取导出目录，优先使用外部存储的 Download 目录
  Future<Directory> _getExportDirectory() async {
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
    return await getApplicationDocumentsDirectory();
  }

  /// 导出全部商品为 zip 压缩包（含 JSON 数据 + images/ 图片）
  /// [onProgress] 回调 (current, total)
  /// 返回 zip 文件路径
  Future<String> exportToZip({
    void Function(int current, int total)? onProgress,
  }) async {
    final db = DBHelper();
    final rawData = await db.exportAllGoods();
    final total = rawData.length;

    if (total == 0) {
      throw Exception('没有商品数据可导出');
    }

    // 创建临时目录
    final tempDir = await Directory.systemTemp.createTemp('export_');
    final imagesDir = Directory('${tempDir.path}/images');
    await imagesDir.create(recursive: true);

    int missingImages = 0;

    // 构建 JSON 数据（图片路径改为相对路径）
    final goodsArray = <Map<String, dynamic>>[];
    for (int i = 0; i < total; i++) {
      final map = Map<String, dynamic>.from(rawData[i]);

      // 处理图片路径
      final imgPath = map['goods_img']?.toString();
      if (imgPath != null && imgPath.isNotEmpty) {
        if (imgPath.startsWith('/')) {
          // 本地图片：复制到临时 images 目录，路径改为相对路径
          final file = File(imgPath);
          if (await file.exists()) {
            final fileName = _safeFileName(imgPath);
            final destFile = File('${imagesDir.path}/$fileName');
            await file.copy(destFile.path);
            map['goods_img'] = 'images/$fileName';
          } else {
            map['goods_img'] = null;
            missingImages++;
          }
        }
        // http 开头的 URL 保持不变
      }

      goodsArray.add(map);

      if (onProgress != null && (i + 1) % 500 == 0) {
        onProgress(i + 1, total);
      }
    }

    // 写入 JSON 文件（紧凑格式，无缩进）
    final exportData = {
      'export_time': DateTime.now().toIso8601String(),
      'app_name': '小店扫码查价',
      'app_version': '1.0.0',
      'total_count': total,
      'goods': goodsArray,
    };

    final jsonFile = File('${tempDir.path}/data.json');
    await jsonFile.writeAsString(jsonEncode(exportData));

    // 打包为 zip
    final dir = await _getExportDirectory();
    final timeStr = _formatDateTime(DateTime.now());
    final zipPath = '${dir.path}/${_exportFileName}_$timeStr.zip';

    await _createZip(tempDir.path, zipPath);

    // 清理临时目录
    await tempDir.delete(recursive: true);

    return zipPath;
  }

  /// 将目录打包为 zip 文件
  Future<void> _createZip(String sourceDir, String zipPath) async {
    final encoder = ZipFileEncoder();
    encoder.create(zipPath);
    await encoder.addDirectory(Directory(sourceDir));
    encoder.close();
  }

  /// 分享导出的 zip 文件
  Future<void> shareExportedFile(String filePath) async {
    await Share.shareXFiles(
      [XFile(filePath)],
      text: '小店扫码查价 - 商品数据备份',
    );
  }

  /// 从文件路径提取安全的文件名
  String _safeFileName(String path) {
    final name = path.split('/').last;
    // 如果文件名重复风险高，可以加时间戳
    return name;
  }

  String _formatDateTime(DateTime dt) {
    return '${dt.year}${_pad(dt.month)}${_pad(dt.day)}_${_pad(dt.hour)}${_pad(dt.minute)}${_pad(dt.second)}';
  }

  String _pad(int n) => n.toString().padLeft(2, '0');
}
