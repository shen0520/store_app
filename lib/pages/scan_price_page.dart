import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'scan_page.dart';
import '../database/db_helper.dart';
import '../models/goods.dart';
import '../utils/app_colors.dart';
import '../widgets/goods_image.dart';
import 'add_goods_page.dart';

class ScanPricePage extends StatefulWidget {
  const ScanPricePage({super.key});

  @override
  State<ScanPricePage> createState() => _ScanPricePageState();
}

class _ScanPricePageState extends State<ScanPricePage> {
  final _db = DBHelper();
  final _flutterTts = FlutterTts();

  Goods? _currentGoods;
  bool _isScanning = false;
  bool _notFound = false;
  bool _continuousMode = false;
  String _lastBarcode = '';

  @override
  void initState() {
    super.initState();
    _initTts();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scanBarcode());
  }

  Future<void> _initTts() async {
    await _flutterTts.setLanguage('zh-CN');
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.setVolume(1.0);
    await _flutterTts.setPitch(1.0);
  }

  Future<void> _speakPrice(Goods goods) async {
    final text = '${goods.goodsName}，售价${goods.sellPrice.toStringAsFixed(0)}元';
    await _flutterTts.speak(text);
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

    // 记录扫码历史
    await _db.insertScanHistory(
      barcode: barcode,
      goodsName: goods?.goodsName,
      sellPrice: goods?.sellPrice,
    );

    // 语音播报
    if (goods != null) {
      await _speakPrice(goods);
    }

    // 连续扫描模式：延迟后自动继续
    if (_continuousMode && mounted && goods != null) {
      await Future.delayed(const Duration(milliseconds: 1500));
      if (mounted) {
        await _scanBarcode();
      }
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
      floatingActionButton: _buildFloatingButtons(),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget? _buildFloatingButtons() {
    if (_isScanning) return null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 连续扫描开关
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(width: 12),
                const Icon(Icons.repeat, size: 18, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                const Text('连续扫描', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
                Switch(
                  value: _continuousMode,
                  activeColor: AppColors.primary,
                  onChanged: (value) => setState(() => _continuousMode = value),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FloatingActionButton.extended(
            onPressed: _scanBarcode,
            backgroundColor: AppColors.primary,
            icon: const Icon(Icons.qr_code_scanner),
            label: Text(_currentGoods != null || _notFound ? '继续扫码' : '开始扫码'),
          ),
        ],
      ),
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

    return _buildInitialState();
  }

  Widget _buildInitialState() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _db.getScanHistory(limit: 10),
      builder: (context, snapshot) {
        final history = snapshot.data ?? [];
        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const SizedBox(height: 40),
              const Icon(Icons.qr_code_scanner,
                  size: 80, color: AppColors.textMuted),
              const SizedBox(height: 20),
              const Text(
                '点击下方按钮开始扫码',
                style: TextStyle(fontSize: 18, color: AppColors.textSecondary),
              ),
              const SizedBox(height: 40),
              if (history.isNotEmpty) ...[
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '最近查询',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ...history.map((item) => _buildHistoryItem(item)),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildHistoryItem(Map<String, dynamic> item) {
    final goodsName = item['goods_name'] as String? ?? '未知商品';
    final sellPrice = item['sell_price'] as double?;
    final barcode = item['barcode'] as String;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: AppColors.cardBg,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      child: ListTile(
        onTap: () async {
          _lastBarcode = barcode;
          await _lookupPrice(barcode);
        },
        title: Text(
          goodsName,
          style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          '条码: $barcode',
          style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
        ),
        trailing: sellPrice != null
            ? Text(
                '¥${sellPrice.toStringAsFixed(2)}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.accent,
                ),
              )
            : const Text(
                '未录入',
                style: TextStyle(fontSize: 13, color: AppColors.textMuted),
              ),
      ),
    );
  }

  Widget _buildGoodsDisplay(Goods goods) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 商品图片 - 顶部居中
          Center(
            child: Container(
              width: 200,
              height: 200,
              decoration: BoxDecoration(
                color: AppColors.cardBg,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.border),
              ),
              child: GoodsImage(
                imagePath: goods.goodsImg,
                width: 200,
                height: 200,
                fit: BoxFit.cover,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 24),
          // 商品名称
          Text(
            goods.goodsName,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 6),
          // 品牌规格
          if (goods.brand != null || goods.spec != null)
            Text(
              '${goods.brand ?? ''} ${goods.spec ?? ''}'.trim(),
              style: const TextStyle(
                fontSize: 15,
                color: AppColors.textSecondary,
              ),
            ),
          const SizedBox(height: 20),
          // 信息卡片区域
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.cardBg,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildInfoRow('条码', goods.barcode),
                if (goods.purchasePrice != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: _buildInfoRow('进货价', '¥${goods.purchasePrice!.toStringAsFixed(2)}'),
                  ),
                if (goods.remark != null && goods.remark!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: _buildInfoRow('备注', goods.remark!),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          // 售价区域 - 居中突出
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 24),
            decoration: BoxDecoration(
              color: AppColors.accent.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.accent.withOpacity(0.2)),
            ),
            child: Column(
              children: [
                const Text(
                  '本店售价',
                  style: TextStyle(
                    fontSize: 16,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '¥${goods.sellPrice.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 56,
                    fontWeight: FontWeight.bold,
                    color: AppColors.accent,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$label: ',
          style: const TextStyle(
            fontSize: 14,
            color: AppColors.textMuted,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
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

  @override
  void dispose() {
    _flutterTts.stop();
    super.dispose();
  }
}
