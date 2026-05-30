import 'package:flutter/material.dart';
import '../database/db_helper.dart';
import '../models/goods.dart';

/// 全局商品状态管理
/// 负责商品列表的增删改查、分页加载、搜索
class GoodsProvider extends ChangeNotifier {
  final DBHelper _db = DBHelper();

  List<Goods> _goodsList = [];
  bool _isLoading = false;
  bool _isLoadingMore = false;
  String? _searchQuery;
  int _currentPage = 0;
  final int _pageSize = 30;
  bool _hasMore = true;

  List<Goods> get goodsList => _goodsList;
  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMore => _hasMore;
  String? get searchQuery => _searchQuery;

  /// 初始加载或刷新
  Future<void> loadGoods({bool refresh = false}) async {
    if (_isLoading) return;

    _isLoading = true;
    _currentPage = 0;
    _hasMore = true;
    if (refresh) {
      // 延迟通知，避免 build 阶段调用 setState
      WidgetsBinding.instance.addPostFrameCallback((_) => notifyListeners());
    } else {
      notifyListeners();
    }

    try {
      final list = await _db.getAllGoods(
        searchQuery: _searchQuery,
        limit: _pageSize,
        offset: 0,
      );
      _goodsList = list;
      _hasMore = list.length >= _pageSize;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// 上拉加载更多
  Future<void> loadMore() async {
    if (_isLoadingMore || !_hasMore) return;

    _isLoadingMore = true;
    notifyListeners();

    try {
      _currentPage++;
      final list = await _db.getAllGoods(
        searchQuery: _searchQuery,
        limit: _pageSize,
        offset: _currentPage * _pageSize,
      );
      if (list.isEmpty) {
        _hasMore = false;
      } else {
        _goodsList.addAll(list);
        _hasMore = list.length >= _pageSize;
      }
    } finally {
      _isLoadingMore = false;
      notifyListeners();
    }
  }

  /// 搜索（会触发重新加载）
  Future<void> search(String query) async {
    _searchQuery = query.trim().isEmpty ? null : query.trim();
    await loadGoods();
  }

  /// 新增商品
  Future<void> addGoods(Goods goods) async {
    await _db.insertGoods(goods);
    // 插入新商品到列表头部
    _goodsList.insert(0, goods);
    notifyListeners();
  }

  /// 更新商品
  Future<void> updateGoods(Goods goods) async {
    await _db.updateGoods(goods);
    final index = _goodsList.indexWhere((g) => g.id == goods.id);
    if (index != -1) {
      _goodsList[index] = goods;
      notifyListeners();
    }
  }

  /// 删除商品
  Future<void> deleteGoods(int id) async {
    await _db.deleteGoods(id);
    _goodsList.removeWhere((g) => g.id == id);
    notifyListeners();
  }

  /// 获取商品总数
  Future<int> getGoodsCount() async {
    return await _db.getGoodsCount();
  }

  /// 清空全部数据
  Future<void> clearAllGoods() async {
    await _db.clearAllGoods();
    _goodsList = [];
    _hasMore = false;
    notifyListeners();
  }

  /// 导入商品
  Future<Map<String, int>> importGoods(
    List<Goods> goodsList, {
    String conflictStrategy = 'skip',
  }) async {
    final result = await _db.importGoods(goodsList, conflictStrategy: conflictStrategy);
    await loadGoods(refresh: true);
    return result;
  }

  @override
  void dispose() {
    _db.close();
    super.dispose();
  }
}
