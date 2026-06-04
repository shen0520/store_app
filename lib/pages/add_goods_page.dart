import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'scan_page.dart';
import 'package:image_picker/image_picker.dart';
import '../database/db_helper.dart';
import '../models/goods.dart';
import '../providers/goods_provider.dart';
import '../services/barcode_service.dart';
import '../utils/app_colors.dart';
import '../widgets/goods_image.dart';

class AddGoodsPage extends StatefulWidget {
  final String? initialBarcode;
  final Goods? existingGoods;

  const AddGoodsPage({super.key, this.initialBarcode, this.existingGoods});

  @override
  State<AddGoodsPage> createState() => _AddGoodsPageState();
}

/// 支持语音输入的字段
enum _VoiceField { name, brand, spec, remark }

class _AddGoodsPageState extends State<AddGoodsPage> with WidgetsBindingObserver {
  final _db = DBHelper();
  final _barcodeService = BarcodeService();
  final _picker = ImagePicker();
  final _speech = SpeechToText();

  final _nameCtrl = TextEditingController();
  final _brandCtrl = TextEditingController();
  final _specCtrl = TextEditingController();
  final _sellPriceCtrl = TextEditingController();
  final _purchasePriceCtrl = TextEditingController();
  final _remarkCtrl = TextEditingController();

  String _barcode = '';
  String? _imageUrl;
  File? _localImage;
  bool _isLoading = false;
  bool _isEditing = false;
  bool _isManualMode = false;
  bool _isNoBarcodeMode = false;

  // 语音识别状态
  bool _speechAvailable = false;

  // FocusNodes
  final _nameFocus = FocusNode();
  final _brandFocus = FocusNode();
  final _specFocus = FocusNode();
  final _remarkFocus = FocusNode();

  // 录音交互状态
  bool _isRecording = false;
  bool _isCancelled = false;
  DateTime? _recordingStartTime;
  Timer? _maxDurationTimer;
  double _currentSoundLevel = 0;
  Offset? _pointerDownPosition;
  _VoiceField? _recordingField;
  String _recognizedWords = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initSpeech();
    if (widget.existingGoods != null) {
      _isEditing = true;
      _loadExistingData(widget.existingGoods!);
    } else if (widget.initialBarcode != null) {
      if (widget.initialBarcode == '__NO_BARCODE__') {
        setState(() {
          _isNoBarcodeMode = true;
          _barcode = '';
          _isManualMode = true;
        });
      } else {
        _barcode = widget.initialBarcode!;
        _queryBarcode(_barcode);
      }
    } else {
      // 不再自动打开扫码页，默认进入手动录入模式，等用户主动选择
      setState(() => _isManualMode = true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.paused ||
            state == AppLifecycleState.inactive) &&
        _isRecording) {
      _cancelRecording();
    }
  }

  void _loadExistingData(Goods goods) {
    _barcode = goods.barcode;
    _nameCtrl.text = goods.goodsName;
    _brandCtrl.text = goods.brand ?? '';
    _specCtrl.text = goods.spec ?? '';
    _sellPriceCtrl.text = goods.sellPrice.toString();
    _purchasePriceCtrl.text = goods.purchasePrice?.toString() ?? '';
    _remarkCtrl.text = goods.remark ?? '';
    _imageUrl = goods.goodsImg;
  }

  /// 初始化语音识别
  Future<void> _initSpeech() async {
    try {
      _speechAvailable = await _speech.initialize(
        onError: (error) {
          debugPrint('语音识别错误: $error');
          if (!mounted) return;
          if (_isRecording) {
            _cancelRecording();
            _showInfo('麦克风被占用或识别出错，请重试');
          }
        },
      );
    } catch (e) {
      debugPrint('语音识别初始化失败: $e');
    }
  }

  // ─── 长按语音交互 ───

  void _onMicPointerDown(_VoiceField field, Offset position) {
    if (!_speechAvailable) {
      _showInfo('语音识别不可用，请检查麦克风权限');
      return;
    }

    _pointerDownPosition = position;
    _recordingStartTime = DateTime.now();
    _isCancelled = false;
    _recognizedWords = '';
    _recordingField = field;
    _currentSoundLevel = 0;

    setState(() => _isRecording = true);

    _maxDurationTimer = Timer(const Duration(seconds: 30), () {
      if (_isRecording) _stopRecordingAndRecognize();
    });

    _speech.listen(
      onResult: (result) {
        if (!mounted) return;
        if (result.recognizedWords.isNotEmpty) {
          _recognizedWords = result.recognizedWords;
          // 实时写入输入框（像第一版本那样边录边出）
          if (_recordingField != null) {
            _getController(_recordingField!).text = _recognizedWords;
          }
        }
      },
      onSoundLevelChange: (level) {
        if (!mounted) return;
        setState(() => _currentSoundLevel = level);
      },
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
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
    // 先关闭录音 UI，避免用户觉得卡住
    if (mounted) {
      setState(() => _isRecording = false);
    }
    // 给语音识别引擎时间返回最终结果（onResult 的最终回调可能延迟）
    await Future.delayed(const Duration(milliseconds: 1000));
    if (!mounted) return;

    // onResult 已实时写入，这里做最终确认；如果仍为空才提示失败
    if (_recognizedWords.isEmpty && _recordingField != null) {
      final currentText = _getController(_recordingField!).text;
      if (currentText.isEmpty) {
        _showInfo('语音识别失败，请重试');
      }
    }
  }

  Future<void> _cancelRecording() async {
    _maxDurationTimer?.cancel();
    _maxDurationTimer = null;
    await _speech.cancel();
    if (!mounted) return;
    setState(() => _isRecording = false);
  }

  TextEditingController _getController(_VoiceField field) {
    switch (field) {
      case _VoiceField.name:
        return _nameCtrl;
      case _VoiceField.brand:
        return _brandCtrl;
      case _VoiceField.spec:
        return _specCtrl;
      case _VoiceField.remark:
        return _remarkCtrl;
    }
  }

  FocusNode _getFocusNode(_VoiceField field) {
    switch (field) {
      case _VoiceField.name:
        return _nameFocus;
      case _VoiceField.brand:
        return _brandFocus;
      case _VoiceField.spec:
        return _specFocus;
      case _VoiceField.remark:
        return _remarkFocus;
    }
  }

  void _resetAndContinue() {
    setState(() {
      _isEditing = false;
      _isNoBarcodeMode = false;
      _isManualMode = false;
      _barcode = '';
      _imageUrl = null;
      _localImage = null;
    });
    _nameCtrl.clear();
    _brandCtrl.clear();
    _specCtrl.clear();
    _sellPriceCtrl.clear();
    _purchasePriceCtrl.clear();
    _remarkCtrl.clear();
    _scanBarcode();
  }

  Future<void> _scanBarcode() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScanPage()),
    );

    if (result != null && result.isNotEmpty) {
      if (result == '__NO_BARCODE__') {
        // 用户选择了无条码录入
        setState(() {
          _isNoBarcodeMode = true;
          _barcode = '';
          _isManualMode = true;
        });
      } else {
        setState(() {
          _isNoBarcodeMode = false;
          _barcode = result;
        });
        _checkExistingAndQuery();
      }
    }
  }

  Future<void> _checkExistingAndQuery() async {
    final exists = await _db.barcodeExists(_barcode);
    if (exists && !_isEditing) {
      if (mounted) {
        final existing = await _db.getGoodsByBarcode(_barcode);
        final shouldEdit = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('商品已存在'),
            content: const Text('该商品已录入，是否前往编辑？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消', style: TextStyle(color: AppColors.textMuted)),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('编辑', style: TextStyle(color: AppColors.primary)),
              ),
            ],
          ),
        );
        if (shouldEdit == true && existing != null) {
          if (mounted) {
            Navigator.pop(context);
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AddGoodsPage(existingGoods: existing),
              ),
            );
          }
          return;
        } else {
          if (mounted) Navigator.pop(context);
          return;
        }
      }
    }
    _queryBarcode(_barcode);
  }

  Future<void> _queryBarcode(String barcode) async {
    // API 查询已禁用：条码 API 不稳定，等待时间长，直接手动录入
    setState(() {
      _isManualMode = true;
      _isLoading = false;
    });
    // 如需恢复 API 查询，取消下面注释：
    // setState(() => _isLoading = true);
    // try {
    //   final info = await _barcodeService.queryBarcode(barcode);
    //   if (info.found) {
    //     setState(() {
    //       _nameCtrl.text = info.goodsName ?? '';
    //       _brandCtrl.text = info.brand ?? '';
    //       _specCtrl.text = info.spec ?? '';
    //       _imageUrl = info.imageUrl;
    //       _isManualMode = false;
    //     });
    //   } else {
    //     setState(() => _isManualMode = true);
    //     _showInfo('未查询到商品信息，请手动录入');
    //   }
    // } catch (e) {
    //   setState(() => _isManualMode = true);
    //   _showInfo('条码查询服务暂不可用，请手动录入');
    // } finally {
    //   setState(() => _isLoading = false);
    // }
  }

  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 800,
      maxHeight: 800,
      imageQuality: 80,
    );
    if (picked != null) {
      final savedFile = await _saveImageToAppDir(File(picked.path));
      setState(() {
        _localImage = savedFile;
        _imageUrl = null;
      });
    }
  }

  /// 将图片复制到应用私有目录，避免原图删除后失效
  Future<File> _saveImageToAppDir(File sourceFile) async {
    final appDir = await getApplicationDocumentsDirectory();
    final imageDir = Directory('${appDir.path}/goods_images');
    if (!await imageDir.exists()) {
      await imageDir.create(recursive: true);
    }
    final fileName = 'goods_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final destPath = '${imageDir.path}/$fileName';
    return await sourceFile.copy(destPath);
  }

  Future<void> _saveGoods() async {
    // 条码校验：非无条码模式且非编辑模式下，条码不能为空
    if (!_isNoBarcodeMode && _barcode.isEmpty && !_isEditing) {
      _showError('条码不能为空');
      return;
    }
    if (_nameCtrl.text.trim().isEmpty) {
      _showError('商品名称不能为空');
      return;
    }
    if (_sellPriceCtrl.text.trim().isEmpty) {
      _showError('本店售价不能为空');
      return;
    }

    final sellPrice = double.tryParse(_sellPriceCtrl.text.trim());
    if (sellPrice == null || sellPrice < 0) {
      _showError('售价格式不正确');
      return;
    }

    final purchasePrice = _purchasePriceCtrl.text.trim().isNotEmpty
        ? double.tryParse(_purchasePriceCtrl.text.trim())
        : null;

    // 无条码模式下自动生成条码
    String finalBarcode = _barcode;
    if (_isNoBarcodeMode && !_isEditing) {
      finalBarcode = await _db.generateNoBarcode();
      // 兜底校验：若冲突则重新生成（防止极端并发情况）
      int retryCount = 0;
      while (await _db.barcodeExists(finalBarcode) && retryCount < 10) {
        finalBarcode = await _db.generateNoBarcode();
        retryCount++;
      }
    }

    final now = DateTime.now();
    final imagePath = _localImage?.path ?? _imageUrl;

    final goods = Goods(
      id: _isEditing ? widget.existingGoods!.id : null,
      barcode: finalBarcode,
      goodsName: _nameCtrl.text.trim(),
      brand: _brandCtrl.text.trim().isNotEmpty ? _brandCtrl.text.trim() : null,
      spec: _specCtrl.text.trim().isNotEmpty ? _specCtrl.text.trim() : null,
      goodsImg: imagePath,
      purchasePrice: purchasePrice,
      sellPrice: sellPrice,
      remark: _remarkCtrl.text.trim().isNotEmpty ? _remarkCtrl.text.trim() : null,
      createTime: _isEditing ? widget.existingGoods!.createTime : now,
      updateTime: now,
    );

    try {
      final provider = context.read<GoodsProvider>();
      if (_isEditing) {
        await provider.updateGoods(goods);
      } else {
        await provider.addGoods(goods);
      }

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('保存成功'),
            content: _isEditing
                ? null
                : const Text('继续录入下一件商品，或返回首页？'),
            actions: [
              if (!_isEditing)
                TextButton(
                  onPressed: () {
                    Navigator.pop(ctx);
                    _resetAndContinue();
                  },
                  child: const Text('继续录入', style: TextStyle(color: AppColors.accent)),
                ),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.pop(context, true);
                },
                child: Text(_isEditing ? '确定' : '返回首页', style: const TextStyle(color: AppColors.primary)),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      _showError('保存失败: $e');
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.danger),
    );
  }

  void _showInfo(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: AppColors.primary),
    );
  }

  Widget _buildImagePreview() {
    final path = _localImage?.path ?? _imageUrl;
    if (path != null && path.isNotEmpty) {
      return GoodsImage(
        imagePath: path,
        width: double.infinity,
        height: 180,
        fit: BoxFit.cover,
      );
    }
    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Container(
      color: AppColors.cardBg,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image, size: 40, color: AppColors.textMuted),
            SizedBox(height: 8),
            Text('暂无图片', style: TextStyle(color: AppColors.textMuted)),
          ],
        ),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: Text(_isEditing ? '编辑商品' : '录入新商品',
            style: const TextStyle(color: Colors.white, fontSize: 18)),
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: AppColors.primary))
          : Stack(
              children: [
                SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_isManualMode)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          margin: const EdgeInsets.only(bottom: 16),
                          decoration: BoxDecoration(
                            color: AppColors.cardBg,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.info_outline, color: AppColors.accent, size: 20),
                              SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '手动录入模式：请填写商品信息',
                                  style: TextStyle(color: AppColors.accent, fontSize: 14),
                                ),
                              ),
                            ],
                          ),
                        ),
                      _buildBarcodeSection(),
                      const SizedBox(height: 20),
                      _buildImageSection(),
                      const SizedBox(height: 20),
                      _buildField('商品名称 *', _nameCtrl,
                          focusNode: _nameFocus, field: _VoiceField.name, required: true),
                      _buildField('品牌', _brandCtrl,
                          focusNode: _brandFocus, field: _VoiceField.brand),
                      _buildField('规格/净含量', _specCtrl,
                          focusNode: _specFocus, field: _VoiceField.spec),
                      _buildField('本店售价 *', _sellPriceCtrl,
                          keyboardType: TextInputType.number, required: true),
                      _buildField('进货价', _purchasePriceCtrl,
                          keyboardType: TextInputType.number,
                          hint: '仅店主可见，选填'),
                      _buildField('备注', _remarkCtrl,
                          focusNode: _remarkFocus, field: _VoiceField.remark, maxLines: 2),
                      const SizedBox(height: 32),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          onPressed: _saveGoods,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            textStyle: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          child: Text(_isEditing ? '保存修改' : '保存商品'),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],
                  ),
                ),
                if (_isRecording) _buildRecordingOverlay(),
              ],
            ),
    );
  }

  Widget _buildBarcodeSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('商品条码', style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
                const SizedBox(height: 4),
                if (_isNoBarcodeMode)
                  const Text(
                    '自动生成',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  )
                else
                  Text(
                    _barcode.isEmpty ? '未扫描' : _barcode,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: _barcode.isEmpty ? AppColors.textMuted : AppColors.textPrimary,
                    ),
                  ),
              ],
            ),
          ),
          // 手动录入的商品（sd 开头）编辑时不允许重扫条码
          if (!_isNoBarcodeMode && !(_isEditing && _barcode.startsWith('sd')))
            ElevatedButton.icon(
              onPressed: _scanBarcode,
              icon: const Icon(Icons.qr_code_scanner, size: 18),
              label: Text(_barcode.isEmpty ? '扫码' : '重扫'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildImageSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('商品图片', style: TextStyle(color: AppColors.textSecondary, fontSize: 14)),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: _pickImage,
          child: Container(
            width: double.infinity,
            height: 180,
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.border),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: _buildImagePreview(),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Center(
          child: TextButton.icon(
            onPressed: _pickImage,
            icon: const Icon(Icons.camera_alt, size: 16, color: AppColors.primary),
            label: const Text('更换图片', style: TextStyle(color: AppColors.primary, fontSize: 14)),
          ),
        ),
      ],
    );
  }

  Widget _buildField(
    String label,
    TextEditingController controller, {
    FocusNode? focusNode,
    _VoiceField? field,
    TextInputType? keyboardType,
    bool required = false,
    int maxLines = 1,
    String? hint,
  }) {
    final isNumberField = keyboardType == TextInputType.number;
    final isRecordingThisField = _isRecording && _recordingField == field;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
            focusNode: focusNode,
            keyboardType: keyboardType,
            maxLines: maxLines,
            style: const TextStyle(color: AppColors.textPrimary, fontSize: 16),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: AppColors.textMuted),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: AppColors.primary),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              suffixIcon: !isNumberField && field != null
                  ? Listener(
                      onPointerDown: (event) => _onMicPointerDown(field, event.position),
                      onPointerMove: (event) => _onMicPointerMove(event.position),
                      onPointerUp: (_) => _onMicPointerUp(),
                      child: Container(
                        width: 40,
                        height: 40,
                        alignment: Alignment.center,
                        child: Icon(
                          isRecordingThisField ? Icons.mic : Icons.mic_none,
                          color: isRecordingThisField ? AppColors.primary : AppColors.textMuted,
                          size: 22,
                        ),
                      ),
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _maxDurationTimer?.cancel();
    _speech.cancel();
    _nameFocus.dispose();
    _brandFocus.dispose();
    _specFocus.dispose();
    _remarkFocus.dispose();
    _nameCtrl.dispose();
    _brandCtrl.dispose();
    _specCtrl.dispose();
    _sellPriceCtrl.dispose();
    _purchasePriceCtrl.dispose();
    _remarkCtrl.dispose();
    super.dispose();
  }
}
