import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auth_service.dart';
import '../services/shop_database.dart';

class CouponsScreen extends StatefulWidget {
  const CouponsScreen({super.key});
  @override
  State<CouponsScreen> createState() => _CouponsScreenState();
}

class _CouponsScreenState extends State<CouponsScreen> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _coupons;
  final _busy = <String>{};
  @override
  void initState() {
    super.initState();
    _coupons = ShopDatabase.shop
        .collection('coupons')
        .orderBy('createdAt', descending: true)
        .snapshots();
  }

  Future<void> _manage(Map<String, dynamic> data) async {
    await FirebaseFunctions.instanceFor(region: 'asia-southeast1')
        .httpsCallable('manageCoupon')
        .call({...data, 'shopId': AuthService.shopId});
  }

  Future<void> _toggle(String code, bool active) async {
    setState(() => _busy.add(code));
    try {
      await _manage({'action': 'toggle', 'code': code, 'active': active});
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('บันทึกไม่สำเร็จ กรุณาลองใหม่')));
      }
    } finally {
      if (mounted) setState(() => _busy.remove(code));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('โค้ดส่วนลด')),
        floatingActionButton: AuthService.isStaff
            ? null
            : FloatingActionButton.extended(
                icon: const Icon(Icons.add),
                label: const Text('สร้างโค้ด'),
                onPressed: () => showDialog(
                    context: context,
                    barrierDismissible: false,
                    builder: (_) => CouponEditor(onSave: _manage))),
        body: AuthService.isStaff
            ? const Center(child: Text('เฉพาะเจ้าของร้าน'))
            : Column(children: [
                const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                        'ใช้ในลิงก์สั่งสินค้าที่ชำระก่อนรับ • 1 โค้ดต่อออเดอร์\nคิดส่วนลดจากราคาสินค้าปัจจุบัน รวมราคาโปร ยอดหลังลดขั้นต่ำ 20 บาท\nสิทธิ์นับรวมออเดอร์รอชำระ ยกเลิกก่อนชำระจึงคืนสิทธิ์ คืนเงินหลังชำระไม่คืนสิทธิ์')),
                Expanded(
                    child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: _coupons,
                        builder: (context, snap) {
                          if (snap.hasError) {
                            return const Center(
                                child: Text(
                                    'โหลดคูปองไม่สำเร็จ กรุณาเปิดหน้านี้ใหม่'));
                          }
                          if (!snap.hasData) {
                            return const Center(
                                child: CircularProgressIndicator());
                          }
                          if (snap.data!.docs.isEmpty) {
                            return const Center(
                                child: Text(
                                    'ยังไม่มีโค้ดส่วนลด แตะสร้างโค้ดเพื่อเริ่มต้น'));
                          }
                          return ListView(
                              padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                              children: snap.data!.docs.map((doc) {
                                final c = doc.data(),
                                    until = (c['endsAt'] as Timestamp).toDate();
                                final expired = !until.isAfter(DateTime.now());
                                final code = doc.id;
                                // Coupon cut-off dates are entered and displayed in Thailand time.
                                final date =
                                    until.toUtc().add(const Duration(hours: 7));
                                return Card(
                                    child: Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(code,
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleLarge),
                                              Text(c['kind'] == 'percent'
                                                  ? 'ลด ${c['value']}%'
                                                  : 'ลด ฿${((c['value'] as num) / 100).toStringAsFixed(2)}'),
                                              Text(
                                                  'ซื้อขั้นต่ำ ฿${((c['minSubtotalMinor'] as num) / 100).toStringAsFixed(2)}'),
                                              Text(
                                                  'ใช้/จองแล้ว ${c['claimed']} จาก ${c['maxUses']} สิทธิ์'),
                                              Text(
                                                  'สิ้นสุด ${date.day}/${date.month}/${date.year} สิ้นวัน (เวลาไทย)'),
                                              if (expired)
                                                const Text('หมดอายุแล้ว'),
                                              SwitchListTile(
                                                  contentPadding:
                                                      EdgeInsets.zero,
                                                  title: const Text(
                                                      'เปิดให้ใช้โค้ด'),
                                                  value: c['active'] == true,
                                                  onChanged: expired ||
                                                          _busy.contains(code)
                                                      ? null
                                                      : (active) => _toggle(
                                                          code, active)),
                                              TextButton.icon(
                                                  icon: const Icon(Icons.copy),
                                                  label:
                                                      const Text('คัดลอกโค้ด'),
                                                  onPressed: () async {
                                                    await Clipboard.setData(
                                                        ClipboardData(
                                                            text: code));
                                                    if (context.mounted) {
                                                      ScaffoldMessenger.of(
                                                              context)
                                                          .showSnackBar(
                                                              const SnackBar(
                                                                  content: Text(
                                                                      'คัดลอกโค้ดแล้ว')));
                                                    }
                                                  }),
                                            ])));
                              }).toList());
                        })),
              ]),
      );
}

class CouponEditor extends StatefulWidget {
  const CouponEditor({super.key, required this.onSave});
  final Future<void> Function(Map<String, dynamic>) onSave;
  @override
  State<CouponEditor> createState() => _CouponEditorState();
}

class _CouponEditorState extends State<CouponEditor> {
  final _form = GlobalKey<FormState>();
  final _code = TextEditingController(), _value = TextEditingController();
  final _minimum = TextEditingController(text: '0'),
      _uses = TextEditingController(text: '100');
  bool _percent = true, _saving = false;
  late DateTime _date;
  String? _error;
  @override
  void initState() {
    super.initState();
    final thai = DateTime.now().toUtc().add(const Duration(hours: 7, days: 30));
    _date = DateTime(thai.year, thai.month, thai.day);
  }

  @override
  void dispose() {
    for (final c in [_code, _value, _minimum, _uses]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave({
        'action': 'create',
        'code': _code.text.trim().toUpperCase(),
        'kind': _percent ? 'percent' : 'fixed',
        'value': _percent
            ? int.parse(_value.text.trim())
            : (double.parse(_value.text) * 100).round(),
        'minSubtotalMinor': (double.parse(_minimum.text) * 100).round(),
        'maxUses': int.parse(_uses.text),
        'endsAt':
            DateTime.utc(_date.year, _date.month, _date.day, 16, 59, 59, 999)
                .millisecondsSinceEpoch
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e is FirebaseFunctionsException
              ? e.message
              : 'สร้างโค้ดไม่สำเร็จ กรุณาลองใหม่';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: const Text('สร้างโค้ดส่วนลด'),
        content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
                child: Form(
                    key: _form,
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      TextFormField(
                          controller: _code,
                          enabled: !_saving,
                          decoration: const InputDecoration(
                              labelText: 'โค้ด เช่น WELCOME10'),
                          validator: (v) => RegExp(r'^[A-Z0-9_-]{3,24}$')
                                  .hasMatch((v ?? '').trim().toUpperCase())
                              ? null
                              : 'ใช้ A-Z ตัวเลข - _ จำนวน 3–24 ตัว'),
                      Wrap(spacing: 8, children: [
                        for (final p in [true, false])
                          ChoiceChip(
                              label: Text(p ? 'ลดเปอร์เซ็นต์' : 'ลดเป็นบาท'),
                              selected: _percent == p,
                              onSelected: _saving
                                  ? null
                                  : (_) => setState(() {
                                        _percent = p;
                                        _value.clear();
                                      }))
                      ]),
                      TextFormField(
                          controller: _value,
                          enabled: !_saving,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: InputDecoration(
                              labelText:
                                  _percent ? 'ส่วนลด 1–99%' : 'ส่วนลด (บาท)'),
                          validator: (v) {
                            final n = double.tryParse(v ?? '');
                            if (n == null || !n.isFinite || n <= 0) {
                              return 'กรุณาระบุส่วนลดมากกว่า 0';
                            }
                            if (_percent &&
                                (int.tryParse(v!.trim()) == null || n > 99)) {
                              return 'ระบุจำนวนเต็ม 1–99';
                            }
                            if (!_percent &&
                                ((n * 100).round() < 1 || n > 100000)) {
                              return 'ระบุ 0.01–100000 บาท';
                            }
                            return null;
                          }),
                      TextFormField(
                          controller: _minimum,
                          enabled: !_saving,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true),
                          decoration: const InputDecoration(
                              labelText: 'ยอดซื้อขั้นต่ำก่อนใช้โค้ด (บาท)'),
                          validator: (v) {
                            final n = double.tryParse(v ?? '');
                            return n == null ||
                                    !n.isFinite ||
                                    n < 0 ||
                                    n > 1000000
                                ? 'ระบุยอด 0–1000000 บาท'
                                : null;
                          }),
                      TextFormField(
                          controller: _uses,
                          enabled: !_saving,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                              labelText: 'จำนวนสิทธิ์รวม'),
                          validator: (v) {
                            final n = int.tryParse(v ?? '');
                            return n == null || n < 1 || n > 100000
                                ? 'ระบุ 1–100000 สิทธิ์'
                                : null;
                          }),
                      TextButton.icon(
                          icon: const Icon(Icons.event),
                          label: Text(
                              'ถึง ${_date.day}/${_date.month}/${_date.year} (เวลาไทย)'),
                          onPressed: _saving
                              ? null
                              : () async {
                                  final now = DateTime.now()
                                      .toUtc()
                                      .add(const Duration(hours: 7));
                                  final today =
                                      DateTime(now.year, now.month, now.day);
                                  final date = await showDatePicker(
                                      context: context,
                                      initialDate:
                                          _date.isBefore(today) ? today : _date,
                                      firstDate: today,
                                      lastDate:
                                          today.add(const Duration(days: 365)));
                                  if (date != null && mounted) {
                                    setState(() => _date = date);
                                  }
                                }),
                      const Text(
                          'เริ่มใช้ทันทีหลังสร้าง เงื่อนไขแก้ย้อนหลังไม่ได้ หากต้องการเปลี่ยนให้ปิดโค้ดเดิมแล้วสร้างโค้ดใหม่'),
                      if (_error != null)
                        Text(_error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                    ])))),
        actions: [
          TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: const Text('ยกเลิก')),
          FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'กำลังบันทึก…' : 'สร้างโค้ด'))
        ],
      ));
}
