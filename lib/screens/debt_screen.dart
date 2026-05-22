import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/debt.dart';
import '../models/sale.dart';
import '../services/debt_service.dart';
import '../services/sale_service.dart';

class DebtScreen extends StatelessWidget {
  const DebtScreen({super.key});

  static final _baht = NumberFormat('#,##0.00', 'th_TH');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ลูกหนี้'), centerTitle: true),
      body: StreamBuilder<List<Debt>>(
        stream: DebtService.watchUnpaid(),
        builder: (ctx, snap) {
          if (snap.hasError) return const Center(child: Text('โหลดข้อมูลไม่สำเร็จ'));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final debts = snap.data!;
          final totalDebt = debts.fold<double>(0, (s, e) => s + e.remaining);

          if (debts.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_outline, size: 64, color: Colors.green),
                  SizedBox(height: 8),
                  Text('ไม่มีลูกหนี้คงค้าง'),
                ],
              ),
            );
          }

          return Column(
            children: [
              Container(
                width: double.infinity,
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('ยอดหนี้รวม',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text('฿${_baht.format(totalDebt)}',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Colors.orange)),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  itemCount: debts.length,
                  itemBuilder: (ctx, i) => _DebtTile(debt: debts[i]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _DebtTile extends StatelessWidget {
  final Debt debt;
  const _DebtTile({required this.debt});

  static final _baht = NumberFormat('#,##0.00', 'th_TH');
  static final _dateShort = DateFormat('dd/MM/yyyy', 'th_TH');
  static final _dateTime = DateFormat('dd/MM/yyyy HH:mm', 'th_TH');

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: const CircleAvatar(
          backgroundColor: Colors.orange,
          child: Icon(Icons.person, color: Colors.white),
        ),
        title: Text(debt.customerName,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text('เปิดบิล ${_dateShort.format(debt.createdAt)}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('฿${_baht.format(debt.remaining)}',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                        fontSize: 16)),
                if (debt.paidAmount > 0)
                  Text('ชำระแล้ว ฿${_baht.format(debt.paidAmount)}',
                      style: const TextStyle(fontSize: 11, color: Colors.green)),
              ],
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.history, color: Colors.grey),
              tooltip: 'ประวัติการซื้อ',
              onPressed: () => _showHistory(context),
            ),
          ],
        ),
        onTap: () => _showPayDialog(context),
      ),
    );
  }

  void _showHistory(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (_, controller) => Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.history, color: Colors.orange),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'ประวัติ: ${debt.customerName}',
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: StreamBuilder<List<Sale>>(
                stream: SaleService.watchByCustomer(debt.customerName),
                builder: (ctx, snap) {
                  if (!snap.hasData)
                    return const Center(child: CircularProgressIndicator());
                  final sales = snap.data!;
                  if (sales.isEmpty)
                    return const Center(child: Text('ยังไม่มีประวัติ'));
                  final totalSpent = sales
                      .where((s) => !s.isRefunded)
                      .fold<double>(0, (a, s) => a + s.total);
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('${sales.length} บิล',
                                style: const TextStyle(color: Colors.grey)),
                            Text('ยอดรวม ฿${_baht.format(totalSpent)}',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.orange)),
                          ],
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          controller: controller,
                          itemCount: sales.length,
                          itemBuilder: (ctx, i) {
                            final s = sales[i];
                            return ListTile(
                              leading: CircleAvatar(
                                radius: 18,
                                backgroundColor: s.isRefunded
                                    ? Colors.red.shade100
                                    : Colors.green.shade100,
                                child: Icon(
                                  s.isRefunded ? Icons.undo : Icons.check,
                                  size: 16,
                                  color: s.isRefunded
                                      ? Colors.red
                                      : Colors.green,
                                ),
                              ),
                              title: Text(
                                s.items
                                    .map((e) =>
                                        '${e.productName}×${e.quantity}')
                                    .join(', '),
                                style: const TextStyle(fontSize: 13),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle:
                                  Text(_dateTime.format(s.createdAt)),
                              trailing: Text(
                                '฿${_baht.format(s.total)}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  decoration: s.isRefunded
                                      ? TextDecoration.lineThrough
                                      : null,
                                  color: s.isRefunded
                                      ? Colors.grey
                                      : null,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPayDialog(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('รับชำระ: ${debt.customerName}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ยอดคงค้าง: ฿${_baht.format(debt.remaining)}',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'จำนวนที่รับ',
                prefixText: '฿',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('ยกเลิก')),
          FilledButton(
            onPressed: () async {
              final amount = double.tryParse(ctrl.text) ?? 0;
              if (amount <= 0) return;
              await DebtService.recordPayment(debt.id, amount);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('บันทึก'),
          ),
        ],
      ),
    );
  }
}
