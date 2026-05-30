import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/app_colors.dart';
import '../providers/goods_provider.dart';
import 'add_goods_page.dart';
import 'scan_price_page.dart';
import 'goods_list_page.dart';
import 'data_manage_page.dart';

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 40),
              const Text(
                '小店扫码查价',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '离线可用 · 数据安全 · 零广告',
                style: TextStyle(
                  fontSize: 16,
                  color: AppColors.textMuted,
                ),
              ),
              const SizedBox(height: 60),
              _buildMainButton(
                context: context,
                icon: Icons.qr_code_scanner,
                label: '录入新商品',
                subLabel: '扫码自动获取商品信息',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AddGoodsPage()),
                ),
              ),
              const SizedBox(height: 20),
              _buildMainButton(
                context: context,
                icon: Icons.price_check,
                label: '快速扫码查价',
                subLabel: '离线秒查本店售价',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ScanPricePage()),
                ),
              ),
              const Spacer(),
              _buildSecondaryButton(
                context: context,
                icon: Icons.inventory_2_outlined,
                label: '商品管理列表',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const GoodsListPage()),
                ),
              ),
              const SizedBox(height: 8),
              _buildSecondaryButton(
                context: context,
                icon: Icons.sync_alt,
                label: '数据导入/导出',
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DataManagePage()),
                ),
              ),
              const SizedBox(height: 16),
              Consumer<GoodsProvider>(
                builder: (context, provider, child) {
                  return FutureBuilder<int>(
                    future: provider.getGoodsCount(),
                    builder: (context, snapshot) {
                      final count = snapshot.data ?? 0;
                      return Center(
                        child: Text(
                          '已录入 $count 件商品 · 数据仅存储在本地',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textMuted,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMainButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String subLabel,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        decoration: BoxDecoration(
          color: AppColors.primary,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 40, color: Colors.white),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subLabel,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white70, size: 28),
          ],
        ),
      ),
    );
  }

  Widget _buildSecondaryButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.cardBg,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            Icon(icon, size: 24, color: AppColors.textPrimary),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.textMuted, size: 20),
          ],
        ),
      ),
    );
  }
}
