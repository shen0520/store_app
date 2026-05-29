import 'package:flutter/material.dart';
import '../database/db_helper.dart';
import '../services/export_service.dart';
import '../services/import_service.dart';
import '../utils/app_colors.dart';

class DataManagePage extends StatefulWidget {
  const DataManagePage({super.key});

  @override
  State<DataManagePage> createState() => _DataManagePageState();
}

class _DataManagePageState extends State<DataManagePage> {
  final _db = DBHelper();
  final _exportService = ExportService();
  final _importService = ImportService();

  int _goodsCount = 0;
  bool _isLoading = false;
  String _conflictStrategy = 'skip'; // skip, overwrite, merge

  @override
  void initState() {
    super.initState();
    _loadGoodsCount();
  }

  Future<void> _loadGoodsCount() async {
    final count = await _db.getGoodsCount();
    if (mounted) {
      setState(() => _goodsCount = count);
    }
  }

  Future<void> _exportData() async {
    setState(() => _isLoading = true);
    try {
      final filePath = await _exportService.exportToJson();
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('导出成功'),
            content: Text('商品数据已导出，共 $_goodsCount 条\n\n文件路径:\n$filePath'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('关闭', style: TextStyle(color: AppColors.textMuted)),
              ),
              TextButton(
                onPressed: () async {
                  Navigator.pop(ctx);
                  await _exportService.shareExportedFile(filePath);
                },
                child: const Text('分享文件', style: TextStyle(color: AppColors.primary)),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      _showError('导出失败: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _exportToCsv() async {
    setState(() => _isLoading = true);
    try {
      final filePath = await _exportService.exportToCsv();
      if (mounted) {
        _showInfo('CSV 导出成功');
        await _exportService.shareExportedFile(filePath);
      }
    } catch (e) {
      _showError('导出失败: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _importData() async {
    // 先确认导入策略
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('导入数据'),
        content: StatefulBuilder(
          builder: (context, setDialogState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('如果导入的商品条码已存在，如何处理？'),
                const SizedBox(height: 16),
                _buildRadioOption(
                  label: '跳过重复（保留本地数据）',
                  value: 'skip',
                  dialogSetState: setDialogState,
                ),
                _buildRadioOption(
                  label: '覆盖重复（用导入数据替换）',
                  value: 'overwrite',
                  dialogSetState: setDialogState,
                ),
                _buildRadioOption(
                  label: '智能合并（保留最新修改）',
                  value: 'merge',
                  dialogSetState: setDialogState,
                ),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('选择文件', style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      final result = await _importService.importFromFile(
        conflictStrategy: _conflictStrategy,
      );

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(result['success'] ? '导入完成' : '导入失败'),
            content: Text(result['message'] as String),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  if (result['success'] == true) {
                    _loadGoodsCount();
                  }
                },
                child: const Text('确定', style: TextStyle(color: AppColors.primary)),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      _showError('导入失败: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Widget _buildRadioOption({
    required String label,
    required String value,
    required StateSetter dialogSetState,
  }) {
    return RadioListTile<String>(
      title: Text(label, style: const TextStyle(fontSize: 14)),
      value: value,
      groupValue: _conflictStrategy,
      activeColor: AppColors.primary,
      contentPadding: EdgeInsets.zero,
      dense: true,
      onChanged: (v) {
        dialogSetState(() => _conflictStrategy = v!);
      },
    );
  }

  Future<void> _clearAllData() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认清空'),
        content: const Text('确定要删除所有商品数据吗？\n此操作不可恢复！'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消', style: TextStyle(color: AppColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('清空', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      await _db.clearAllGoods();
      _showInfo('已清空全部数据');
      _loadGoodsCount();
    } catch (e) {
      _showError('清空失败: $e');
    } finally {
      setState(() => _isLoading = false);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.primary,
        title: const Text('数据管理', style: TextStyle(color: Colors.white, fontSize: 18)),
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
                  // 数据统计卡片
                  _buildStatsCard(),
                  const SizedBox(height: 24),

                  // 导出区域
                  _buildSectionTitle('数据导出'),
                  const SizedBox(height: 8),
                  _buildInfoText('将商品数据导出为文件，可分享给其他手机导入'),
                  const SizedBox(height: 12),
                  _buildActionButton(
                    label: '导出为 JSON (推荐)',
                    icon: Icons.download,
                    onTap: _exportData,
                  ),
                  const SizedBox(height: 8),
                  _buildActionButton(
                    label: '导出为 CSV (Excel可打开)',
                    icon: Icons.table_chart,
                    onTap: _exportToCsv,
                  ),
                  const SizedBox(height: 24),

                  // 导入区域
                  _buildSectionTitle('数据导入'),
                  const SizedBox(height: 8),
                  _buildInfoText('从 JSON 或 CSV 文件导入商品数据'),
                  const SizedBox(height: 12),
                  _buildActionButton(
                    label: '导入数据',
                    icon: Icons.upload_file,
                    color: AppColors.accent,
                    onTap: _importData,
                  ),
                  const SizedBox(height: 24),

                  // 危险操作区域
                  _buildSectionTitle('危险操作'),
                  const SizedBox(height: 8),
                  _buildInfoText('请谨慎操作，建议先导出备份'),
                  const SizedBox(height: 12),
                  _buildActionButton(
                    label: '清空全部数据',
                    icon: Icons.delete_forever,
                    color: AppColors.danger,
                    onTap: _clearAllData,
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildStatsCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '当前商品数量',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 8),
          Text(
            '$_goodsCount',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 48,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Text(
            '条',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: AppColors.textPrimary,
      ),
    );
  }

  Widget _buildInfoText(String text) {
    return Text(
      text,
      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
    );
  }

  Widget _buildActionButton({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
    Color? color,
  }) {
    final btnColor = color ?? AppColors.primary;
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ElevatedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 20),
        label: Text(label, style: const TextStyle(fontSize: 16)),
        style: ElevatedButton.styleFrom(
          backgroundColor: btnColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          elevation: 0,
        ),
      ),
    );
  }
}
