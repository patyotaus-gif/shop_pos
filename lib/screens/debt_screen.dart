import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/debt.dart';
import '../services/debt_service.dart';

class DebtScreen extends StatelessWidget {
  const DebtScreen({super.key});

  static final _baht = NumberFormat('#,##0.00', 'th_TH');
  static final _date = DateFormat('dd/MM/yyyy', 'th_TH');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ลูกหนี้'), centerTitle: true),
      body: StreamBuilder<List<Debt>>(
        stream: DebtService.watchUnpaid(),
        builder: (ctx, snap) {
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
  static final _date = DateFormat('dd/MM/yyyy', 'th_TH');

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
        subtitle: Text('เปิดบิล ${_date.format(debt.createdAt)}'),
        trailing: Column(
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
        onTap: () => _showPayDialog(context),
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
