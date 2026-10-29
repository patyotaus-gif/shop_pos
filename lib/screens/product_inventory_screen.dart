import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../models/product.dart';
import '../services/inventory_service.dart';
import '../services/shop_database.dart';
import '../utils/stock_quantity.dart';
import '../utils/operation_error.dart';
import 'stock_receive_scan_screen.dart';

Future<void> openStockReceiveScanner(BuildContext context) => Navigator.push<
        void>(
    context,
    MaterialPageRoute(
        builder: (_) => StockReceiveScanScreen(onCode: (context, code) async {
              final matches = await ShopDatabase.shop
                  .collection('products')
                  .where('barcode', isEqualTo: code)
                  .limit(2)
                  .get();
              if (matches.docs.isEmpty) {
                throw StateError(
                    'ไม่พบสินค้า กรุณาตรวจรหัสในช่องบาร์โค้ดของสินค้า');
              }
              if (matches.docs.length > 1) {
                throw StateError(
                    'รหัสนี้ซ้ำหลายสินค้า ให้เจ้าของร้านแก้รหัสก่อนรับเข้า');
              }
              final doc = matches.docs.single;
              final product = Product.fromFirestore(doc.data(), doc.id);
              if (product.isRecipeMode) {
                throw StateError(
                    'สินค้านี้ใช้สูตร กรุณารับเข้าที่หน้าวัตถุดิบ');
              }
              if (!context.mounted) return;
              await showDialog<void>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) =>
                      _StockDialog(product: product, kind: 'receive'));
            })));

class ProductInventoryScreen extends StatelessWidget {
  const ProductInventoryScreen({super.key, required this.productId});
  final String productId;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('จัดการสต๊อก')),
        body: StreamBuilder<Product?>(
            stream: InventoryService.watchProduct(productId),
            builder: (context, snap) {
              if (snap.hasError) {
                return const Center(child: Text('โหลดสินค้าไม่สำเร็จ'));
              }
              if (!snap.hasData) {
                return const Center(child: Text('กำลังโหลด หรือไม่พบสินค้า'));
              }
              final p = snap.data!;
              if (p.isRecipeMode) {
                return const Center(
                    child:
                        Text('สินค้านี้ตัดตามสูตร จัดการสต๊อกที่หน้าวัตถุดิบ'));
              }
              return ListView(padding: const EdgeInsets.all(16), children: [
                OutlinedButton.icon(
                    onPressed: () => openStockReceiveScanner(context),
                    icon: const Icon(Icons.qr_code_scanner),
                    label: const Text('สแกนรับสินค้าเข้า')),
                Text(p.name, style: Theme.of(context).textTheme.titleLarge),
                Text(
                    'SKU ${p.sku.isEmpty ? 'ยังไม่กำหนด' : p.sku} • ${p.unit}'),
                if (p.storageLocation.isNotEmpty)
                  Text('จัดเก็บ: ${p.storageLocation}'),
                const SizedBox(height: 12),
                StreamBuilder<num>(
                    stream: InventoryService.watchReserved(productId),
                    builder: (context, held) {
                      if (!held.hasData) {
                        return Text(held.hasError
                            ? 'โหลดจำนวนจองไม่สำเร็จ'
                            : 'กำลังตรวจจำนวนจอง');
                      }
                      final available =
                          (p.saleable - held.data!).clamp(0, double.infinity);
                      return Wrap(spacing: 8, runSpacing: 8, children: [
                        Chip(
                            label: Text(
                                'คงเหลือ ${stockText(p.stock)} ${p.unit}')),
                        Chip(
                            label: Text('จองออนไลน์ ${stockText(held.data!)}')),
                        Chip(label: Text('พร้อมขาย ${stockText(available)}')),
                        if (p.stock > p.saleable)
                          Chip(
                              label: Text(
                                  'หมดอายุ ${stockText(p.stock - p.saleable)}')),
                      ]);
                    }),
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  for (final entry in const {
                    'receive': 'รับสินค้าเข้า',
                    'count': 'ตรวจนับ',
                    'waste': 'ของเสีย / ตัดออก'
                  }.entries)
                    OutlinedButton(
                        onPressed: () => showDialog<void>(
                            context: context,
                            builder: (_) =>
                                _StockDialog(product: p, kind: entry.key)),
                        child: Text(entry.value)),
                ]),
                if (p.trackLots) ...[
                  const SizedBox(height: 16),
                  Text('ล็อตสินค้า',
                      style: Theme.of(context).textTheme.titleMedium),
                  for (final lot in p.stockLots)
                    ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                            '${lot['number']} • ${stockText(lot['quantity'] as num)} ${p.unit}'),
                        subtitle: Text(
                            'หมดอายุ ${lot['expiresOn']}${(lot['expiresOn'] as String).compareTo(stockToday()) < 0 ? ' • ห้ามขาย' : ''}')),
                ],
                const Divider(height: 32),
                Text('ประวัติสต๊อกล่าสุด 100 รายการ',
                    style: Theme.of(context).textTheme.titleMedium),
                const Text(
                    'เริ่มเก็บเมื่อใช้งานระบบสต๊อกรุ่นนี้ รายการเก่ายังอยู่ในประวัติการขาย'),
                StreamBuilder<List<Map<String, dynamic>>>(
                    stream: InventoryService.history(productId),
                    builder: (context, history) {
                      if (history.hasError) {
                        return const Text('โหลดประวัติไม่สำเร็จ');
                      }
                      if (!history.hasData) {
                        return const LinearProgressIndicator();
                      }
                      if (history.data!.isEmpty) {
                        return const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text('ยังไม่มีรายการ'));
                      }
                      return Column(children: [
                        for (final row in history.data!)
                          ListTile(
                              contentPadding: EdgeInsets.zero,
                              title: Text('${const {
                                    'opening': 'ยอดเริ่มต้น',
                                    'receive': 'รับเข้า',
                                    'count': 'ตรวจนับ',
                                    'waste': 'ของเสีย',
                                    'sale': 'ขาย',
                                    'refund': 'คืนสินค้า'
                                  }[row['kind']] ?? row['kind']} ${stockText(row['delta'] as num)} ${row['unit'] ?? ''}'),
                              subtitle: Text(
                                  '${row['reason'] ?? ''}${row['lot'] is Map ? '\nล็อต ${(row['lot'] as Map)['number']}' : ''}${(row['documentNumber'] as String? ?? '').isNotEmpty ? '\nเอกสาร ${row['documentNumber']}' : ''}\n${row['createdAt'] is Timestamp ? (row['createdAt'] as Timestamp).toDate().toLocal().toString().split('.').first : 'กำลังบันทึก'}${row['referenceId'] != null ? '\nอ้างอิง ${row['referenceId']}' : ''}'),
                              trailing: Text(
                                  'เหลือ ${stockText(row['after'] as num)}'))
                      ]);
                    }),
              ]);
            }),
      );
}

class _StockDialog extends StatefulWidget {
  const _StockDialog({required this.product, required this.kind});
  final Product product;
  final String kind;
  @override
  State<_StockDialog> createState() => _StockDialogState();
}

class _StockDialogState extends State<_StockDialog> {
  final qty = TextEditingController(),
      cost = TextEditingController(),
      reason = TextEditingController(),
      document = TextEditingController(),
      lotNumber = TextEditingController(),
      expiry = TextEditingController();
  bool busy = false, loading = true, packs = false;
  String? lotId;
  Map<String, dynamic>? pending;
  String? error;
  String get key =>
      'pending-stock-${ShopDatabase.shop.id}-${widget.product.id}';
  @override
  void initState() {
    super.initState();
    reason.text = widget.kind == 'receive' ? 'รับสินค้าเข้า' : '';
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(key);
      if (mounted) {
        setState(() {
          pending = stored == null
              ? null
              : Map<String, dynamic>.from(jsonDecode(stored) as Map);
          loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = 'อ่านรายการรอยืนยันไม่สำเร็จ กรุณาปิดหน้านี้แล้วลองใหม่';
          loading = true;
        });
      }
    }
  }

  @override
  void dispose() {
    for (final c in [qty, cost, reason, document, lotNumber, expiry]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> submit() async {
    if (busy || loading) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      if (pending == null) {
        final quantity = num.tryParse(qty.text.trim());
        final totalCost =
            cost.text.trim().isEmpty ? null : double.tryParse(cost.text.trim());
        if (quantity == null ||
            !quantity.isFinite ||
            (totalCost != null && !totalCost.isFinite) ||
            (cost.text.trim().isNotEmpty && totalCost == null)) {
          throw StateError('กรอกจำนวนและต้นทุนให้ถูกต้อง');
        }
        pending = {
          'id': const Uuid().v4(),
          'kind': widget.kind,
          'quantity': quantity,
          'reason': reason.text.trim(),
          'expectedStock': widget.product.stock,
          'expectedRevision': widget.product.stockRevision,
          'totalCost': totalCost,
          'packSize': packs ? widget.product.unitsPerPack : 1,
          'documentNumber': document.text.trim(),
          'lotId': lotId,
          'lotNumber': lotNumber.text.trim(),
          'expiresOn': expiry.text.trim()
        };
        if (!await prefs.setString(key, jsonEncode(pending))) {
          throw StateError('เก็บคำขอไม่สำเร็จ');
        }
      }
      final r = pending!;
      await InventoryService.change(
              productId: widget.product.id,
              requestId: r['id'],
              kind: r['kind'],
              quantity: r['quantity'],
              reason: r['reason'],
              expectedStock: r['expectedStock'],
              expectedRevision: r['expectedRevision'],
              totalCost: (r['totalCost'] as num?)?.toDouble(),
              packSize: r['packSize'],
              documentNumber: r['documentNumber'],
              lotId: r['lotId'],
              lotNumber: r['lotNumber'],
              expiresOn: r['expiresOn'])
          .timeout(const Duration(seconds: 25));
      await prefs.remove(key);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (e is StateError) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(key);
        pending = null;
      }
      if (mounted) setState(() => error = operationError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    return AlertDialog(
        title: Text(p.name),
        scrollable: true,
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          if (loading) const LinearProgressIndicator(),
          if (pending != null)
            Text(
                'มีรายการรอยืนยัน: ${pending!['kind']} ${pending!['quantity']} • ${pending!['reason']}\nกดยืนยันรายการเดิมก่อนทำรายการใหม่'),
          if (pending == null) ...[
            Text('คงเหลือขณะเปิด ${stockText(p.stock)} ${p.unit}'),
            if (widget.kind == 'receive' && p.unitsPerPack != 1)
              SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                      'รับเป็น${p.packUnit} (1 = ${p.unitsPerPack} ${p.unit})'),
                  value: packs,
                  onChanged: busy ? null : (v) => setState(() => packs = v)),
            if (p.trackLots && widget.kind != 'receive')
              DropdownButtonFormField<String>(
                  initialValue: lotId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'เลือกล็อต'),
                  items: [
                    for (final l in p.stockLots)
                      DropdownMenuItem(
                          value: l['id'] as String,
                          child: Text('${l['number']} (${l['quantity']})',
                              overflow: TextOverflow.ellipsis))
                  ],
                  onChanged: busy ? null : (v) => setState(() => lotId = v)),
            for (final field in [
              (
                qty,
                widget.kind == 'count'
                    ? 'จำนวนที่นับได้จริง${p.trackLots ? 'ในล็อตนี้' : ''}'
                    : 'จำนวน${packs ? p.packUnit : p.unit}'
              ),
              if (widget.kind == 'receive')
                (cost, 'ต้นทุนรวมที่รับเข้า (เว้นว่างไม่เปลี่ยนต้นทุน)'),
              (reason, 'เหตุผล *'),
              (document, 'เลขเอกสาร (ถ้ามี)'),
              if (p.trackLots && widget.kind == 'receive') ...[
                (lotNumber, 'เลขล็อต *'),
                (expiry, 'วันหมดอายุ YYYY-MM-DD *')
              ],
            ])
              Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: TextField(
                      controller: field.$1,
                      enabled: !busy,
                      keyboardType: field.$1 == qty || field.$1 == cost
                          ? const TextInputType.numberWithOptions(decimal: true)
                          : TextInputType.text,
                      decoration: InputDecoration(
                          labelText: field.$2,
                          border: const OutlineInputBorder()))),
          ],
          if (error != null)
            Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error))),
        ]),
        actions: [
          TextButton(
              onPressed: busy ? null : () => Navigator.pop(context),
              child: const Text('ปิด')),
          FilledButton(
              onPressed: busy || loading ? null : submit,
              child: Text(busy
                  ? 'กำลังยืนยัน…'
                  : pending == null
                      ? 'บันทึก'
                      : 'ยืนยันรายการเดิม')),
        ]);
  }
}
