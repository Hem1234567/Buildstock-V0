import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Called for every code in continuous mode. Return a short message to show to
/// the user (for example "Added Cement 50kg") or null for no message.
typedef ScanHandler = Future<String?> Function(String code);

/// Full screen camera scanner built on `mobile_scanner`.
///
/// * Single mode (default): closes with the first code and returns it.
/// * Continuous mode (`onScan` given): stays open, calls [onScan] for each new
///   code and shows its message. Used for fast billing at the counter.
class BarcodeScannerScreen extends StatefulWidget {
  const BarcodeScannerScreen({
    super.key,
    this.title = 'Scan barcode',
    this.hint = 'Point the camera at a barcode or QR code',
    this.qrOnly = false,
    this.onScan,
  });

  final String title;
  final String hint;
  final bool qrOnly;
  final ScanHandler? onScan;

  /// Opens the scanner and returns the scanned text (single mode).
  static Future<String?> open(
    BuildContext context, {
    String title = 'Scan barcode',
    String hint = 'Point the camera at a barcode or QR code',
    bool qrOnly = false,
  }) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            BarcodeScannerScreen(title: title, hint: hint, qrOnly: qrOnly),
      ),
    );
  }

  /// Opens the scanner in continuous mode.
  static Future<void> openContinuous(
    BuildContext context, {
    required ScanHandler onScan,
    String title = 'Scan products',
    String hint = 'Scan each product. Tap done when finished.',
  }) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) =>
            BarcodeScannerScreen(title: title, hint: hint, onScan: onScan),
      ),
    );
  }

  @override
  State<BarcodeScannerScreen> createState() => _BarcodeScannerScreenState();
}

class _BarcodeScannerScreenState extends State<BarcodeScannerScreen> {
  late final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: widget.qrOnly ? const [BarcodeFormat.qrCode] : const [],
  );

  bool _torchOn = false;
  bool _handled = false;
  String? _message;
  String? _lastCode;
  DateTime _lastAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled) return;
    String? code;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue;
      if (value != null && value.trim().isNotEmpty) {
        code = value.trim();
        break;
      }
    }
    if (code == null) return;

    final handler = widget.onScan;
    if (handler == null) {
      _handled = true;
      if (mounted) Navigator.of(context).pop(code);
      return;
    }

    // Continuous mode: ignore the same code seen again within 1.5 seconds.
    final now = DateTime.now();
    if (code == _lastCode && now.difference(_lastAt).inMilliseconds < 1500) {
      return;
    }
    _lastCode = code;
    _lastAt = now;
    try {
      final message = await handler(code);
      if (mounted) setState(() => _message = message ?? 'Scanned $code');
    } catch (error) {
      if (mounted) setState(() => _message = error.toString());
    }
  }

  Future<void> _typeCode() async {
    final controller = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter code'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Barcode / number'),
          onSubmitted: (text) => Navigator.pop(context, text.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Use'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (value == null || value.isEmpty || !mounted) return;
    final handler = widget.onScan;
    if (handler == null) {
      Navigator.of(context).pop(value);
    } else {
      final message = await handler(value);
      if (mounted) setState(() => _message = message ?? 'Scanned $value');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.title),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Type code',
            icon: const Icon(Icons.keyboard_alt_outlined),
            onPressed: _typeCode,
          ),
          IconButton(
            tooltip: 'Torch',
            icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
            onPressed: () async {
              await _controller.toggleTorch();
              if (mounted) setState(() => _torchOn = !_torchOn);
            },
          ),
          IconButton(
            tooltip: 'Switch camera',
            icon: const Icon(Icons.cameraswitch_outlined),
            onPressed: () => _controller.switchCamera(),
          ),
          if (widget.onScan != null)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done', style: TextStyle(color: Colors.white)),
            ),
        ],
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(controller: _controller, onDetect: _onDetect),
          Center(
            child: Container(
              width: 280,
              height: widget.qrOnly ? 280 : 160,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 2.5),
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
          Positioned(
            left: 24,
            right: 24,
            bottom: 36,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_message != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _message!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                Text(
                  widget.hint,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
