import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart';
import '../providers/goods_provider.dart';
import '../models/goods.dart';
import '../utils/app_colors.dart';
import '../widgets/goods_image.dart';
import 'add_goods_page.dart';

class GoodsListPage extends StatefulWidget {
  const GoodsListPage({super.key});

  @override
  State<GoodsListPage> createState() => _GoodsListPageState();
}

class _GoodsListPageState extends State<GoodsListPage> {
  final _searchCtrl = TextEditingController();
  Timer? _debounceTimer;
  final ScrollController _scrollController = ScrollController();

  // 语音搜索
  final _speech = SpeechToText();
  bool _speechAvailable = false;
  bool _isRecording = false;
  bool _isCancelled = false;
  DateTime? _recordingStartTime;
  Timer? _maxDurationTimer;
  double _currentSoundLevel = 0;
  Offset? _pointerDownPosition;
  String _recognizedWords = '';
  String _searchCtrlTextBeforeRecording = '';
  int _goodsCount = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _initSpeech();
    _loadGoodsCount();
    // 页面打开后加载数据（若存在上次搜索残留，先清空搜索词）
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<GoodsProvider>();
      if (provider.searchQuery != null) {
        _searchCtrl.clear();
        provider.search('');
      } else {
        provider.loadGoods();
      }
    });
  }

  Future<void> _loadGoodsCount() async {
    final count = await context.read<GoodsProvider>().getGoodsCount();
    if (mounted) {
      setState(() => _goodsCount = count);
    }
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      context.read<GoodsProvider>().loadMore();
    }
  }

  // ─── 语音搜索 ───

  Future<void> _initSpeech() async {
    try {
      _speechAvailable = await _speech.initialize(
        onError: (error) {
          debugPrint('语音识别错误: $error');
          if (!mounted) return;
          if (_isRecording) {
            _cancelRecording();
            _showInfo('语音错误: $error');
          }
        },
      );
    } catch (e) {
      debugPrint('语音识别初始化失败: $e');
    }
  }

  void _onMicPointerDown(Offset position) {
    if (!_speechAvailable) {
      _showInfo('语音识别不可用，请检查麦克风权限');
      return;
    }
    // 收起键盘，避免语音输入时键盘遮挡
    FocusScope.of(context).unfocus();
    _pointerDownPosition = position;
    _recordingStartTime = DateTime.now();
    _isCancelled = false;
    _recognizedWords = '';
    _searchCtrlTextBeforeRecording = _searchCtrl.text;
    _currentSoundLevel = 0;

    setState(() => _isRecording = true);

    _maxDurationTimer = Timer(const Duration(seconds: 60), () {
      if (_isRecording) _stopRecordingAndRecognize();
    });

    _speech.listen(
      onResult: (result) {
        if (!mounted) return;
        if (result.recognizedWords.isNotEmpty) {
          _recognizedWords = result.recognizedWords;
          // 实时追加到已有文字后
          _searchCtrl.text = _searchCtrlTextBeforeRecording + _recognizedWords;
        }
      },
      onSoundLevelChange: (level) {
        if (!mounted) return;
        setState(() => _currentSoundLevel = level);
      },
      listenFor: const Duration(seconds: 60),
      pauseFor: const Duration(seconds: 10),
      localeId: 'zh_CN',
    );
  }

  void _onMicPointerMove(Offset position) {
    if (!_isRecording || _pointerDownPosition == null) return;
    final dy = position.dy - _pointerDownPosition!.dy;
    final shouldCancel = dy < -80;
    if (shouldCancel != _isCancelled) {
      setState(() => _isCancelled = shouldCancel);
    }
  }

  Future<void> _onMicPointerUp() async {
    if (!_isRecording) return;

    final duration = DateTime.now().difference(_recordingStartTime!);
    _maxDurationTimer?.cancel();
    _maxDurationTimer = null;

    // 误触保护
    if (duration < const Duration(milliseconds: 500)) {
      await _speech.cancel();
      setState(() => _isRecording = false);
      _showInfo('录音过短');
      return;
    }

    // 已取消
    if (_isCancelled) {
      await _speech.cancel();
      setState(() => _isRecording = false);
      return;
    }

    // 正常结束
    await _stopRecordingAndRecognize();
  }

  Future<void> _stopRecordingAndRecognize() async {
    await _speech.stop();
    if (!mounted) return;
    setState(() => _isRecording = false);

    // 给语音识别引擎时间返回最终结果（onResult 的最终回调可能延迟）
    await Future.delayed(const Duration(milliseconds: 1000));
    if (!mounted) return;

    if (_recognizedWords.isNotEmpty) {
      final fullText = _searchCtrlTextBeforeRecording + _recognizedWords;
      _searchCtrl.text = fullText;
      _onSearchChanged(fullText);
    } else {
      _showInfo('识别无结果（未收到文字），请重试');
    }
  }

  Future<void> _cancelRecording() async {
    _maxDurationTimer?.cancel();
    _maxDurationTimer = null;
    await _speech.cancel();
    if (!mounted) return;
    setState(() => _isRecording = false);
  }

  void _showInfo(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.primary),
    );
  }

  void _onSearchChanged(String value) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      context.read<GoodsProvider>().search(value);
    });
  }

  Future<bool> _deleteGoods(Goods goods) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定删除 "${goods.goodsName}" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );

    if (confirm == true && goods.id != null) {
      await context.read<GoodsProvider>().deleteGoods(goods.id!);
      await _loadGoodsCount();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('删除成功'),
            backgroundColor: AppColors.primary,
          ),
        );
      }
      return true;
    }
    return false;
  }

  Future<void> _editGoods(Goods goods) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AddGoodsPage(existingGoods: goods),
      ),
    );
    if (result == true && mounted) {
      await context.read<GoodsProvider>().loadGoods(refresh: true);
      await _loadGoodsCount();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text('商品管理',
            style: TextStyle(color: Colors.white, fontSize: 18)),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: Stack(
        children: [
          Column(
            children: [
              _buildSearchBar(),
              _buildStatsCard(),
              Expanded(
                child: Consumer<GoodsProvider>(
                  builder: (context, provider, child) {
                    if (provider.isLoading && provider.goodsList.isEmpty) {
                      return const Center(
                        child: CircularProgressIndicator(color: AppColors.primary),
                      );
                    }
                    if (provider.goodsList.isEmpty) {
                      return _buildEmptyState();
                    }
                    return _buildList(provider);
                  },
                ),
              ),
            ],
          ),
          if (_isRecording) _buildRecordingOverlay(),
        ],
      ),
    );
  }

  // ─── 录音弹窗覆盖层 ───

  Widget _buildRecordingOverlay() {
    return Positioned.fill(
      child: IgnorePointer(
        child: Container(
          color: Colors.black.withOpacity(0.5),
          child: Center(
            child: Container(
              width: 220,
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              decoration: BoxDecoration(
                color: const Color(0xCC1A1A1A),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildSoundWave(),
                  const SizedBox(height: 20),
                  Icon(
                    Icons.mic,
                    size: 48,
                    color: _isCancelled ? Colors.red : Colors.white,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _isCancelled
                        ? '松开取消'
                        : '松开结束录音，上滑取消本次录入',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSoundWave() {
    final normalized = (_currentSoundLevel.abs() / 50000).clamp(0.0, 1.0);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(7, (index) {
        final distFromCenter = (index - 3).abs();
        final factor = 1 - distFromCenter * 0.2;
        final height = 6 + normalized * 28 * factor;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 100),
          width: 4,
          height: height.clamp(6.0, 34.0),
          margin: const EdgeInsets.symmetric(horizontal: 2),
          decoration: BoxDecoration(
            color: _isCancelled ? Colors.red : Colors.white,
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: const BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(0),
          bottomRight: Radius.circular(0),
        ),
      ),
      child: TextField(
        controller: _searchCtrl,
        onChanged: _onSearchChanged,
        style: const TextStyle(color: AppColors.textPrimary),
        decoration: InputDecoration(
          hintText: '搜索商品名称或条码',
          hintStyle: const TextStyle(color: AppColors.textMuted),
          prefixIcon: const Icon(Icons.search, color: AppColors.textMuted),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_searchCtrl.text.isNotEmpty)
                IconButton(
                  icon: const Icon(Icons.clear, color: AppColors.textMuted),
                  onPressed: () {
                    _searchCtrl.clear();
                    _onSearchChanged('');
                  },
                ),
              Focus(
                canRequestFocus: false,
                descendantsAreFocusable: false,
                child: Listener(
                  onPointerDown: (event) => _onMicPointerDown(event.position),
                  onPointerMove: (event) => _onMicPointerMove(event.position),
                  onPointerUp: (_) => _onMicPointerUp(),
                  child: Container(
                    width: 40,
                    height: 40,
                    alignment: Alignment.center,
                    child: Icon(
                      _isRecording ? Icons.mic : Icons.mic_none,
                      color: _isRecording ? AppColors.primary : AppColors.textMuted,
                      size: 22,
                    ),
                  ),
                ),
              ),
            ],
          ),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Widget _buildStatsCard() {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, Color(0xFF006B44)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.25),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '商品总数',
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      '$_goodsCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 40,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Text(
                      '条',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.inventory_2_outlined,
              color: Colors.white,
              size: 28,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return const Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.inventory_2_outlined, size: 60, color: AppColors.textMuted),
          SizedBox(height: 16),
          Text(
            '暂无商品',
            style: TextStyle(fontSize: 18, color: AppColors.textSecondary),
          ),
          SizedBox(height: 8),
          Text(
            '点击录入新商品开始添加',
            style: TextStyle(fontSize: 14, color: AppColors.textMuted),
          ),
        ],
      ),
    );
  }

  Widget _buildList(GoodsProvider provider) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.all(12),
      itemCount: provider.goodsList.length + (provider.hasMore || provider.isLoadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index >= provider.goodsList.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          );
        }
        final goods = provider.goodsList[index];
        return _buildGoodsCard(goods);
      },
    );
  }

  Widget _buildGoodsCard(Goods goods) {
    return Dismissible(
      key: ValueKey(goods.id ?? goods.barcode),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _deleteGoods(goods),
      background: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppColors.danger,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete, color: Colors.white, size: 28),
            SizedBox(height: 4),
            Text('删除', style: TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
      ),
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        color: AppColors.cardBg,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        child: InkWell(
          onTap: () => _editGoods(goods),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.border),
                  ),
                  child: GoodsImage(
                    imagePath: goods.goodsImg,
                    width: 64,
                    height: 64,
                    fit: BoxFit.cover,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        goods.goodsName,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.textPrimary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${goods.brand ?? ''} ${goods.spec ?? ''}'.trim(),
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.textSecondary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '条码: ${goods.barcode}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 20, color: AppColors.border),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '售价: ¥${goods.sellPrice.toStringAsFixed(2)}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.accent,
                        ),
                      ),
                      if (goods.purchasePrice != null)
                        Text(
                          '进价: ¥${goods.purchasePrice!.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 13,
                            color: AppColors.textMuted,
                          ),
                        ),
                    ],
                  ),
                ),
                Row(
                  children: [
                    TextButton.icon(
                      onPressed: () => _editGoods(goods),
                      icon: const Icon(Icons.edit, size: 16, color: AppColors.accent),
                      label: const Text('编辑', style: TextStyle(color: AppColors.accent)),
                    ),
                    TextButton.icon(
                      onPressed: () => _deleteGoods(goods),
                      icon: const Icon(Icons.delete, size: 16, color: AppColors.danger),
                      label: const Text('删除', style: TextStyle(color: AppColors.danger)),
                    ),
                  ],
                ),
              ],
            ),
            if (goods.remark != null && goods.remark!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '备注: ${goods.remark}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textMuted,
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  ),
);
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _maxDurationTimer?.cancel();
    _speech.cancel();
    _searchCtrl.dispose();
    _scrollController.dispose();
    super.dispose();
  }
}
