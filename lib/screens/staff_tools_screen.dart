import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import '../models/sale.dart';
import '../services/staff_access_service.dart';
import '../utils/operation_error.dart';
import '../widgets/shop_operation.dart';
import 'cash_session_screen.dart';
import 'sale_receipt_screen.dart';

class StaffToolsScreen extends StatefulWidget {
  const StaffToolsScreen({super.key});
  @override
  State<StaffToolsScreen> createState() => _StaffToolsScreenState();
}

class _StaffToolsScreenState extends State<StaffToolsScreen> {
  late Future<Map<String, dynamic>> _workspace = StaffAccessService.workspace();
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('สิทธิ์เพิ่มเติม')),
      body: FutureBuilder<Map<String, dynamic>>(
          future: _workspace,
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(
                  child: TextButton(
                      onPressed: () => setState(
                          () => _workspace = StaffAccessService.workspace()),
                      child: Text(operationError(snap.error!))));
            }
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final p = snap.data!['permissions'] as Map? ?? {};
            return ListView(children: [
              ListTile(
                  title: Text('พนักงาน: ${snap.data!['staffName']}'),
                  subtitle: const Text('สิทธิ์เพิ่มเติมกำหนดโดยเจ้าของร้าน')),
              if (p['cashSession'] == true)
                ListTile(
                    leading: const Icon(Icons.point_of_sale),
                    title: const Text('เปิด–ปิดรอบ'),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                            builder: (_) => const CashSessionScreen()))),
              if (p['reports'] == true)
                ListTile(
                    leading: const Icon(Icons.assessment_outlined),
                    title: const Text('รายงานยอดขาย'),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                            builder: (_) => const _StaffReport()))),
              if (p['cost'] == true || p['stock'] == true)
                ListTile(
                    leading: const Icon(Icons.inventory_2_outlined),
                    title: Text(p['stock'] == true
                        ? 'ตรวจนับสต๊อกสินค้า'
                        : 'ต้นทุนสินค้า'),
                    onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                            builder: (_) => const _StaffInventory()))),
              for (final entry in const {
                'discount': 'ลดราคาในหน้ารับชำระ / ใช้คูปองบิลโต๊ะ',
                'cancel': 'ยกเลิกบิลโต๊ะและออเดอร์ที่ยังไม่ชำระ',
                'refund': 'คืนเงินจากหน้าใบเสร็จ'
              }.entries)
                ListTile(
                    title: Text(entry.value),
                    trailing: Icon(p[entry.key] == true
                        ? Icons.check_circle
                        : Icons.lock_outline)),
            ]);
          }));
}

class _StaffReport extends StatefulWidget {
  const _StaffReport();
  @override
  State<_StaffReport> createState() => _StaffReportState();
}

class _StaffReportState extends State<_StaffReport> {
  DateTimeRange _range = DateTimeRange(
      start: DateUtils.dateOnly(DateTime.now()),
      end: DateUtils.dateOnly(DateTime.now()));
  late Future<Map<String, dynamic>> _data = _load();
  Future<Map<String, dynamic>> _load() => StaffAccessService.work('report', {
        'from': _range.start.toUtc().toIso8601String(),
        'to': _range.end.add(const Duration(days: 1)).toUtc().toIso8601String()
      });
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('รายงานยอดขาย')),
      body: Column(children: [
        ListTile(
            title: Text(
                '${DateFormat('dd/MM/yyyy').format(_range.start)} – ${DateFormat('dd/MM/yyyy').format(_range.end)}'),
            subtitle: const Text('เลือกช่วงไม่เกิน 31 วัน · เวลาตามเครื่องนี้'),
            trailing: const Icon(Icons.date_range),
            onTap: () async {
              final selected = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                  initialDateRange: _range);
              if (selected != null && context.mounted) {
                if (selected.duration.inDays > 30) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('เลือกได้ไม่เกิน 31 วัน')));
                  return;
                }
                setState(() {
                  _range = selected;
                  _data = _load();
                });
              }
            }),
        Expanded(
            child: FutureBuilder<Map<String, dynamic>>(
                future: _data,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return Center(
                        child: TextButton(
                            onPressed: () => setState(() => _data = _load()),
                            child: Text(operationError(snap.error!))));
                  }
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final sales = (snap.data!['records'] as List)
                      .map((r) => Sale.fromFirestore(
                          StaffAccessService.firestoreDates(r as Map),
                          r['id'] as String))
                      .toList()
                    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
                  final total = sales
                      .where((s) => !s.isRefunded)
                      .fold<double>(0, (v, s) => v + s.total);
                  return ListView(children: [
                    ListTile(
                        title: Text(
                            'ยอดบิลที่ยังไม่คืนเงิน ฿${total.toStringAsFixed(2)}'),
                        subtitle: const Text(
                            'ตามวันขายของบิล ไม่ใช่กระแสเงินสดหรือยอดรับเงินในรอบ')),
                    if (sales.isEmpty)
                      const ListTile(title: Text('ไม่มีรายการขายในช่วงนี้')),
                    for (final sale in sales)
                      ListTile(
                          title: Text(
                              '${sale.receiptNo ?? sale.id} · ฿${sale.total.toStringAsFixed(2)}'),
                          subtitle: Text(
                              '${sale.staffName ?? ''}${sale.isRefunded ? ' · คืนเงินแล้ว' : ''}'),
                          onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute<void>(
                                  builder: (_) => SaleReceiptScreen(
                                      saleId: sale.id, allowRefund: true)))),
                  ]);
                }))
      ]));
}

class _StaffInventory extends StatefulWidget {
  const _StaffInventory();
  @override
  State<_StaffInventory> createState() => _StaffInventoryState();
}

class _StaffInventoryState extends State<_StaffInventory> {
  late Future<Map<String, dynamic>> _data = StaffAccessService.work('products');
  void _reload() => setState(() => _data = StaffAccessService.work('products'));
  Future<void> _count(Map p) async {
    final lots = (p['stockLots'] as List? ?? []).cast<Map>();
    String? lotId = lots.firstOrNull?['id'] as String?;
    final quantity = TextEditingController();
    final reason = TextEditingController();
    final requestId = const Uuid().v4();
    bool busy = false;
    await showDialog<void>(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, setDialog) => AlertDialog(
                    title: Text('ตรวจนับ ${p['name']}'),
                    content: SingleChildScrollView(
                        child:
                            Column(mainAxisSize: MainAxisSize.min, children: [
                      if (p['trackLots'] == true)
                        DropdownButtonFormField<String>(
                            initialValue: lotId,
                            isExpanded: true,
                            decoration:
                                const InputDecoration(labelText: 'ล็อตสินค้า'),
                            items: lots
                                .map((l) => DropdownMenuItem(
                                    value: l['id'] as String,
                                    child: Text(
                                        '${l['number']} · ${l['expiresOn']}')))
                                .toList(),
                            onChanged: busy
                                ? null
                                : (v) => setDialog(() => lotId = v)),
                      TextField(
                          controller: quantity,
                          enabled: !busy,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: InputDecoration(
                              labelText: 'จำนวนที่นับได้ (${p['unit']})')),
                      TextField(
                          controller: reason,
                          enabled: !busy,
                          maxLength: 300,
                          decoration: const InputDecoration(
                              labelText: 'เหตุผลตรวจนับ')),
                    ])),
                    actions: [
                      TextButton(
                          onPressed: busy ? null : () => Navigator.pop(ctx),
                          child: const Text('ยกเลิก')),
                      FilledButton(
                          onPressed: busy
                              ? null
                              : () async {
                                  final q = num.tryParse(quantity.text.trim());
                                  if (q == null ||
                                      q < 0 ||
                                      reason.text.trim().isEmpty) {
                                    return;
                                  }
                                  setDialog(() => busy = true);
                                  final ok = await performShopOperation(
                                      ctx,
                                      () => StaffAccessService.work(
                                              'stockCount', {
                                            'productId': p['id'],
                                            'requestId': requestId,
                                            'quantity': q,
                                            'expectedRevision':
                                                p['stockRevision'],
                                            'reason': reason.text.trim(),
                                            'lotId': lotId
                                          }).then((_) {}),
                                      success: 'บันทึกตรวจนับแล้ว');
                                  if (ctx.mounted) {
                                    if (ok) {
                                      Navigator.pop(ctx);
                                    } else {
                                      setDialog(() => busy = false);
                                    }
                                  }
                                },
                          child: Text(busy ? 'กำลังบันทึก…' : 'บันทึก'))
                    ])));
    quantity.dispose();
    reason.dispose();
    if (mounted) _reload();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('สินค้า / ตรวจนับ'), actions: [
        IconButton(onPressed: _reload, icon: const Icon(Icons.refresh))
      ]),
      body: FutureBuilder<Map<String, dynamic>>(
          future: _data,
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(child: Text(operationError(snap.error!)));
            }
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final rows = (snap.data!['records'] as List).cast<Map>();
            return ListView(children: [
              const ListTile(
                  subtitle: Text(
                      'ตรวจนับจำนวนคงเหลือ สินค้าแบบล็อตต้องเลือกล็อตเดิม ส่วนการรับล็อตใหม่และวัตถุดิบให้เจ้าของร้านจัดการ')),
              for (final p in rows)
                ListTile(
                    title: Text('${p['name']}'),
                    subtitle: Text(
                        'คงเหลือ ${p['stock']} ${p['unit']}${p.containsKey('unitCost') ? ' · ต้นทุน ฿${p['unitCost']}' : ''}'),
                    trailing: StaffAccessService.can('stock') &&
                            p['stockMode'] != 'recipe'
                        ? IconButton(
                            tooltip: 'ตรวจนับ',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed: () => _count(p))
                        : null),
            ]);
          }));
}
