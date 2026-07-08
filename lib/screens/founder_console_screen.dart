import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/hardware_request.dart';
import '../models/supplier.dart';
import '../services/admin_service.dart';

/// Founder-only operations console — manage subscriptions, advance hardware
/// shipments, and onboard/edit marketplace suppliers. Every mutation goes
/// through founder-gated Cloud Functions (AdminService); the screen itself
/// is only reachable from a founder-gated Settings entry.
class FounderConsoleScreen extends StatelessWidget {
  const FounderConsoleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('ผู้ดูแลระบบ'),
          centerTitle: true,
          actions: [
            Builder(
              builder: (context) => IconButton(
                tooltip: 'จัดการผู้ดูแล',
                icon: const Icon(Icons.admin_panel_settings_outlined),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const _GrantFounderDialog(),
                ),
              ),
            ),
          ],
          bottom: const TabBar(
            tabs: [
              Tab(text: 'ร้านค้า'),
              Tab(text: 'ซัพพลายเออร์'),
              Tab(text: 'แผน & บิล'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [_ShopsTab(), _SuppliersTab(), _BillingTab()],
        ),
      ),
    );
  }
}

final _dateFmt = DateFormat('d MMM yy', 'th_TH');
final _baht = NumberFormat('#,##0', 'th_TH');

String _tierLabel(String t) => switch (t) {
      'solo' => 'Solo',
      'lite' => 'Lite',
      'full' => 'Full',
      'restaurant' => 'Restaurant',
      _ => t,
    };

String _date(Object? iso) {
  if (iso is! String) return '-';
  final dt = DateTime.tryParse(iso)?.toLocal();
  return dt == null ? '-' : _dateFmt.format(dt);
}

// ────────────────────────────── Shops tab ──────────────────────────────

class _ShopsTab extends StatefulWidget {
  const _ShopsTab();
  @override
  State<_ShopsTab> createState() => _ShopsTabState();
}

class _ShopsTabState extends State<_ShopsTab> {
  late Future<List<Map<String, dynamic>>> _future;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _future = AdminService.listShops();
  }

  void _reload() => setState(() => _future = AdminService.listShops());

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'ค้นหาร้าน / อีเมล',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) =>
                setState(() => _query = v.trim().toLowerCase()),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return _ErrorView(
                    message: snap.error.toString(), onRetry: _reload);
              }
              var shops = snap.data ?? const [];
              if (_query.isNotEmpty) {
                shops = shops
                    .where((s) =>
                        (s['name'] ?? '')
                            .toString()
                            .toLowerCase()
                            .contains(_query) ||
                        (s['email'] ?? '')
                            .toString()
                            .toLowerCase()
                            .contains(_query))
                    .toList();
              }
              if (shops.isEmpty) {
                return const Center(child: Text('ไม่พบร้าน'));
              }
              return RefreshIndicator(
                onRefresh: () async => _reload(),
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: shops.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) => _ShopTile(
                    shop: shops[i],
                    onChanged: _reload,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ShopTile extends StatelessWidget {
  const _ShopTile({required this.shop, required this.onChanged});

  final Map<String, dynamic> shop;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final status = (shop['subscriptionStatus'] ?? 'trial').toString();
    final tier = (shop['tier'] ?? 'full').toString();
    final hw = (shop['hardware'] as List?) ?? const [];
    return ListTile(
      title: Text(
        shop['name']?.toString().isNotEmpty == true
            ? shop['name'].toString()
            : '(ไม่มีชื่อร้าน)',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(shop['email']?.toString() ?? '',
              maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 4, children: [
            _Chip(_tierLabel(tier)),
            _StatusChip(status),
            if (status == 'trial')
              _Chip('ทดลองถึง ${_date(shop['trialEndsAt'])}')
            else if (status == 'active')
              _Chip('ถึง ${_date(shop['subscriptionEndsAt'])}'),
            if (hw.isNotEmpty)
              _Chip('HW: ${_hwLabel(hw.first['status'])}'),
          ]),
        ],
      ),
      isThreeLine: true,
      trailing: const Icon(Icons.chevron_right),
      onTap: () async {
        await showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (_) => _ShopActionsSheet(shop: shop),
        );
        onChanged();
      },
    );
  }
}

String _hwLabel(Object? status) {
  final s = HardwareStatus.values.firstWhere(
    (e) => e.name == status,
    orElse: () => HardwareStatus.requested,
  );
  return s.label;
}

class _ShopActionsSheet extends StatefulWidget {
  const _ShopActionsSheet({required this.shop});
  final Map<String, dynamic> shop;

  @override
  State<_ShopActionsSheet> createState() => _ShopActionsSheetState();
}

class _ShopActionsSheetState extends State<_ShopActionsSheet> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(done)));
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('ผิดพลาด: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final shop = widget.shop;
    final shopId = shop['id'].toString();
    final hw = (shop['hardware'] as List?) ?? const [];

    return Padding(
      padding: EdgeInsets.fromLTRB(
          20, 0, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              shop['name']?.toString().isNotEmpty == true
                  ? shop['name'].toString()
                  : '(ไม่มีชื่อร้าน)',
              style: const TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w700),
            ),
            Text(shop['email']?.toString() ?? '',
                style: TextStyle(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6))),
            const SizedBox(height: 16),
            if (_busy) const LinearProgressIndicator(),
            const _SheetLabel('การสมัครสมาชิก'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final d in const [7, 30, 60])
                ActionChip(
                  label: Text('+$d วันทดลอง'),
                  onPressed: _busy
                      ? null
                      : () => _run(
                          () => AdminService.extendTrial(shopId, d),
                          'ต่อทดลอง +$d วันแล้ว'),
                ),
              ActionChip(
                avatar: const Icon(Icons.check_circle_outline, size: 18),
                label: const Text('เปิดใช้แบบจ่ายเงิน'),
                onPressed: _busy ? null : _openActivate,
              ),
              ActionChip(
                avatar: const Icon(Icons.block, size: 18),
                label: const Text('หมดอายุทันที'),
                onPressed: _busy
                    ? null
                    : () => _run(() => AdminService.expire(shopId),
                        'ตั้งเป็นหมดอายุแล้ว'),
              ),
            ]),
            if (hw.isNotEmpty) ...[
              const SizedBox(height: 20),
              const _SheetLabel('ฮาร์ดแวร์'),
              for (final h in hw) _hardwareBlock(shopId, h),
            ],
          ],
        ),
      ),
    );
  }

  Widget _hardwareBlock(String shopId, dynamic h) {
    final reqId = h['id'].toString();
    final current = h['status'].toString();
    final kit = HardwareKit.values.firstWhere(
      (e) => e.name == h['kit'],
      orElse: () => HardwareKit.none,
    );
    const order = ['requested', 'preparing', 'shipped', 'delivered'];
    final idx = order.indexOf(current);
    final next = idx >= 0 && idx < order.length - 1 ? order[idx + 1] : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Text(kit.label, style: const TextStyle(fontSize: 13)),
        const SizedBox(height: 2),
        Text('สถานะ: ${_hwLabel(current)}',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          if (next != null)
            FilledButton.tonal(
              onPressed: _busy
                  ? null
                  : () => _run(
                      () => AdminService.setHardwareStatus(shopId, reqId,
                          status: next),
                      'อัพเดตเป็น ${_hwLabel(next)}'),
              child: Text('→ ${_hwLabel(next)}'),
            ),
          if (current != 'returned' && current != 'requested')
            OutlinedButton(
              onPressed: _busy
                  ? null
                  : () => _run(
                      () => AdminService.setHardwareStatus(shopId, reqId,
                          status: 'returned'),
                      'ตั้งเป็นคืนเครื่องแล้ว'),
              child: const Text('คืนเครื่อง'),
            ),
        ]),
      ],
    );
  }

  Future<void> _openActivate() async {
    final result = await showDialog<({String tier, String cycle})>(
      context: context,
      builder: (_) => const _ActivateDialog(),
    );
    if (result == null) return;
    final days = result.cycle == 'yearly' ? 365 : 30;
    await _run(
      () => AdminService.activate(
        widget.shop['id'].toString(),
        days: days,
        tier: result.tier,
        billingCycle: result.cycle,
      ),
      'เปิดใช้ ${_tierLabel(result.tier)} ($days วัน) แล้ว',
    );
  }
}

class _ActivateDialog extends StatefulWidget {
  const _ActivateDialog();
  @override
  State<_ActivateDialog> createState() => _ActivateDialogState();
}

class _ActivateDialogState extends State<_ActivateDialog> {
  String _tier = 'full';
  String _cycle = 'monthly';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('เปิดใช้แบบจ่ายเงิน'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: _tier,
            decoration: const InputDecoration(labelText: 'แพ็กเกจ'),
            items: const [
              DropdownMenuItem(value: 'solo', child: Text('Solo')),
              DropdownMenuItem(value: 'lite', child: Text('Lite')),
              DropdownMenuItem(value: 'full', child: Text('Full')),
              DropdownMenuItem(
                  value: 'restaurant', child: Text('Restaurant')),
            ],
            onChanged: (v) => setState(() => _tier = v ?? 'full'),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _cycle,
            decoration: const InputDecoration(labelText: 'รอบบิล'),
            items: const [
              DropdownMenuItem(value: 'monthly', child: Text('รายเดือน (30 วัน)')),
              DropdownMenuItem(value: 'yearly', child: Text('รายปี (365 วัน)')),
            ],
            onChanged: (v) => setState(() => _cycle = v ?? 'monthly'),
          ),
        ],
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ยกเลิก')),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, (tier: _tier, cycle: _cycle)),
          child: const Text('เปิดใช้'),
        ),
      ],
    );
  }
}

// ──────────────────────────── Suppliers tab ────────────────────────────

class _SuppliersTab extends StatelessWidget {
  const _SuppliersTab();

  @override
  Widget build(BuildContext context) {
    final col = FirebaseFirestore.instance
        .collection('suppliers')
        .orderBy('name');
    return Scaffold(
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: col.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data?.docs ?? const [];
          if (docs.isEmpty) {
            return const Center(
                child: Text('ยังไม่มีซัพพลายเออร์ — กดปุ่ม +'));
          }
          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final s = Supplier.fromFirestore(docs[i].data(), docs[i].id);
              return ListTile(
                leading: CircleAvatar(
                  backgroundColor: s.active
                      ? Theme.of(context).colorScheme.primary
                          .withValues(alpha: 0.12)
                      : Colors.grey.withValues(alpha: 0.2),
                  child: Icon(Icons.storefront,
                      color: s.active
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey),
                ),
                title: Text(s.name,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                    '${s.category}${s.active ? '' : ' · ปิดอยู่'} · ขั้นต่ำ ฿${_baht.format(s.minOrder)}'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(
                  builder: (_) => _SupplierDetailScreen(supplier: s),
                )),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editSupplier(context, null),
        icon: const Icon(Icons.add_business),
        label: const Text('เพิ่มซัพพลายเออร์'),
      ),
    );
  }
}

Future<void> _editSupplier(BuildContext context, Supplier? existing) async {
  await showDialog<void>(
    context: context,
    builder: (_) => _SupplierEditDialog(existing: existing),
  );
}

class _SupplierEditDialog extends StatefulWidget {
  const _SupplierEditDialog({this.existing});
  final Supplier? existing;

  @override
  State<_SupplierEditDialog> createState() => _SupplierEditDialogState();
}

class _SupplierEditDialogState extends State<_SupplierEditDialog> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _category =
      TextEditingController(text: widget.existing?.category ?? '');
  late final _area = TextEditingController(text: widget.existing?.area ?? '');
  late final _delivery =
      TextEditingController(text: widget.existing?.deliveryDays ?? '');
  late final _minOrder = TextEditingController(
      text: widget.existing != null
          ? widget.existing!.minOrder.toStringAsFixed(0)
          : '');
  final _email = TextEditingController();
  final _password = TextEditingController();
  late bool _active = widget.existing?.active ?? true;
  bool _busy = false;

  bool get _isNew => widget.existing == null;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isNew ? 'เพิ่มซัพพลายเออร์' : 'แก้ไขซัพพลายเออร์'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _field(_name, 'ชื่อร้านส่ง'),
          _field(_category, 'หมวด (เช่น ผัก · ผลไม้)'),
          _field(_area, 'พื้นที่จัดส่ง (ไม่บังคับ)'),
          _field(_delivery, 'วันที่ส่ง (เช่น จ-ส)'),
          _field(_minOrder, 'ยอดสั่งขั้นต่ำ (บาท)',
              keyboard: TextInputType.number),
          if (_isNew) ...[
            const SizedBox(height: 4),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('บัญชีเข้าพอร์ทัล (supplier ใช้ล็อกอิน)',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
            ),
            const SizedBox(height: 8),
            _field(_email, 'อีเมล', keyboard: TextInputType.emailAddress),
            _field(_password, 'รหัสผ่าน (อย่างน้อย 6 ตัว)'),
          ] else
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('เปิดใช้งาน'),
              value: _active,
              onChanged: (v) => setState(() => _active = v),
            ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('ยกเลิก')),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('บันทึก'),
        ),
      ],
    );
  }

  Widget _field(TextEditingController c, String label,
          {TextInputType? keyboard}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: c,
          keyboardType: keyboard,
          decoration: InputDecoration(
              labelText: label, border: const OutlineInputBorder()),
        ),
      );

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    if (_isNew &&
        (_email.text.trim().isEmpty || _password.text.trim().length < 6)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('กรอกอีเมล + รหัสผ่าน (อย่างน้อย 6 ตัว)')));
      return;
    }
    setState(() => _busy = true);
    try {
      if (_isNew) {
        // New suppliers get a portal login account (id == auth uid).
        await AdminService.createSupplierAccount(
          email: _email.text.trim(),
          password: _password.text.trim(),
          name: _name.text.trim(),
          category: _category.text.trim(),
          area: _area.text.trim(),
          deliveryDays: _delivery.text.trim(),
          minOrder: double.tryParse(_minOrder.text.trim()) ?? 0,
        );
      } else {
        await AdminService.upsertSupplier(
          supplierId: widget.existing!.id,
          name: _name.text.trim(),
          category: _category.text.trim(),
          area: _area.text.trim(),
          deliveryDays: _delivery.text.trim(),
          minOrder: double.tryParse(_minOrder.text.trim()) ?? 0,
          active: _active,
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('ผิดพลาด: $e')));
      }
    }
  }
}

class _SupplierDetailScreen extends StatelessWidget {
  const _SupplierDetailScreen({required this.supplier});
  final Supplier supplier;

  @override
  Widget build(BuildContext context) {
    final products = FirebaseFirestore.instance
        .collection('suppliers')
        .doc(supplier.id)
        .collection('products')
        .orderBy('name');
    return Scaffold(
      appBar: AppBar(
        title: Text(supplier.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _editSupplier(context, supplier),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: products.snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = snap.data?.docs ?? const [];
          if (docs.isEmpty) {
            return const Center(child: Text('ยังไม่มีสินค้า — กดปุ่ม +'));
          }
          return ListView.separated(
            itemCount: docs.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final p =
                  SupplierProduct.fromFirestore(docs[i].data(), docs[i].id);
              return ListTile(
                title: Text(p.name),
                subtitle: Text(
                    '฿${_baht.format(p.price)}/${p.unit} · ขั้นต่ำ ${p.moq}${p.available ? '' : ' · หมด'}'),
                trailing: const Icon(Icons.edit, size: 18),
                onTap: () => _editProduct(context, p),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editProduct(context, null),
        icon: const Icon(Icons.add),
        label: const Text('เพิ่มสินค้า'),
      ),
    );
  }

  Future<void> _editProduct(
      BuildContext context, SupplierProduct? existing) async {
    await showDialog<void>(
      context: context,
      builder: (_) =>
          _ProductEditDialog(supplierId: supplier.id, existing: existing),
    );
  }
}

class _ProductEditDialog extends StatefulWidget {
  const _ProductEditDialog({required this.supplierId, this.existing});
  final String supplierId;
  final SupplierProduct? existing;

  @override
  State<_ProductEditDialog> createState() => _ProductEditDialogState();
}

class _ProductEditDialogState extends State<_ProductEditDialog> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _unit =
      TextEditingController(text: widget.existing?.unit ?? 'ชิ้น');
  late final _price = TextEditingController(
      text: widget.existing != null
          ? widget.existing!.price.toStringAsFixed(0)
          : '');
  late final _moq = TextEditingController(
      text: widget.existing != null ? '${widget.existing!.moq}' : '1');
  late bool _available = widget.existing?.available ?? true;
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'เพิ่มสินค้า' : 'แก้ไขสินค้า'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _field(_name, 'ชื่อสินค้า'),
          _field(_unit, 'หน่วย (เช่น กก., ลัง)'),
          _field(_price, 'ราคา (บาท)', keyboard: TextInputType.number),
          _field(_moq, 'สั่งขั้นต่ำ', keyboard: TextInputType.number),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('มีของ'),
            value: _available,
            onChanged: (v) => setState(() => _available = v),
          ),
        ]),
      ),
      actions: [
        TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context),
            child: const Text('ยกเลิก')),
        FilledButton(
          onPressed: _busy ? null : _save,
          child: _busy
              ? const SizedBox(
                  width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('บันทึก'),
        ),
      ],
    );
  }

  Widget _field(TextEditingController c, String label,
          {TextInputType? keyboard}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: TextField(
          controller: c,
          keyboardType: keyboard,
          decoration: InputDecoration(
              labelText: label, border: const OutlineInputBorder()),
        ),
      );

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await AdminService.upsertSupplierProduct(
        supplierId: widget.supplierId,
        productId: widget.existing?.id,
        name: _name.text.trim(),
        unit: _unit.text.trim().isEmpty ? 'ชิ้น' : _unit.text.trim(),
        price: double.tryParse(_price.text.trim()) ?? 0,
        moq: int.tryParse(_moq.text.trim()) ?? 1,
        available: _available,
      );
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('ผิดพลาด: $e')));
      }
    }
  }
}

// ────────────────────────────── shared bits ────────────────────────────

class _Chip extends StatelessWidget {
  const _Chip(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(text, style: const TextStyle(fontSize: 11)),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip(this.status);
  final String status;
  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'active' => ('จ่ายเงินแล้ว', Colors.green),
      'trial' => ('ทดลองใช้', Colors.orange),
      _ => ('หมดอายุ', Colors.red),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, color: color, fontWeight: FontWeight.w700)),
    );
  }
}

class _SheetLabel extends StatelessWidget {
  const _SheetLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700)),
      );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final denied = message.contains('permission-denied') ||
        message.contains('Founder only');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(denied ? Icons.lock_outline : Icons.error_outline,
                size: 48,
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            Text(denied
                ? 'หน้านี้สำหรับผู้ดูแลระบบเท่านั้น'
                : 'โหลดข้อมูลไม่สำเร็จ'),
            const SizedBox(height: 16),
            if (!denied)
              FilledButton.tonal(
                  onPressed: onRetry, child: const Text('ลองใหม่')),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── Manage founders ───────────────────────────

/// Grant or revoke the founder custom claim by email. The change takes effect
/// on that user's next token refresh / re-login.
class _GrantFounderDialog extends StatefulWidget {
  const _GrantFounderDialog();
  @override
  State<_GrantFounderDialog> createState() => _GrantFounderDialogState();
}

class _GrantFounderDialogState extends State<_GrantFounderDialog> {
  final _email = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _set(bool founder) async {
    final email = _email.text.trim();
    if (email.isEmpty) return;
    setState(() => _busy = true);
    try {
      await AdminService.setFounder(email, founder);
      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(founder
            ? 'ให้สิทธิ์ผู้ดูแลแก่ $email แล้ว (ผู้ใช้ต้องล็อกอินใหม่)'
            : 'ถอนสิทธิ์ผู้ดูแลของ $email แล้ว'),
      ));
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(_friendlyError(e))));
    }
  }

  String _friendlyError(Object e) {
    final m = e.toString();
    if (m.contains('No user')) return 'ไม่พบบัญชีที่ใช้อีเมลนี้';
    if (m.contains('bootstrap')) {
      return 'บัญชีนี้เป็นผู้ดูแลหลัก ถอนสิทธิ์ไม่ได้';
    }
    if (m.contains('Founder only') || m.contains('permission-denied')) {
      return 'เฉพาะผู้ดูแลเท่านั้น';
    }
    return 'เกิดข้อผิดพลาด ลองใหม่อีกครั้ง';
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('จัดการผู้ดูแลระบบ'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'ให้/ถอนสิทธิ์ผู้ดูแล (founder) ด้วยอีเมลบัญชีที่มีอยู่ '
            'การเปลี่ยนแปลงมีผลเมื่อผู้ใช้ล็อกอินใหม่',
            style: TextStyle(fontSize: 13),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _email,
            enabled: !_busy,
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            decoration: const InputDecoration(
              labelText: 'อีเมล',
              hintText: 'name@example.com',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('ปิด'),
        ),
        TextButton(
          onPressed: _busy ? null : () => _set(false),
          child: const Text('ถอนสิทธิ์'),
        ),
        FilledButton(
          onPressed: _busy ? null : () => _set(true),
          child: _busy
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('ให้สิทธิ์'),
        ),
      ],
    );
  }
}

// ─────────────────────────── Billing tab ───────────────────────────
// Plan catalog (config/plans) + company PromptPay account + recent
// subscription payments. Every write goes through founder-gated callables
// (adminUpsertPlans / adminSetBilling).

const _kTierOrder = ['solo', 'lite', 'full', 'restaurant'];

/// Mirrors functions/plans.js DEFAULT_TIERS — shown when config/plans
/// doesn't exist yet (first run before the founder saves anything).
const Map<String, Map<String, dynamic>> _kDefaultTiers = {
  'solo': {
    'name': 'Solo',
    'desc': 'ใช้มือถือ/แท็บเล็ตของตัวเอง POS + รายงาน + PromptPay',
    'enabled': true,
    'monthly': {'amount': 19900},
    'yearly': {'amount': 199000},
  },
  'lite': {
    'name': 'Lite',
    'desc': 'มีแท็บเล็ตแล้ว + ชุดพิมพ์ใบเสร็จ + จัดการสต็อก + ฐานลูกค้า',
    'enabled': true,
    'monthly': {'amount': 39900},
    'yearly': {'amount': 399000},
  },
  'full': {
    'name': 'Full',
    'desc': 'ครบชุดฮาร์ดแวร์ + 3 ผู้ใช้ + สะสมแต้ม + ซ่อมถึงที่',
    'enabled': true,
    'featured': true,
    'monthly': {'amount': 59900},
    'yearly': {'amount': 599000},
  },
  'restaurant': {
    'name': 'Restaurant',
    'desc': 'ร้านอาหารหลายสาขา + ครัว + ผังโต๊ะ + แยกบิล',
    'enabled': true,
    'perLocation': true,
    'monthly': {'amount': 119900},
    'yearly': {'amount': 1199000},
  },
};

class _BillingTab extends StatefulWidget {
  const _BillingTab();

  @override
  State<_BillingTab> createState() => _BillingTabState();
}

class _TierForm {
  _TierForm(Map<String, dynamic> t)
      : name = TextEditingController(text: (t['name'] ?? '') as String),
        desc = TextEditingController(text: (t['desc'] ?? '') as String),
        monthly = TextEditingController(
            text: '${(((t['monthly'] as Map?)?['amount'] ?? 0) as num) ~/ 100}'),
        yearly = TextEditingController(
            text: '${(((t['yearly'] as Map?)?['amount'] ?? 0) as num) ~/ 100}'),
        enabled = t['enabled'] != false,
        featured = t['featured'] == true;

  final TextEditingController name;
  final TextEditingController desc;
  final TextEditingController monthly; // บาท (แปลงเป็นสตางค์ตอนบันทึก)
  final TextEditingController yearly;
  bool enabled;
  bool featured;

  void dispose() {
    name.dispose();
    desc.dispose();
    monthly.dispose();
    yearly.dispose();
  }

  Map<String, dynamic> toTier() => {
        'name': name.text.trim(),
        'desc': desc.text.trim(),
        'enabled': enabled,
        'featured': featured,
        'monthly': {'amount': (int.tryParse(monthly.text.trim()) ?? 0) * 100},
        'yearly': {'amount': (int.tryParse(yearly.text.trim()) ?? 0) * 100},
      };
}

class _BillingTabState extends State<_BillingTab> {
  bool _loading = true;
  String? _error;

  final Map<String, _TierForm> _forms = {};
  final _ppId = TextEditingController();
  final _ppName = TextEditingController();
  final _lineId = TextEditingController();
  List<Map<String, dynamic>> _payments = const [];

  bool _savingPlans = false;
  bool _savingBilling = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final f in _forms.values) {
      f.dispose();
    }
    _ppId.dispose();
    _ppName.dispose();
    _lineId.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Plan catalog — readable by any signed-in user per rules.
      Map<String, dynamic> tiers = Map.of(_kDefaultTiers);
      final snap = await FirebaseFirestore.instance
          .collection('config')
          .doc('plans')
          .get();
      final data = snap.data();
      if (data != null && data['tiers'] is Map) {
        tiers = Map<String, dynamic>.from(data['tiers'] as Map);
      }
      for (final f in _forms.values) {
        f.dispose();
      }
      _forms.clear();
      for (final key in _kTierOrder) {
        final t = tiers[key];
        _forms[key] = _TierForm(t is Map
            ? Map<String, dynamic>.from(t)
            : Map<String, dynamic>.from(_kDefaultTiers[key]!));
      }

      final billing = await AdminService.getBilling();
      _ppId.text = (billing['promptpayId'] ?? '') as String;
      _ppName.text = (billing['promptpayName'] ?? '') as String;
      _lineId.text = (billing['founderLineUserId'] ?? '') as String;

      _payments = await AdminService.listSubscriptionPayments();

      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  Future<void> _savePlans() async {
    for (final entry in _forms.entries) {
      final f = entry.value;
      if (f.name.text.trim().isEmpty ||
          (int.tryParse(f.monthly.text.trim()) ?? 0) <= 0 ||
          (int.tryParse(f.yearly.text.trim()) ?? 0) <= 0) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('แผน ${entry.key}: กรอกชื่อ + ราคาให้ครบ (จำนวนเต็มบาท)'),
          backgroundColor: Colors.red,
        ));
        return;
      }
    }
    setState(() => _savingPlans = true);
    try {
      await AdminService.upsertPlans(
          {for (final e in _forms.entries) e.key: e.value.toTier()});
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('บันทึกแผนแล้ว — มีผลกับหน้าเว็บทันที')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('บันทึกไม่สำเร็จ: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _savingPlans = false);
    }
  }

  Future<void> _saveBilling() async {
    setState(() => _savingBilling = true);
    try {
      await AdminService.setBilling(
        promptpayId: _ppId.text.trim(),
        promptpayName: _ppName.text.trim(),
        founderLineUserId: _lineId.text.trim(),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('บันทึกบัญชีรับเงินแล้ว')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('บันทึกไม่สำเร็จ: $e'), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _savingBilling = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return _ErrorView(message: _error!, onRetry: _load);
    }
    final cs = Theme.of(context).colorScheme;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── บัญชีรับเงินบริษัท ──
          Text('บัญชีรับเงิน (PromptPay บริษัท)',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('ใช้รับค่าต่ออายุจากร้านค้า + แจ้งเตือน LINE เมื่อมีการจ่าย',
              style: TextStyle(
                  fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6))),
          const SizedBox(height: 12),
          TextField(
            controller: _ppId,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'PromptPay ID (เบอร์ 10 หลัก / บัตร ปชช. 13 หลัก)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _ppName,
            decoration: const InputDecoration(
              labelText: 'ชื่อบัญชีผู้รับ (โชว์ให้คนจ่ายเช็ค)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _lineId,
            decoration: const InputDecoration(
              labelText: 'LINE userId ของ founder (รับแจ้งเตือนจ่ายเงิน)',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _savingBilling ? null : _saveBilling,
            icon: const Icon(Icons.save_outlined, size: 18),
            label: Text(_savingBilling ? 'กำลังบันทึก…' : 'บันทึกบัญชีรับเงิน'),
          ),
          const Divider(height: 36),

          // ── แผน & ราคา ──
          Text('แผน & ราคา', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('แก้แล้วมีผลกับหน้า pok-pok.app/subscribe และการคิดเงินทันที (ราคาเป็นบาท)',
              style: TextStyle(
                  fontSize: 12, color: cs.onSurface.withValues(alpha: 0.6))),
          const SizedBox(height: 8),
          for (final key in _kTierOrder) _tierCard(key, _forms[key]!),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _savingPlans ? null : _savePlans,
            icon: const Icon(Icons.save_outlined, size: 18),
            label: Text(_savingPlans ? 'กำลังบันทึก…' : 'บันทึกแผนทั้งหมด'),
          ),
          const Divider(height: 36),

          // ── การชำระล่าสุด (PromptPay) ──
          Text('ต่ออายุผ่าน PromptPay ล่าสุด',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (_payments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text('ยังไม่มีรายการ',
                  style:
                      TextStyle(color: cs.onSurface.withValues(alpha: 0.5))),
            )
          else
            for (final p in _payments) _paymentTile(p),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _tierCard(String key, _TierForm f) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      child: ExpansionTile(
        title: Text('${_tierLabel(key)}'
            ' · ฿${f.monthly.text}/ด · ฿${f.yearly.text}/ป'
            '${f.enabled ? '' : ' (ปิดขาย)'}'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
        children: [
          TextField(
            controller: f.name,
            decoration: const InputDecoration(
                labelText: 'ชื่อแผน', border: OutlineInputBorder(), isDense: true),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: f.desc,
            maxLines: 2,
            decoration: const InputDecoration(
                labelText: 'คำอธิบาย', border: OutlineInputBorder(), isDense: true),
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: TextField(
                controller: f.monthly,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                    labelText: 'รายเดือน (บาท)',
                    prefixText: '฿',
                    border: OutlineInputBorder(),
                    isDense: true),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: TextField(
                controller: f.yearly,
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                    labelText: 'รายปี (บาท)',
                    prefixText: '฿',
                    border: OutlineInputBorder(),
                    isDense: true),
              ),
            ),
          ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('เปิดขาย'),
            value: f.enabled,
            onChanged: (v) => setState(() => f.enabled = v),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('ป้าย "แนะนำ"'),
            value: f.featured,
            onChanged: (v) => setState(() => f.featured = v),
          ),
        ],
      ),
    );
  }

  Widget _paymentTile(Map<String, dynamic> p) {
    final paid = p['status'] == 'paid';
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        paid ? Icons.check_circle : Icons.hourglass_empty,
        color: paid ? Colors.green : Colors.orange,
        size: 20,
      ),
      title: Text(
          '${p['shopName'] ?? p['shopId']} · ${_tierLabel('${p['tier']}')} '
          '${p['billingCycle'] == 'yearly' ? 'รายปี' : 'รายเดือน'}'),
      subtitle: Text(
          '฿${(p['finalAmount'] as num?)?.toStringAsFixed(2) ?? '-'} · ${_date(p['paidAt'] ?? p['createdAt'])} · ${p['status']}'),
    );
  }
}
