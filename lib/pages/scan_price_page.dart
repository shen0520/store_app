import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  bool _ttsReady = false;
  bool _ttsEnabled = true; // 语音播报开关，默认开启
  String _ttsStatus = '初始化中...';
  String _lastBarcode = '';

  static const String _ttsPrefKey = 'tts_enabled';

  @override
  void initState() {
    super.initState();
    _loadTtsPreference();
    _initTts();
    WidgetsBinding.instance.addPostFrameCallback((_) => _scanBarcode());
  }

  Future<void> _loadTtsPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getBool(_ttsPrefKey);
      if (saved != null && mounted) {
        setState(() => _ttsEnabled = saved);
      }
    } catch (e) {
      debugPrint('读取 TTS 偏好设置失败: $e');
    }
  }

  Future<void> _toggleTts() async {
    setState(() => _ttsEnabled = !_ttsEnabled);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_ttsPrefKey, _ttsEnabled);
    } catch (e) {
      debugPrint('保存 TTS 偏好设置失败: $e');
    }
  }

  Future<void> _initTts() async {
    try {
      await _flutterTts.awaitSpeakCompletion(false);
      await _flutterTts.setSpeechRate(0.5);
      await _flutterTts.setVolume(1.0);
      await _flutterTts.setPitch(1.0);

      // 获取可用引擎列表
      final engines = await _flutterTts.getEngines;
      debugPrint('TTS 可用引擎: $engines');
      if (engines == null || (engines as List).isEmpty) {
        debugPrint('⚠️ 未检测到任何 TTS 引擎');
        setState(() => _ttsStatus = '未检测到语音引擎');
        return;
      }

      // 检查中文 TTS 引擎是否可用
      var isAvailable = await _flutterTts.isLanguageAvailable('zh-CN');
      if (!isAvailable) {
        isAvailable = await _flutterTts.isLanguageAvailable('zh_CN');
      }
      if (!isAvailable) {
        isAvailable = await _flutterTts.isLanguageAvailable('cmn');
      }
      debugPrint('TTS zh-CN 可用: $isAvailable');

      if (isAvailable) {
        await _flutterTts.setLanguage('zh-CN');
        _ttsReady = true;
        setState(() => _ttsStatus = '语音播报已开启');
      } else {
        final languages = await _flutterTts.getLanguages;
        debugPrint('TTS 所有可用语言: $languages');
        final zhLang = languages.cast<String?>().firstWhere(
          (l) =>
              l != null &&
              (l.startsWith('zh') || l.startsWith('cmn') || l.startsWith('ZH')),
          orElse: () => null,
        );
        if (zhLang != null) {
          await _flutterTts.setLanguage(zhLang);
          _ttsReady = true;
          setState(() => _ttsStatus = '语音播报已开启');
        } else {
          setState(() => _ttsStatus = '无中文语音引擎');
        }
      }
    } catch (e, st) {
      debugPrint('TTS 初始化异常: $e');
      debugPrint('$st');
      setState(() => _ttsStatus = '语音初始化失败');
    }
  }

  Future<void> _speakPrice(Goods goods) async {
    if (!_ttsEnabled) {
      debugPrint('🔇 语音播报已关闭，跳过播报');
      return;
    }
    if (!_ttsReady) {
      debugPrint('⚠️ TTS 未就绪，跳过播报。状态: $_ttsStatus');
      return;
    }
    final priceText = goods.sellPrice == goods.sellPrice.toInt()
        ? '${goods.sellPrice.toInt()}'
        : '${goods.sellPrice}';
    final text = '${goods.goodsName}，售价${priceText}元';
    debugPrint('TTS 播报: $text');
    try {
      final result = await _flutterTts.speak(text);
      if (result != 1) {
        debugPrint('⚠️ TTS speak 失败，返回值: $result');
      } else {
        debugPrint('✅ TTS speak 成功');
      }
    } catch (e) {
      debugPrint('⚠️ TTS speak 异常: $e');
    }
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
    // TODO: 临时调试日志，排查完注释掉
    // debugPrint('🔍 [扫码调试] 原始条码: "$barcode"');
    // debugPrint('🔍 [扫码调试] 长度: ${barcode.length}, runes: ${barcode.runes.toList()}');

    final goods = await _db.getGoodsByBarcode(barcode);

    // TODO: 临时调试日志，排查完注释掉
    // debugPrint('🔍 [扫码调试] 查询结果: ${goods != null ? '找到 ${goods.goodsName}' : '未找到'}');
    // if (goods != null) {
    //   debugPrint('🔍 [扫码调试] 数据库条码: "${goods.barcode}" 长度:${goods.barcode.length}');
    // }

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
              const SizedBox(height: 8),
              // TTS 状态提示
              if (!_ttsReady)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: AppColors.accent.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.volume_off,
                        size: 14,
                        color: AppColors.accent.withOpacity(0.7),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _ttsStatus,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.accent.withOpacity(0.8),
                        ),
                      ),
                    ],
                  ),
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
          // 商品名称 + 语音播报开关
          Row(
            children: [
              Expanded(
                child: Text(
                  goods.goodsName,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              // 语音播报开关按钮
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: _ttsReady ? _toggleTts : null,
                  borderRadius: BorderRadius.circular(20),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    child: Icon(
                      _ttsEnabled && _ttsReady
                          ? Icons.volume_up
                          : Icons.volume_off,
                      size: 24,
                      color: _ttsReady
                          ? (_ttsEnabled
                              ? AppColors.primary
                              : AppColors.textMuted)
                          : AppColors.textMuted.withOpacity(0.4),
                    ),
                  ),
                ),
              ),
            ],
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
          // TODO: 临时调试面板，排查完注释掉
          // _buildDebugInfo(),
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

  // TODO: 临时调试面板，排查完注释掉
  Widget _buildDebugInfo() {
    if (_lastBarcode.isEmpty) return const SizedBox.shrink();
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.yellow.withOpacity(0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '[调试] 扫码原始数据',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: Colors.deepOrange,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '条码: "$_lastBarcode"',
            style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
          ),
          Text(
            '长度: ${_lastBarcode.length}',
            style: const TextStyle(fontSize: 13, color: AppColors.textPrimary),
          ),
          Text(
            '字符码点: ${_lastBarcode.runes.map((r) => '0x${r.toRadixString(16).toUpperCase()}').join(', ')}',
            style: const TextStyle(fontSize: 11, color: AppColors.textMuted),
          ),
          Text(
            '查询状态: ${_currentGoods != null ? '找到商品: ${_currentGoods!.goodsName}' : '未找到'}',
            style: TextStyle(
              fontSize: 13,
              color: _currentGoods != null ? Colors.green : AppColors.danger,
              fontWeight: FontWeight.w500,
            ),
          ),
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
          // TODO: 临时调试面板，排查完注释掉
          // _buildDebugInfo(),
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
