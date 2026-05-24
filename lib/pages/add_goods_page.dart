import 'dart:io';
import 'package:flutter/material.dart';
import 'package:barcode_scan2/barcode_scan2.dart';
import 'package:image_picker/image_picker.dart';
import '../database/db_helper.dart';
import '../models/goods.dart';
import '../services/barcode_service.dart';
import '../utils/app_colors.dart';

class AddGoodsPage extends StatefulWidget {
  final String? initialBarcode;
  final Goods? existingGoods;

  const AddGoodsPage({super.key, this.initialBarcode, this.existingGoods});

  @override
  State<AddGoodsPage> createState() => _AddGoodsPageState();
}

class _AddGoodsPageState extends State<AddGoodsPage> {
  final _db = DBHelper();
  final _barcodeService = BarcodeService();
  final _picker = ImagePicker();

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

  @override
  void initState() {
    super.initState();
    if (widget.existingGoods != null) {
      _isEditing = true;
      _loadExistingData(widget.existingGoods!);
    } else if (widget.initialBarcode != null) {
      _barcode = widget.initialBarcode!;
      _queryBarcode(_barcode);
    } else {
      _scanBarcode();
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

  Future<void> _scanBarcode() async {
    try {
      final result = await BarcodeScanner.scan(
        options: const ScanOptions(
          strings: {
            'cancel': '取消',
            'flash_on': '手电筒',
            'flash_off': '关闭手电筒',
          },
          restrictFormat: [BarcodeFormat.ean13, BarcodeFormat.ean8, BarcodeFormat.code128],
          useCamera: -1,
          autoEnableFlash: false,
        ),
      );

      if (result.rawContent.isNotEmpty) {
        setState(() => _barcode = result.rawContent);
        _checkExistingAndQuery();
      }
    } catch (e) {
      _showError('扫码失败: $e');
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
    setState(() => _isLoading = true);
    try {
      final info = await _barcodeService.queryBarcode(barcode);
      if (info.found) {
        setState(() {
          _nameCtrl.text = info.goodsName ?? '';
          _brandCtrl.text = info.brand ?? '';
          _specCtrl.text = info.spec ?? '';
          _imageUrl = info.imageUrl;
          _isManualMode = false;
        });
      } else {
        setState(() => _isManualMode = true);
        _showInfo('未查询到公开商品信息，请手动完善');
      }
    } catch (e) {
      setState(() => _isManualMode = true);
      _showInfo('网络不可用，已进入手动录入模式');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _pickImage() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery);
    if (picked != null) {
      setState(() {
        _localImage = File(picked.path);
        _imageUrl = null;
      });
    }
  }

  Future<void> _saveGoods() async {
    if (_barcode.isEmpty) {
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

    final now = DateTime.now();
    final imagePath = _localImage?.path ?? _imageUrl;

    final goods = Goods(
      id: _isEditing ? widget.existingGoods!.id : null,
      barcode: _barcode,
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
      if (_isEditing) {
        await _db.updateGoods(goods);
      } else {
        await _db.insertGoods(goods);
      }

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('保存成功'),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  Navigator.pop(context, true);
                },
                child: const Text('确定', style: TextStyle(color: AppColors.primary)),
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
    if (_localImage != null) {
      return Image.file(_localImage!, fit: BoxFit.cover);
    }
    if (_imageUrl != null && _imageUrl!.isNotEmpty) {
      return Image.network(
        _imageUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildPlaceholder(),
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
          : SingleChildScrollView(
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
                  _buildField('商品名称 *', _nameCtrl, required: true),
                  _buildField('品牌', _brandCtrl),
                  _buildField('规格/净含量', _specCtrl),
                  _buildField('本店售价 *', _sellPriceCtrl,
                      keyboardType: TextInputType.number, required: true),
                  _buildField('进货价', _purchasePriceCtrl,
                      keyboardType: TextInputType.number,
                      hint: '仅店主可见，选填'),
                  _buildField('备注', _remarkCtrl, maxLines: 2),
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
                Text(
                  _barcode.isEmpty ? '未扫描' : _barcode,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
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

  Widget _buildField(String label, TextEditingController controller,
      {TextInputType? keyboardType, bool required = false, int maxLines = 1, String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: AppColors.textSecondary, fontSize: 14)),
          const SizedBox(height: 6),
          TextField(
            controller: controller,
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
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _brandCtrl.dispose();
    _specCtrl.dispose();
    _sellPriceCtrl.dispose();
    _purchasePriceCtrl.dispose();
    _remarkCtrl.dispose();
    super.dispose();
  }
}
