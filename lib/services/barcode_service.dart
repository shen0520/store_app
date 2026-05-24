import 'dart:convert';
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
}

class BarcodeService {
  static const String _baichuanApi = 'https://api.baichuanhui.com/barcode/';
  static const String _backupApi = 'https://api.bitfu.cn/barcode/';

  Future<BarcodeInfo> queryBarcode(String barcode) async {
    try {
      final result = await _queryWithTimeout(_baichuanApi, barcode);
      if (result.found) return result;
    } catch (_) {}

    try {
      final result = await _queryWithTimeout(_backupApi, barcode);
      if (result.found) return result;
    } catch (_) {}

    return BarcodeInfo(found: false);
  }

  Future<BarcodeInfo> _queryWithTimeout(String baseUrl, String barcode) async {
    final uri = Uri.parse('$baseUrl$barcode');
    final response = await http
        .get(uri, headers: {
          'Accept': 'application/json',
          'User-Agent': 'StorePriceApp/1.0',
        })
        .timeout(const Duration(seconds: 5));

    if (response.statusCode == 200) {
      final data = json.decode(response.body);

      if (data['code'] == 200 || data['status'] == 'ok') {
        final result = data['data'] ?? data['result'] ?? data;
        if (result != null) {
          return BarcodeInfo(
            goodsName: _extractString(result, ['name', 'goodsName', 'title', 'productName']),
            brand: _extractString(result, ['brand', 'trademark', 'manufacturer']),
            spec: _extractString(result, ['spec', 'specification', 'standard', 'netContent', 'weight']),
            imageUrl: _extractString(result, ['img', 'image', 'pic', 'imageUrl', 'photo']),
            found: true,
          );
        }
      }
    }

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
