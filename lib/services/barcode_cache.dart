import 'barcode_service.dart';

/// 条码查询结果内存缓存
/// 最多缓存 100 条，避免短时间内重复请求 API
class BarcodeCache {
  static final BarcodeCache _instance = BarcodeCache._internal();
  factory BarcodeCache() => _instance;
  BarcodeCache._internal();

  final Map<String, _CacheEntry> _cache = {};
  final int _maxSize = 100;

  /// 缓存有效期（24小时）
  static const Duration _ttl = Duration(hours: 24);

  BarcodeInfo? get(String barcode) {
    final entry = _cache[barcode];
    if (entry == null) return null;
    if (DateTime.now().difference(entry.timestamp) > _ttl) {
      _cache.remove(barcode);
      return null;
    }
    return entry.data;
  }

  void set(String barcode, BarcodeInfo data) {
    if (_cache.length >= _maxSize) {
      // 淘汰最旧的条目
      final oldest = _cache.entries.reduce(
        (a, b) => a.value.timestamp.isBefore(b.value.timestamp) ? a : b,
      );
      _cache.remove(oldest.key);
    }
    _cache[barcode] = _CacheEntry(data: data, timestamp: DateTime.now());
  }

  void clear() => _cache.clear();
}

class _CacheEntry {
  final BarcodeInfo data;
  final DateTime timestamp;

  _CacheEntry({required this.data, required this.timestamp});
}
