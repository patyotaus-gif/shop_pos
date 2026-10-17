import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../screens/bluetooth_printer_screen.dart';
import '../services/bluetooth_printer_service.dart';

/// Explicit printing only. Never retries or falls back automatically: the
/// printer may have received part of the job even when transport reports error.
class BluetoothPrintButton extends StatefulWidget {
  const BluetoothPrintButton({super.key, required this.buildPdf});
  final Future<Uint8List> Function(int paperMm) buildPdf;
  @override
  State<BluetoothPrintButton> createState() => _BluetoothPrintButtonState();
}

class _BluetoothPrintButtonState extends State<BluetoothPrintButton> {
  bool _busy = false;

  Future<void> _print() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      var config = await BluetoothPrinterService.saved();
      if (!mounted) return;
      config ??= await Navigator.push<BluetoothPrinterConfig>(context,
          MaterialPageRoute(builder: (_) => const BluetoothPrinterScreen()));
      if (config == null || !mounted) return;
      await BluetoothPrinterService.printPdf(
          await widget.buildPdf(config.paperMm), config);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'ส่งข้อมูลไป ${config.name} แล้ว กรุณาตรวจใบเสร็จที่เครื่อง')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(BluetoothPrinterService.errorMessage(e)),
            duration: const Duration(seconds: 8)));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!BluetoothPrinterService.supported) return const SizedBox.shrink();
    return Wrap(alignment: WrapAlignment.center, children: [
      TextButton.icon(
          onPressed: _busy ? null : _print,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.bluetooth),
          label: Text(_busy ? 'กำลังส่งพิมพ์…' : 'พิมพ์ Bluetooth')),
      IconButton(
          onPressed: _busy
              ? null
              : () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const BluetoothPrinterScreen())),
          tooltip: 'เลือกเครื่องพิมพ์ Bluetooth',
          icon: const Icon(Icons.settings_bluetooth)),
    ]);
  }
}
