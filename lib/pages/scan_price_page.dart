import 'package:flutter/material.dart';
import 'scan_page.dart';
import '../database/db_helper.dart';
import '../models/goods.dart';
import '../utils/app_colors.dart';
import 'add_goods_page.dart';

class ScanPricePage extends StatefulWidget {
  const ScanPricePage({super.key});

  @override
  State<ScanPricePage> createState() => _ScanPricePageState();
}

class _ScanPricePageState extends State<ScanPricePage> {
  final _db = DBHelper();
  Goods? _currentGoods;
  bool _isScanning = false;
  bool _notFound = false;
  String _lastBarcode = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scanBarcode());
  }

  Future<void> _scanBarcode() async {
    if (_isScanning) return;
    setState(() {
      _isScanning = true;
      _currentGoods = null;
      _notFound = false;
    });

    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScanPage()),
    );

    if (result != null && result.isNotEmpty) {
      _lastBarcode = result;
      await _lookupPrice(result);
    }

    if (mounted) {
      setState(() => _isScanning = false);
    }
  }

  Future<void> _lookupPrice(String barcode) async {
    final goods = await _db.getGoodsByBarcode(barcode);
    if (mounted) {
      setState(() {
        if (goods != null) {
          _currentGoods = goods;
          _notFound = false;
        } else {
          _currentGoods = null;
          _notFound = true;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text('快速扫码查价',
            style: TextStyle(color: Colors.white, fontSize: 18)),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: _buildBody(),
      floatingActionButton: _currentGoods != null || _notFound
          ? FloatingActionButton.extended(
              onPressed: _scanBarcode,
              backgroundColor: AppColors.primary,
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('继续扫码'),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildBody() {
    if (_isScanning && _currentGoods == null && !_notFound) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppColors.primary),
            SizedBox(height: 16),
            Text('正在扫码...', style: TextStyle(color: AppColors.textSecondary)),
          ],
        ),
      );
    }

    if (_currentGoods != null) {
      return _buildGoodsDisplay(_currentGoods!);
    }

    if (_notFound) {
      return _buildNotFound();
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.qr_code_scanner,
              size: 80, color: AppColors.textMuted),
          const SizedBox(height: 20),
          const Text(
            '点击下方按钮开始扫码',
            style: TextStyle(fontSize: 18, color: AppColors.textSecondary),
          ),
          const SizedBox(height: 40),
          ElevatedButton.icon(
            onPressed: _scanBarcode,
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('开始扫码', style: TextStyle(fontSize: 18)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 40, vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGoodsDisplay(Goods goods) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          const SizedBox(height: 20),
          // 商品图片
          Container(
            width: 220,
            height: 220,
            decoration: BoxDecoration(
              color: AppColors.cardBg,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: goods.goodsImg != null && goods.goodsImg!.isNotEmpty
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.network(
                      goods.goodsImg!,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => _buildImagePlaceholder(),
                    ),
                  )
                : _buildImagePlaceholder(),
          ),
          const SizedBox(height: 32),
          // 商品名称
          Text(
            goods.goodsName,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          // 品牌规格
          if (goods.brand != null || goods.spec != null)
            Text(
              '${goods.brand ?? ''} ${goods.spec ?? ''}'.trim(),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                color: AppColors.textSecondary,
              ),
            ),
          const SizedBox(height: 40),
          // 条码
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.cardBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              '条码: ${goods.barcode}',
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textMuted,
              ),
            ),
          ),
          const SizedBox(height: 40),
          // 本店售价 - 超大字橙色
          const Text(
            '本店售价',
            style: TextStyle(
              fontSize: 18,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '¥${goods.sellPrice.toStringAsFixed(2)}',
            style: const TextStyle(
              fontSize: 64,
              fontWeight: FontWeight.bold,
              color: AppColors.accent,
            ),
          ),
          const SizedBox(height: 60),
        ],
      ),
    );
  }

  Widget _buildImagePlaceholder() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.image_not_supported,
              size: 50, color: AppColors.textMuted),
          SizedBox(height: 8),
          Text('暂无图片', style: TextStyle(color: AppColors.textMuted)),
        ],
      ),
    );
  }

  Widget _buildNotFound() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.search_off, size: 80, color: AppColors.textMuted),
          const SizedBox(height: 20),
          const Text(
            '该商品未录入本店价格',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '条码: $_lastBarcode',
            style: const TextStyle(
              fontSize: 14,
              color: AppColors.textMuted,
            ),
          ),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => AddGoodsPage(initialBarcode: _lastBarcode),
                ),
              ).then((result) {
                if (result == true) {
                  _lookupPrice(_lastBarcode);
                }
              });
            },
            icon: const Icon(Icons.add),
            label: const Text('前往录入', style: TextStyle(fontSize: 16)),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.accent,
              foregroundColor: Colors.white,
              padding:
                  const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
