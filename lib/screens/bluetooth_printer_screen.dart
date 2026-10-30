import '../widgets/compact_action.dart';
import '../widgets/content_width.dart';
import 'package:flutter/material.dart';
import '../services/bluetooth_printer_service.dart';

class BluetoothPrinterScreen extends StatefulWidget {
  const BluetoothPrinterScreen({super.key});
  @override
  State<BluetoothPrinterScreen> createState() => _BluetoothPrinterScreenState();
}

class _BluetoothPrinterScreenState extends State<BluetoothPrinterScreen> {
  List<BluetoothPrinterConfig> _devices = [];
  BluetoothPrinterConfig? _selected;
  int _paper = 58;
  bool _busy = false;
  String? _error;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _run(Future<void> Function() task) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      _notice = null;
    });
    try {
      await task();
    } catch (e) {
      if (mounted) {
        setState(() => _error = BluetoothPrinterService.errorMessage(e));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _load() => _run(() async {
        final saved = await BluetoothPrinterService.saved();
        final devices = await BluetoothPrinterService.pairedDevices();
        if (!mounted) return;
        setState(() {
          _devices = devices;
          _selected =
              devices.where((d) => d.address == saved?.address).firstOrNull;
          _paper = saved?.paperMm ?? 58;
        });
      });

  BluetoothPrinterConfig get _config => BluetoothPrinterConfig(
      address: _selected!.address, name: _selected!.name, paperMm: _paper);

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('เครื่องพิมพ์ Bluetooth')),
        body: ContentWidth(
            maxWidth: 760,
            child: SafeArea(
                child: ListView(padding: const EdgeInsets.all(16), children: [
              const Text(
                  'Android • เครื่องพิมพ์ Bluetooth Classic ที่รองรับ ESC/POS'),
              const SizedBox(height: 8),
              const Text(
                  'จับคู่เครื่องพิมพ์ในการตั้งค่ามือถือก่อน แล้วกลับมากดรีเฟรช '
                  'หาก RawBT หรือแอพอื่นเชื่อมอยู่ ให้ตัดการเชื่อมต่อก่อนพิมพ์จาก Pokpok'),
              Wrap(spacing: 8, children: [
                TextButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _run(BluetoothPrinterService.openSettings),
                    icon: const Icon(Icons.settings_bluetooth),
                    label: const Text('เปิดการตั้งค่า Bluetooth')),
                TextButton.icon(
                    onPressed: _busy ? null : _load,
                    icon: const Icon(Icons.refresh),
                    label: const Text('รีเฟรช')),
              ]),
              if (_busy) const LinearProgressIndicator(),
              if (_error != null)
                Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error))),
              if (_notice != null) Text(_notice!),
              if (!_busy && _devices.isEmpty)
                const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                        'ยังไม่พบเครื่องที่จับคู่ไว้ รองรับ Bluetooth Classic ในรุ่นนี้')),
              for (final device in _devices)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(_selected?.address == device.address
                      ? Icons.check_circle
                      : Icons.print_outlined),
                  title: Text(device.name),
                  subtitle: Text(device.address),
                  selected: _selected?.address == device.address,
                  onTap: _busy
                      ? null
                      : () => setState(() {
                            _selected = device;
                            _notice = null;
                          }),
                ),
              const SizedBox(height: 12),
              DropdownButtonFormField<int>(
                initialValue: _paper,
                key: ValueKey(_paper),
                decoration: const InputDecoration(labelText: 'ขนาดกระดาษ'),
                items: const [
                  DropdownMenuItem(value: 58, child: Text('58 มม. (384 จุด)')),
                  DropdownMenuItem(value: 80, child: Text('80 มม. (576 จุด)'))
                ],
                onChanged:
                    _busy ? null : (value) => setState(() => _paper = value!),
              ),
              const SizedBox(height: 16),
              CompactAction(
                  child: OutlinedButton.icon(
                      onPressed: _busy || _selected == null
                          ? null
                          : () => _run(() async {
                                final config = _config;
                                await BluetoothPrinterService.printPdf(
                                    await BluetoothPrinterService.testDocument(
                                        config.paperMm),
                                    config);
                                if (mounted) {
                                  setState(() => _notice =
                                      'ส่งข้อมูลแล้ว กรุณาตรวจว่ากระดาษออกครบและภาษาไทยถูกต้อง');
                                }
                              }),
                      icon: const Icon(Icons.print),
                      label: const Text('พิมพ์ทดสอบภาษาไทย'))),
              CompactAction(
                  child: FilledButton(
                      onPressed: _busy || _selected == null
                          ? null
                          : () => _run(() async {
                                final config = _config;
                                await BluetoothPrinterService.save(config);
                                if (context.mounted) {
                                  Navigator.pop(context, config);
                                }
                              }),
                      child: const Text('ใช้เครื่องนี้'))),
              CompactAction(
                  child: TextButton(
                      onPressed: _busy
                          ? null
                          : () => _run(() async {
                                await BluetoothPrinterService.forget();
                                if (mounted) {
                                  setState(() {
                                    _selected = null;
                                    _notice = 'ล้างเครื่องที่บันทึกไว้แล้ว';
                                  });
                                }
                              }),
                      child: const Text('ล้างเครื่องที่บันทึกไว้'))),
              const Text(
                  'บันทึกเฉพาะมือถือเครื่องนี้ การเลือกเครื่องยังไม่ยืนยันว่าพิมพ์ได้ '
                  'ควรพิมพ์ทดสอบก่อนใช้งานจริง'),
            ]))),
      );
}
