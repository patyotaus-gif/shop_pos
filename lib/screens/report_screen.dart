import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/sale.dart';
import '../services/sale_service.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});

  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen> with SingleTickerProviderStateMixin {
  late TabController _tab;
  final _baht = NumberFormat('#,##0.00', 'th_TH');
  final _dateFormat = DateFormat('dd/MM/yyyy HH:mm', 'th_TH');

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  DateTimeRange _rangeFor(String period) {
    final now = DateTime.now();
    return switch (period) {
      'week' => DateTimeRange(
          start: now.subtract(const Duration(days: 7)),
          end: now,
        ),
      'month' => DateTimeRange(
          start: DateTime(now.year, now.month, 1),
          end: now,
        ),
      _ => DateTimeRange(
          start: DateTime(now.year, now.month, now.day),
          end: now,
        ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('รายงาน'),
        centerTitle: true,
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(text: 'วันนี้'),
            Tab(text: '7 วัน'),
            Tab(text: 'เดือนนี้'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: [
          _SalesReport(range: _rangeFor('today'), baht: _baht, dateFormat: _dateFormat),
          _SalesReport(range: _rangeFor('week'), baht: _baht, dateFormat: _dateFormat),
          _SalesReport(range: _rangeFor('month'), baht: _baht, dateFormat: _dateFormat),
        ],
      ),
    );
  }
}

class _SalesReport extends StatelessWidget {
  final DateTimeRange range;
  final NumberFormat baht;
  final DateFormat dateFormat;

  const _SalesReport({
    required this.range,
    required this.baht,
    required this.dateFormat,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return StreamBuilder<List<Sale>>(
      stream: SaleService.watchByRange(range.start, range.end),
      builder: (ctx, snap) {
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final sales = snap.data!;
        final total = sales.fold<double>(0, (s, e) => s + e.total);
        final count = sales.length;
        final debtTotal = sales
            .where((s) => s.isDebt)
            .fold<double>(0, (s, e) => s + e.total);

        return Column(
          children: [
            // Summary cards
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  _SummaryCard(
                    label: 'รายได้รวม',
                    value: '฿${baht.format(total)}',
                    icon: Icons.attach_money,
                    color: Colors.green,
                  ),
                  const SizedBox(width: 8),
                  _SummaryCard(
                    label: 'จำนวนบิล',
                    value: '$count บิล',
                    icon: Icons.receipt_long,
                    color: cs.primary,
                  ),
                  const SizedBox(width: 8),
                  _SummaryCard(
                    label: 'ยอดเชื่อ',
                    value: '฿${baht.format(debtTotal)}',
                    icon: Icons.person_outline,
                    color: Colors.orange,
                  ),
                ],
              ),
            ),
            const Divider(),
            // Sale list
            Expanded(
              child: sales.isEmpty
                  ? const Center(child: Text('ยังไม่มีรายการขาย'))
                  : ListView.builder(
                      itemCount: sales.length,
                      itemBuilder: (ctx, i) {
                        final s = sales[i];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor:
                                s.isDebt ? Colors.orange.shade100 : Colors.green.shade100,
                            child: Icon(
                              s.isDebt ? Icons.person_outline : Icons.check,
                              color: s.isDebt ? Colors.orange : Colors.green,
                            ),
                          ),
                          title: Text(
                            s.isDebt ? 'เชื่อ: ${s.customerName}' : 'ชำระเงินสด',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                          subtitle: Text(
                            '${s.items.length} รายการ · ${dateFormat.format(s.createdAt)}',
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('฿${baht.format(s.total)}',
                                  style: const TextStyle(fontWeight: FontWeight.bold)),
                              if (s.discount > 0)
                                Text('ลด ฿${baht.format(s.discount)}',
                                    style: const TextStyle(
                                        fontSize: 11, color: Colors.green)),
                            ],
                          ),
                          onTap: () => _showSaleDetail(ctx, s),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  void _showSaleDetail(BuildContext context, Sale sale) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('รายละเอียดบิล',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ...sale.items.map((item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${item.productName} × ${item.quantity}'),
                      Text('฿${baht.format(item.subtotal)}'),
                    ],
                  ),
                )),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('รวม', style: TextStyle(fontWeight: FontWeight.bold)),
                Text('฿${baht.format(sale.total)}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  Navigator.pop(ctx);
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (c) => AlertDialog(
                      title: const Text('ยกเลิกบิล'),
                      content: const Text('ต้องการยกเลิกบิลนี้และคืนสต็อกใช่ไหม?'),
                      actions: [
                        TextButton(
                            onPressed: () => Navigator.pop(c, false),
                            child: const Text('ยกเลิก')),
                        FilledButton(
                          onPressed: () => Navigator.pop(c, true),
                          style: FilledButton.styleFrom(backgroundColor: Colors.red),
                          child: const Text('ยืนยัน'),
                        ),
                      ],
                    ),
                  );
                  if (confirm == true) await SaleService.voidSale(sale);
                },
                icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                label: const Text('ยกเลิกบิล', style: TextStyle(color: Colors.red)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13),
                textAlign: TextAlign.center),
            Text(label,
                style: const TextStyle(fontSize: 10, color: Colors.grey),
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
