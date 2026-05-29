import 'dart:convert';
import 'dart:developer' as developer;
import 'package:http/http.dart' as http;

class BarcodeInfo {
  final String? goodsName;
  final String? brand;
  final String? spec;
  final String? imageUrl;
  final bool found;

  BarcodeInfo({
    this.goodsName,
    this.brand,
    this.spec,
    this.imageUrl,
    required this.found,
  });

  @override
  String toString() {
    return 'BarcodeInfo{found: $found, name: $goodsName, brand: $brand, spec: $spec}';
  }
}

class BarcodeService {
  static const String _baichuanApi = 'https://api.baichuanhui.com/barcode/';
  static const String _backupApi = 'https://api.bitfu.cn/barcode/';

  /// 查询条码信息
  /// 依次调用两个API，返回第一个成功的结果
  Future<BarcodeInfo> queryBarcode(String barcode) async {
    developer.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━', name: 'BarcodeService');
    developer.log('🔍 开始查询条码: $barcode', name: 'BarcodeService');

    // 尝试主API
    developer.log('📡 尝试主API: $_baichuanApi$barcode', name: 'BarcodeService');
    try {
      final result = await _queryWithTimeout(_baichuanApi, barcode);
      if (result.found) {
        developer.log('✅ 主API查询成功: $result', name: 'BarcodeService');
        return result;
      }
      developer.log('⚠️ 主API返回未找到', name: 'BarcodeService');
    } catch (e, stack) {
      developer.log('❌ 主API异常: $e', name: 'BarcodeService', error: e, stackTrace: stack);
    }

    // 尝试备用API
    developer.log('📡 尝试备用API: $_backupApi$barcode', name: 'BarcodeService');
    try {
      final result = await _queryWithTimeout(_backupApi, barcode);
      if (result.found) {
        developer.log('✅ 备用API查询成功: $result', name: 'BarcodeService');
        return result;
      }
      developer.log('⚠️ 备用API返回未找到', name: 'BarcodeService');
    } catch (e, stack) {
      developer.log('❌ 备用API异常: $e', name: 'BarcodeService', error: e, stackTrace: stack);
    }

    developer.log('🚫 所有API均不可用，返回未找到', name: 'BarcodeService');
    developer.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━', name: 'BarcodeService');
    return BarcodeInfo(found: false);
  }

  Future<BarcodeInfo> _queryWithTimeout(String baseUrl, String barcode) async {
    final uri = Uri.parse('$baseUrl$barcode');
    developer.log('➡️ 发送请求: $uri', name: 'BarcodeService');

    final response = await http
        .get(uri, headers: {
          'Accept': 'application/json',
          'User-Agent': 'StorePriceApp/1.0',
        })
        .timeout(const Duration(seconds: 5));

    developer.log('⬅️ 响应状态码: ${response.statusCode}', name: 'BarcodeService');
    developer.log('⬅️ 响应体: ${response.body}', name: 'BarcodeService');

    if (response.statusCode == 200) {
      final data = json.decode(response.body);

      if (data['code'] == 200 || data['status'] == 'ok') {
        final result = data['data'] ?? data['result'] ?? data;
        if (result != null && result is Map) {
          final info = BarcodeInfo(
            goodsName: _extractString(result, ['name', 'goodsName', 'title', 'productName']),
            brand: _extractString(result, ['brand', 'trademark', 'manufacturer']),
            spec: _extractString(result, ['spec', 'specification', 'standard', 'netContent', 'weight']),
            imageUrl: _extractString(result, ['img', 'image', 'pic', 'imageUrl', 'photo']),
            found: true,
          );
          developer.log('✅ 解析结果: $info', name: 'BarcodeService');
          return info;
        }
      }
    }

    developer.log('⚠️ 响应未包含有效商品数据', name: 'BarcodeService');
    return BarcodeInfo(found: false);
  }

  String? _extractString(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value != null && value.toString().isNotEmpty) {
        return value.toString();
      }
    }
    return null;
  }
}
