import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/customer.dart';
import '../services/customer_service.dart';

/// Loyalty customers list — points balance + lifetime spend per customer.
/// Reached from Settings (Full/Restaurant). Customers are usually created
/// at checkout when a phone is attached; this screen is for viewing and
/// manual add/search.
class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  static final _baht = NumberFormat('#,##0', 'th_TH');
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('ลูกค้าสะสมแต้ม'), centerTitle: true),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'ค้นหาชื่อ / เบอร์โทร',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: StreamBuilder<List<Customer>>(
              stream: CustomerService.watchAll(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                var customers = snap.data ?? const <Customer>[];
                if (_query.isNotEmpty) {
                  customers = customers
                      .where((c) =>
                          c.name.toLowerCase().contains(_query) ||
                          c.phone.contains(_query))
                      .toList();
                }
                if (customers.isEmpty) {
                  return Center(
                    child: Text(
                      _query.isEmpty
                          ? 'ยังไม่มีลูกค้า — เพิ่มได้ตอนขาย หรือกดปุ่ม +'
                          : 'ไม่พบลูกค้า',
                      style: TextStyle(
                          color: cs.onSurface.withValues(alpha: 0.5)),
                    ),
                  );
                }
                return ListView.separated(
                  itemCount: customers.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final c = customers[i];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: cs.primary.withValues(alpha: 0.12),
                        child: Text(
                          c.name.isNotEmpty ? c.name.characters.first : '?',
                          style: TextStyle(
                              color: cs.primary,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                      title: Text(c.name,
                          style:
                              const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                          '${c.phone} · ใช้จ่ายรวม ฿${_baht.format(c.totalSpent)}'),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('${c.points}',
                              style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: cs.primary)),
                          Text('แต้ม',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: cs.onSurface
                                      .withValues(alpha: 0.5))),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addCustomer,
        icon: const Icon(Icons.person_add_alt),
        label: const Text('เพิ่มลูกค้า'),
      ),
    );
  }

  Future<void> _addCustomer() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('เพิ่มลูกค้า'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'เบอร์โทร',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'ชื่อ (ไม่บังคับ)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('ยกเลิก')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('เพิ่ม')),
        ],
      ),
    );
    if (ok == true && phoneCtrl.text.trim().isNotEmpty) {
      await CustomerService.ensure(
          phone: phoneCtrl.text, name: nameCtrl.text);
    }
  }
}
