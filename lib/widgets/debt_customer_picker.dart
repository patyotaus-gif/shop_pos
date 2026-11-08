import 'package:flutter/material.dart';

import '../models/customer.dart';
import '../models/debt.dart';

/// Who a ค้างชำระ bill belongs to. [customerId] links the debt to the shared
/// customer list so the same person is picked, not retyped, next time.
class DebtCustomerChoice {
  const DebtCustomerChoice({required this.name, required this.customerId});
  final String name;
  final String customerId;
}

/// Pick an existing customer, a name from older debts, or add a new one.
/// Older free-text debt names become customer records when picked.
class DebtCustomerPicker extends StatefulWidget {
  const DebtCustomerPicker({
    super.key,
    required this.customers,
    required this.debts,
    required this.create,
  });

  final Stream<List<Customer>> customers;
  final Stream<List<Debt>> debts;
  final Future<Customer> Function(String name, String phone) create;

  static Future<DebtCustomerChoice?> show(
    BuildContext context, {
    required Stream<List<Customer>> customers,
    required Stream<List<Debt>> debts,
    required Future<Customer> Function(String name, String phone) create,
  }) =>
      showDialog<DebtCustomerChoice>(
          context: context,
          builder: (_) => DebtCustomerPicker(
              customers: customers, debts: debts, create: create));

  @override
  State<DebtCustomerPicker> createState() => _DebtCustomerPickerState();
}

class _DebtCustomerPickerState extends State<DebtCustomerPicker> {
  final _search = TextEditingController();
  final _phone = TextEditingController();
  late final Stream<List<Customer>> _customers = widget.customers;
  late final Stream<List<Debt>> _debts = widget.debts;
  bool _adding = false;
  bool _saving = false;
  Object? _error;

  @override
  void dispose() {
    _search.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _choose(String name, {String phone = '', String? id}) async {
    if (_saving) return;
    if (id != null) {
      Navigator.pop(context, DebtCustomerChoice(name: name, customerId: id));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final customer = await widget.create(name.trim(), phone.trim());
      if (mounted) {
        Navigator.pop(context,
            DebtCustomerChoice(name: customer.name, customerId: customer.id));
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final query = _search.text.trim().toLowerCase();
    return AlertDialog(
      title: const Text('ลูกค้าค้างชำระ'),
      content: SizedBox(
        width: 420,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            key: const ValueKey('debt-customer-search'),
            controller: _search,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: _adding ? 'ชื่อลูกค้าใหม่' : 'ค้นหาชื่อหรือเบอร์โทร',
              prefixIcon: Icon(_adding ? Icons.person_add_alt : Icons.search),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          if (_adding) ...[
            TextField(
              key: const ValueKey('debt-customer-phone'),
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'เบอร์โทร (ไม่บังคับ)',
                helperText: 'ใส่เบอร์เพื่อให้ลูกค้าสะสมแต้มได้ด้วย',
                border: OutlineInputBorder(),
              ),
            ),
          ] else
            Flexible(
              child: StreamBuilder<List<Customer>>(
                stream: _customers,
                builder: (context, customerSnap) =>
                    StreamBuilder<List<Debt>>(
                  stream: _debts,
                  builder: (context, debtSnap) {
                    if (customerSnap.hasError) {
                      return const Padding(
                          padding: EdgeInsets.all(8),
                          child: Text(
                              'โหลดรายชื่อลูกค้าไม่สำเร็จ เพิ่มชื่อใหม่ได้ด้านล่าง'));
                    }
                    final customers = customerSnap.data ?? const <Customer>[];
                    final known =
                        customers.map((c) => c.name.trim()).toSet();
                    final legacy = <String>{
                      for (final d in debtSnap.data ?? const <Debt>[])
                        if (d.customerId == null &&
                            d.customerName.trim().isNotEmpty &&
                            !known.contains(d.customerName.trim()))
                          d.customerName.trim()
                    }.toList()
                      ..sort();
                    bool matches(String text) =>
                        query.isEmpty || text.toLowerCase().contains(query);
                    final rows = <Widget>[
                      for (final c in customers)
                        if (matches(c.name) || matches(c.phone))
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.person_outline),
                            title: Text(c.name),
                            subtitle: c.phone.isEmpty ? null : Text(c.phone),
                            onTap: () => _choose(c.name, id: c.id),
                          ),
                      for (final name in legacy)
                        if (matches(name))
                          ListTile(
                            dense: true,
                            leading: const Icon(Icons.history),
                            title: Text(name),
                            subtitle: const Text('เคยค้างชำระ'),
                            onTap: () => _choose(name),
                          ),
                    ];
                    if (rows.isEmpty) {
                      return Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(query.isEmpty
                            ? 'ยังไม่มีรายชื่อลูกค้า'
                            : 'ไม่พบ "${_search.text.trim()}"'),
                      );
                    }
                    return ListView(shrinkWrap: true, children: rows);
                  },
                ),
              ),
            ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('บันทึกลูกค้าไม่สำเร็จ: $_error',
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('ยกเลิก')),
        if (_adding)
          FilledButton(
            key: const ValueKey('debt-customer-save'),
            onPressed: _saving || _search.text.trim().isEmpty
                ? null
                : () => _choose(_search.text, phone: _phone.text),
            child: const Text('บันทึกและใช้ชื่อนี้'),
          )
        else
          FilledButton.tonalIcon(
            key: const ValueKey('debt-customer-add'),
            onPressed: _saving ? null : () => setState(() => _adding = true),
            icon: const Icon(Icons.person_add_alt),
            label: const Text('เพิ่มลูกค้าใหม่'),
          ),
      ],
    );
  }
}
