import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../utils/app_colors.dart';

/// 商品图片显示组件
/// 自动判断是本地文件路径还是网络URL，使用对应方式显示
class GoodsImage extends StatelessWidget {
  final String? imagePath;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;

  const GoodsImage({
    super.key,
    required this.imagePath,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
  });

  bool get _isLocalFile {
    if (imagePath == null || imagePath!.isEmpty) return false;
    return imagePath!.startsWith('/') || imagePath!.startsWith('file://');
  }

  bool get _isNetworkUrl {
    if (imagePath == null || imagePath!.isEmpty) return false;
    return imagePath!.startsWith('http://') || imagePath!.startsWith('https://');
  }

  @override
  Widget build(BuildContext context) {
    if (imagePath == null || imagePath!.isEmpty) {
      return _buildPlaceholder();
    }

    Widget imageWidget;

    if (_isLocalFile) {
      // 本地文件
      final file = File(imagePath!);
      imageWidget = Image.file(
        file,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, __, ___) => _buildPlaceholder(),
      );
    } else if (_isNetworkUrl) {
      // 网络图片
      imageWidget = CachedNetworkImage(
        imageUrl: imagePath!,
        width: width,
        height: height,
        fit: fit,
        placeholder: (_, __) => _buildLoading(),
        errorWidget: (_, __, ___) => _buildPlaceholder(),
      );
    } else {
      // 未知类型，尝试网络加载
      imageWidget = CachedNetworkImage(
        imageUrl: imagePath!,
        width: width,
        height: height,
        fit: fit,
        placeholder: (_, __) => _buildLoading(),
        errorWidget: (_, __, ___) => _buildPlaceholder(),
      );
    }

    if (borderRadius != null) {
      return ClipRRect(
        borderRadius: borderRadius!,
        child: imageWidget,
      );
    }

    return imageWidget;
  }

  Widget _buildPlaceholder() {
    return Container(
      width: width,
      height: height,
      color: AppColors.cardBg,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_not_supported, size: 32, color: AppColors.textMuted),
            SizedBox(height: 4),
            Text('暂无图片', style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildLoading() {
    return Container(
      width: width,
      height: height,
      color: AppColors.cardBg,
      child: const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: AppColors.primary,
          ),
        ),
      ),
    );
  }
}
