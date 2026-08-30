import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
  );
  bool _didPop = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _complete(String value) {
    if (_didPop) return;
    _didPop = true;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan Password QR')),
      body: MobileScanner(
        controller: _controller,
        onDetect: (capture) {
          if (_didPop) return;
          for (final barcode in capture.barcodes) {
            final value = barcode.rawValue;
            if (value == null) continue;
            final trimmed = value.trim();
            if (trimmed.isEmpty) continue;
            _complete(trimmed);
            return;
          }
        },
        errorBuilder: (context, error) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Camera error: ${error.errorDetails?.message ?? error.errorCode.name}',
                textAlign: TextAlign.center,
              ),
            ),
          );
        },
      ),
    );
  }
}
