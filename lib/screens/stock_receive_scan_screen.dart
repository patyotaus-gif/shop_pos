import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../utils/operation_error.dart';

/// Scanning only selects a product. The existing stock form owns validation,
/// authorization, confirmation and idempotent persistence.
class StockReceiveScanScreen extends StatefulWidget {
  const StockReceiveScanScreen({super.key, required this.onCode, this.scan});
  final Future<void> Function(BuildContext context, String code) onCode;
  final Future<String?> Function(BuildContext context)? scan;

  @override
  State<StockReceiveScanScreen> createState() => _StockReceiveScanScreenState();
}

class _StockReceiveScanScreenState extends State<StockReceiveScanScreen> {
  final _code = TextEditingController();
  final _focus = FocusNode();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _code.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _open({bool camera = false}) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      var code = _code.text.trim();
      if (camera) {
        final scanned = await (widget.scan?.call(context) ??
            Navigator.push<String>(
                context,
                MaterialPageRoute(
                    builder: (_) => const InventoryCodeScanner())));
        if (!mounted || scanned == null) return;
        code = scanned.trim();
        _code.text = code;
      }
      if (code.isEmpty || code.length > 150) {
        throw StateError('กรอกรหัสสินค้า 1–150 ตัวอักษร');
      }
      if (!mounted) return;
      _focus.unfocus();
      await widget.onCode(context, code);
      if (mounted) _code.clear();
    } catch (e) {
      if (mounted) setState(() => _error = operationError(e));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
        _focus.requestFocus();
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('สแกนรับสินค้าเข้า')),
      body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('สแกน QR หรือบาร์โค้ดสินค้า แล้วตรวจจำนวนก่อนบันทึกรับเข้า'),
        const SizedBox(height: 12),
        OutlinedButton.icon(
            onPressed: _busy ? null : () => _open(camera: true),
            icon: const Icon(Icons.qr_code_scanner),
            label: const Text('เปิดกล้องสแกน')),
        const SizedBox(height: 12),
        TextField(
            controller: _code,
            focusNode: _focus,
            enabled: !_busy,
            maxLength: 150,
            textInputAction: TextInputAction.search,
            decoration: const InputDecoration(
                labelText: 'รหัส QR / บาร์โค้ดสินค้า',
                helperText: 'พิมพ์รหัส หรือใช้เครื่องสแกนแล้วกด Enter'),
            onSubmitted: (_) => _open()),
        FilledButton(
            onPressed: _busy ? null : () => _open(),
            child: Text(_busy ? 'กำลังทำรายการ…' : 'ค้นหาเพื่อรับสินค้าเข้า')),
        const SizedBox(height: 12),
        const Text('รหัสต้องตรงกับช่องบาร์โค้ดที่บันทึกไว้ในสินค้า '
            'สแกนอย่างเดียวยังไม่เพิ่มสต๊อก'),
        if (_error != null)
          Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_error!,
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error))),
      ])));
}

class InventoryCodeScanner extends StatefulWidget {
  const InventoryCodeScanner({super.key});
  @override
  State<InventoryCodeScanner> createState() => _InventoryCodeScannerState();
}

class _InventoryCodeScannerState extends State<InventoryCodeScanner> {
  bool _done = false;
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('สแกน QR / บาร์โค้ดสินค้า')),
      body: SafeArea(
          child: MobileScanner(
              errorBuilder: (context, error) => const Center(
                  child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('เปิดกล้องไม่สำเร็จ กรุณาตรวจสิทธิ์กล้อง '
                          'หรือกลับไปกรอกรหัสสินค้า'))),
              onDetect: (capture) {
                final value = capture.barcodes.firstOrNull?.rawValue?.trim();
                if (!_done && value != null && value.isNotEmpty) {
                  _done = true;
                  Navigator.pop(context, value);
                }
              })));
}
