import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../utils/app_colors.dart';

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});

  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> with SingleTickerProviderStateMixin {
  late AnimationController _lineController;
  final MobileScannerController _controller = MobileScannerController(
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.code128,
    ],
  );
  bool _isScanning = true;

  @override
  void initState() {
    super.initState();
    _lineController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  void _onDetect(BarcodeCapture capture) {
    if (!_isScanning) return;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && value.isNotEmpty) {
        setState(() => _isScanning = false);
        _controller.stop();
        Navigator.pop(context, value);
        return;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _lineController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scanAreaSize = MediaQuery.of(context).size.width * 0.75;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          _buildOverlay(scanAreaSize),
          _buildHeader(),
          _buildFooter(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.arrow_back, color: Colors.white),
            ),
            const Expanded(
              child: Text(
                '对准条码自动扫描',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),
            ),
            const SizedBox(width: 48),
          ],
        ),
      ),
    );
  }

  Widget _buildOverlay(double size) {
    final borderWidth = MediaQuery.of(context).size.width;
    final borderHeight = MediaQuery.of(context).size.height;
    final left = (borderWidth - size) / 2;
    final top = (borderHeight - size) / 2;

    return Stack(
      children: [
        _buildDarkOverlay(left, top, size, borderWidth, borderHeight),
        Positioned(
          left: left,
          top: top,
          width: size,
          height: size,
          child: _buildScanFrame(size),
        ),
      ],
    );
  }

  Widget _buildDarkOverlay(
    double left,
    double top,
    double size,
    double width,
    double height,
  ) {
    return Stack(
      children: [
        Positioned(top: 0, left: 0, right: 0, height: top, child: _darkMask()),
        Positioned(bottom: 0, left: 0, right: 0, height: height - top - size, child: _darkMask()),
        Positioned(top: top, left: 0, width: left, height: size, child: _darkMask()),
        Positioned(top: top, right: 0, width: left, height: size, child: _darkMask()),
      ],
    );
  }

  Widget _darkMask() => Container(color: Colors.black54);

  Widget _buildScanFrame(double size) {
    const cornerLength = 24.0;
    const cornerThickness = 3.0;
    const cornerColor = AppColors.accent;

    return Stack(
      children: [
        // 左上角
        Positioned(top: 0, left: 0, child: _corner(cornerLength, cornerThickness, cornerColor, true, true)),
        // 右上角
        Positioned(top: 0, right: 0, child: _corner(cornerLength, cornerThickness, cornerColor, false, true)),
        // 左下角
        Positioned(bottom: 0, left: 0, child: _corner(cornerLength, cornerThickness, cornerColor, true, false)),
        // 右下角
        Positioned(bottom: 0, right: 0, child: _corner(cornerLength, cornerThickness, cornerColor, false, false)),
        // 扫描线
        AnimatedBuilder(
          animation: _lineController,
          builder: (_, __) {
            return Positioned(
              top: _lineController.value * (size - 2),
              left: 0,
              right: 0,
              child: Container(height: 2, color: cornerColor.withOpacity(0.8)),
            );
          },
        ),
      ],
    );
  }

  Widget _corner(double length, double thickness, Color color, bool left, bool top) {
    return SizedBox(
      width: length,
      height: length,
      child: Stack(
        children: [
          Positioned(
            top: top ? 0 : null,
            bottom: !top ? 0 : null,
            left: left ? 0 : null,
            right: !left ? 0 : null,
            child: Container(
              width: left ? length : thickness,
              height: top ? thickness : length,
              color: color,
            ),
          ),
          Positioned(
            top: top ? 0 : null,
            bottom: !top ? 0 : null,
            left: left ? 0 : null,
            right: !left ? 0 : null,
            child: Container(
              width: left ? thickness : length,
              height: top ? length : thickness,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    return Positioned(
      bottom: 40,
      left: 0,
      right: 0,
      child: Center(
        child: Column(
          children: [
            const Text(
              '支持 EAN-13 / EAN-8 / CODE-128',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close),
              label: const Text('取消'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white24,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
