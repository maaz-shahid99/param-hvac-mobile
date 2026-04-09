import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class QRScannerPage extends StatefulWidget {
  const QRScannerPage({super.key});

  @override
  State<QRScannerPage> createState() => _QRScannerPageState();
}

class _QRScannerPageState extends State<QRScannerPage> {
  // 1. autoStart is false so we can delay it for the page transition
  final MobileScannerController _controller = MobileScannerController(
    autoStart: false,
  );

  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    // 2. Safely start the camera after the first frame is rendered
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 500), () async {
        if (mounted) {
          try {
            await _controller.start();
          } catch (e) {
            debugPrint("Camera Start Error: $e");
          }
        }
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleBarcode(BarcodeCapture capture) {
    if (_isProcessing) return;

    final barcode = capture.barcodes.firstOrNull;
    if (barcode?.rawValue == null) return;

    setState(() => _isProcessing = true);
    HapticFeedback.mediumImpact();

    final data = barcode!.rawValue!;

    // Check if it's the Thread standard format: v=1&&eui=...&&cc=...
    final RegExp threadRegex = RegExp(r'eui=([0-9a-fA-F]+).*cc=([A-Za-z0-9]+)');
    final match = threadRegex.firstMatch(data);

    if (match != null) {
      final eui64 = match.group(1)!;
      final pskd = match.group(2)!;

      _controller.stop().then((_) {
        if (mounted) {
          Navigator.pop(context, {'eui64': eui64, 'pskd': pskd});
        }
      });
    } else {
      final parts = data.contains('|') ? data.split('|') : data.split(' ');
      if (parts.length >= 2) {
        final eui64 = parts[0].trim();
        final pskd = parts[1].trim();

        _controller.stop().then((_) {
          if (mounted) {
            Navigator.pop(context, {'eui64': eui64, 'pskd': pskd});
          }
        });
      } else {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid QR format. Scan a valid Thread device.'),
            backgroundColor: Colors.red,
          ),
        );
        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) setState(() => _isProcessing = false);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan QR Code'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.flip_camera_ios),
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          // 3. MobileScanner MUST be in the tree immediately!
          MobileScanner(
            controller: _controller,
            onDetect: _handleBarcode,
            // FIXED: Removed the 'child' parameter
            placeholderBuilder: (context) {
              return const Center(
                child: CircularProgressIndicator(),
              );
            },
          ),
          // Viewfinder UI
          Center(
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),

          // Bottom Text UI
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.black87,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Text(
                  'Align QR code within frame',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}