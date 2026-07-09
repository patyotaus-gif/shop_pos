import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/restaurant_table.dart';
import '../services/auth_service.dart';
import '../services/entitlements.dart';
import '../services/image_service.dart';
import '../services/settings_service.dart';
import '../services/shop_service.dart';
import '../services/table_service.dart';
import '../utils/qr_pdf_generator.dart';

/// "QR สั่งอาหาร" — printable QR links into the customer order web page.
/// Takeaway QR for every tier with online ordering; per-table QRs (and the
/// dine-in mode switches) for the Restaurant tier.
class OrderQrScreen extends StatefulWidget {
  const OrderQrScreen({super.key});

  @override
  State<OrderQrScreen> createState() => _OrderQrScreenState();
}

class _OrderQrScreenState extends State<OrderQrScreen> {
  String? _shopId;
  String _shopName = '';
  bool _isRestaurant = false;
  String _mode = 'dineIn';
  bool _autoSend = false;
  String? _logoUrl;
  bool _busy = false;

  String get _baseUrl => 'https://pok-pok.app/order/?shop=$_shopId';
  String get _takeawayUrl => '$_baseUrl&mode=takeaway';
  String _tableUrl(String tableId) => '$_baseUrl&table=$tableId';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final shop = await ShopService.getCurrentShop();
    final settings = await SettingsService.getSettings();
    if (!mounted) return;
    setState(() {
      _shopId = AuthService.shopId;
      _shopName = shop?.name ?? '';
      _isRestaurant =
          shop != null && Entitlements.canUseTables(shop.tier);
      _mode = settings['tableOrderMode'] == 'prepaid' ? 'prepaid' : 'dineIn';
      _autoSend = settings['tableOrderAutoSend'] == true;
      _logoUrl = settings['logoUrl'] as String?;
    });
  }

  ImageProvider get _logoProvider => (_logoUrl?.isNotEmpty ?? false)
      ? NetworkImage(_logoUrl!) as ImageProvider
      : const AssetImage('assets/icon/icon.png');

  Widget _qr(String data, {double size = 150}) => QrImageView(
        data: data,
        size: size,
        // EC level H tolerates the ≤20% center logo without breaking scans.
        errorCorrectionLevel: QrErrorCorrectLevel.H,
        backgroundColor: Colors.white,
        embeddedImage: _logoProvider,
        embeddedImageStyle: QrEmbeddedImageStyle(size: Size(size * .18, size * .18)),
      );

  Future<void> _pickLogo() async {
    final picked =
        await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null || _shopId == null) return;
    setState(() => _busy = true);
    try {
      final url =
          await ImageService.saveShopLogo(File(picked.path), _shopId!);
      await SettingsService.saveSettings({'logoUrl': url});
      if (mounted) setState(() => _logoUrl = url);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('อัปโหลดโลโก้ไม่สำเร็จ: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _saveMode(String mode) async {
    setState(() => _mode = mode);
    await SettingsService.saveSettings({'tableOrderMode': mode});
  }

  Future<void> _saveAutoSend(bool v) async {
    setState(() => _autoSend = v);
    await SettingsService.saveSettings({'tableOrderAutoSend': v});
  }

  Future<Uint8List?> _logoBytes() async {
    final url = _logoUrl;
    if (url == null || url.isEmpty) return null;
    try {
      final res = await http.get(Uri.parse(url));
      return res.statusCode == 200 ? res.bodyBytes : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _exportPdf(List<({String label, String url})> entries) async {
    setState(() => _busy = true);
    try {
      await QrPdfGenerator.printQrSheets(
        shopName: _shopName,
        entries: entries,
        logoBytes: await _logoBytes(),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (_shopId == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('QR สั่งอาหาร')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('QR สั่งอาหาร'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_busy) const LinearProgressIndicator(),
          // ── โลโก้กลาง QR ──
          Row(children: [
            CircleAvatar(
                radius: 22, backgroundImage: _logoProvider),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                (_logoUrl?.isNotEmpty ?? false)
                    ? 'โลโก้ร้านแสดงกลาง QR ทุกใบ'
                    : 'ยังไม่มีโลโก้ร้าน — ใช้โลโก้ Pokpok ไปก่อน',
                style: const TextStyle(fontSize: 13),
              ),
            ),
            TextButton(
              onPressed: _busy ? null : _pickLogo,
              child: const Text('เปลี่ยนโลโก้'),
            ),
          ]),
          const Divider(height: 28),

          // ── Takeaway ──
          Text('สั่งกลับบ้าน (Takeaway)',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('ลูกค้าสแกน → สั่ง + จ่าย PromptPay ล่วงหน้า มารับที่ร้าน',
              style: TextStyle(
                  fontSize: 12, color: cs.onSurface.withValues(alpha: .6))),
          const SizedBox(height: 12),
          Center(child: _qr(_takeawayUrl, size: 180)),
          const SizedBox(height: 8),
          Center(
            child: TextButton.icon(
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('คัดลอกลิงก์'),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _takeawayUrl));
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('คัดลอกแล้ว')));
              },
            ),
          ),
          FilledButton.icon(
            onPressed: _busy
                ? null
                : () => _exportPdf(
                    [(label: 'รับกลับบ้าน', url: _takeawayUrl)]),
            icon: const Icon(Icons.print_outlined, size: 18),
            label: const Text('พิมพ์ / ส่งออก PDF'),
          ),

          if (_isRestaurant) ...[
            const Divider(height: 36),
            // ── โหมดโต๊ะ ──
            Text('QR ประจำโต๊ะ',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              initialValue: _mode,
              decoration: const InputDecoration(
                  labelText: 'เมื่อลูกค้าสแกน QR โต๊ะ',
                  border: OutlineInputBorder(),
                  isDense: true),
              items: const [
                DropdownMenuItem(
                    value: 'dineIn',
                    child: Text('สั่งเข้าครัว จ่ายทีหลัง (แนะนำ)')),
                DropdownMenuItem(
                    value: 'prepaid',
                    child: Text('จ่าย PromptPay ก่อน แบบสั่งออนไลน์')),
              ],
              onChanged: _busy
                  ? null
                  : (v) => _saveMode(v ?? 'dineIn'),
            ),
            if (_mode == 'dineIn')
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('ส่งเข้าครัวอัตโนมัติ'),
                subtitle: const Text(
                    'ปิด = รายการจากลูกค้ารอพนักงานกดส่งครัวก่อน (กันสั่งเล่น)'),
                value: _autoSend,
                onChanged: _busy ? null : _saveAutoSend,
              ),
            const SizedBox(height: 8),
            StreamBuilder<List<RestaurantTable>>(
              stream: TableService.watchTables(),
              builder: (ctx, snap) {
                final tables = snap.data ?? const <RestaurantTable>[];
                if (tables.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text('ยังไม่มีโต๊ะ — เพิ่มได้ที่หน้า "โต๊ะ"',
                        style: TextStyle(
                            color: cs.onSurface.withValues(alpha: .5))),
                  );
                }
                return Column(children: [
                  FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _exportPdf([
                              for (final t in tables)
                                (label: t.name, url: _tableUrl(t.id)),
                            ]),
                    icon: const Icon(Icons.print_outlined, size: 18),
                    label: Text('พิมพ์ QR ทุกโต๊ะ (${tables.length})'),
                  ),
                  const SizedBox(height: 8),
                  for (final t in tables)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: SizedBox(
                          width: 56, height: 56, child: _qr(_tableUrl(t.id), size: 56)),
                      title: Text(t.name),
                      subtitle: t.section != null ? Text(t.section!) : null,
                      trailing: IconButton(
                        icon: const Icon(Icons.print_outlined, size: 20),
                        tooltip: 'พิมพ์โต๊ะนี้',
                        onPressed: _busy
                            ? null
                            : () => _exportPdf(
                                [(label: t.name, url: _tableUrl(t.id))]),
                      ),
                    ),
                ]);
              },
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
