import '../widgets/content_width.dart';
import 'package:flutter/material.dart';
import 'staff_inventory_screen.dart';
import 'package:intl/intl.dart';
import '../models/sale.dart';
import '../services/staff_access_service.dart';
import '../utils/operation_error.dart';

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
      appBar: AppBar(title: const Text('เพิ่มเติม')),
      body: ContentWidth(
          maxWidth: 1040,
          child: FutureBuilder<Map<String, dynamic>>(
              future: _workspace,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(
                      child: TextButton(
                          onPressed: () => setState(() =>
                              _workspace = StaffAccessService.workspace()),
                          child: Text(operationError(snap.error!))));
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final p = snap.data!['permissions'] as Map? ?? {};
                if (![
                  'cashSession',
                  'reports',
                  'cost',
                  'stock',
                  'stockReceive',
                  'stockWaste',
                  'stockHistory'
                ].any((key) => p[key] == true)) {
                  return const Center(child: Text('ไม่มีเมนูเพิ่มเติม'));
                }
                return ListView(children: [
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
                  if ([
                    'cost',
                    'stock',
                    'stockReceive',
                    'stockWaste',
                    'stockHistory'
                  ].any((key) => p[key] == true))
                    ListTile(
                        leading: const Icon(Icons.inventory_2_outlined),
                        title: const Text('สต๊อกสินค้า'),
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute<void>(
                                builder: (_) => const StaffInventoryScreen()))),
                ]);
              })));
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
      body: ContentWidth(
          maxWidth: 1040,
          child: Column(children: [
            ListTile(
                title: Text(
                    '${DateFormat('dd/MM/yyyy').format(_range.start)} – ${DateFormat('dd/MM/yyyy').format(_range.end)}'),
                subtitle:
                    const Text('เลือกช่วงไม่เกิน 31 วัน · เวลาตามเครื่องนี้'),
                trailing: const Icon(Icons.date_range),
                onTap: () async {
                  final selected = await showDateRangePicker(
                      context: context,
                      firstDate: DateTime(2020),
                      lastDate: DateTime.now(),
                      initialDateRange: _range);
                  if (selected != null && context.mounted) {
                    if (selected.duration.inDays > 30) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          content: Text('เลือกได้ไม่เกิน 31 วัน')));
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
                                onPressed: () =>
                                    setState(() => _data = _load()),
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
                          const ListTile(
                              title: Text('ไม่มีรายการขายในช่วงนี้')),
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
                                          saleId: sale.id,
                                          allowRefund: true)))),
                      ]);
                    }))
          ])));
}
