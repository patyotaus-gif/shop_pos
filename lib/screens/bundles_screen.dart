import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import '../models/product.dart';
import '../services/auth_service.dart';
import '../services/product_service.dart';
import '../services/shop_database.dart';

class BundlesScreen extends StatefulWidget {
  const BundlesScreen({super.key});
  @override
  State<BundlesScreen> createState() => _BundlesScreenState();
}

class _BundlesScreenState extends State<BundlesScreen> {
  late final _products = ProductService.watchAll();
  late final _configs = ShopDatabase.shop
      .collection('promotionSettings')
      .doc('bundles')
      .snapshots();
  bool _busy = false;
  Future<void> _manage(Map<String, dynamic> data) async {
    await FirebaseFunctions.instanceFor(region: 'asia-southeast1')
        .httpsCallable('manageBundle')
        .call({...data, 'shopId': AuthService.shopId});
  }

  Future<void> _change(Map<String, dynamic> data) async {
    setState(() => _busy = true);
    try {
      await _manage(data);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e is FirebaseFunctionsException
                ? e.message ?? 'บันทึกไม่สำเร็จ'
                : 'บันทึกไม่สำเร็จ กรุณาลองใหม่')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _edit(List<Product> products, [Map<String, dynamic>? initial]) {
    showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => BundleEditor(
            products: products, initial: initial, onSave: _manage));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('ชุดสินค้า')),
        body: AuthService.isStaff
            ? const Center(child: Text('เฉพาะเจ้าของร้าน'))
            : StreamBuilder<List<Product>>(
                stream: _products,
                builder: (context, products) => StreamBuilder<
                        DocumentSnapshot<Map<String, dynamic>>>(
                    stream: _configs,
                    builder: (context, configs) {
                      if (products.hasError || configs.hasError) {
                        return const Center(
                            child: Text('โหลดไม่สำเร็จ กรุณาเปิดหน้านี้ใหม่'));
                      }
                      if (!products.hasData || !configs.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final bundles =
                          ((configs.data!.data()?['bundles'] as List?) ?? [])
                              .map((b) => Map<String, dynamic>.from(b as Map))
                              .toList();
                      return ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            const Text(
                                'เลือกสินค้าครบชุด ระบบลดให้เป็นราคาชุดอัตโนมัติก่อนชำระเงิน ทั้งเคาน์เตอร์และลิงก์สั่งสินค้า\n'
                                'ใช้ได้ขณะออนไลน์ ไม่ใช้กับบิลโต๊ะแบบจ่ายทีหลัง\n'
                                'สินค้าแต่ละชนิดอยู่ได้ในชุดที่เปิดใช้เพียงชุดเดียว และต้องไม่มีตัวเลือกเสริม\n'
                                'ใช้ร่วมกับซื้อแถมได้ คูปองและส่วนลดท้ายบิลคิดต่อจากราคาชุด หากซื้อแยกถูกกว่าจะใช้ราคาที่ถูกกว่า'),
                            const SizedBox(height: 12),
                            Align(
                                alignment: Alignment.centerLeft,
                                child: FilledButton.icon(
                                    onPressed: _busy
                                        ? null
                                        : () => _edit(products.data!),
                                    icon: const Icon(Icons.add),
                                    label: const Text('สร้างชุดสินค้า'))),
                            if (bundles.isEmpty)
                              const Padding(
                                  padding: EdgeInsets.all(24),
                                  child: Text(
                                      'ยังไม่มีชุดสินค้า เช่น กาแฟ + ขนม ราคาพิเศษ')),
                            for (final b in bundles)
                              Card(
                                  child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(b['name'] as String,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .titleMedium),
                                            for (final c
                                                in b['components'] as List)
                                              Text(
                                                  '${c['productName'] ?? c['productId']} × ${c['quantity']}'),
                                            Text(
                                                'ราคาชุด ${((b['priceMinor'] as num) / 100).toStringAsFixed(2)} บาท • สูงสุด ${b['maxSets']} ชุดต่อบิล'),
                                            Builder(builder: (_) {
                                              final until = (b['endsAt']
                                                      as Timestamp)
                                                  .toDate()
                                                  .toUtc()
                                                  .add(
                                                      const Duration(hours: 7));
                                              return Text(
                                                  'ถึง ${until.day}/${until.month}/${until.year} สิ้นวัน (เวลาไทย)');
                                            }),
                                            SwitchListTile(
                                                contentPadding: EdgeInsets.zero,
                                                title: Text(
                                                    (b['endsAt'] as Timestamp)
                                                            .toDate()
                                                            .isBefore(
                                                                DateTime.now())
                                                        ? 'หมดอายุ'
                                                        : 'เปิดใช้งาน'),
                                                value: b['active'] == true &&
                                                    (b['endsAt'] as Timestamp)
                                                        .toDate()
                                                        .isAfter(
                                                            DateTime.now()),
                                                onChanged: _busy
                                                    ? null
                                                    : (v) => _change({
                                                          'action': 'toggle',
                                                          'id': b['id'],
                                                          'active': v
                                                        })),
                                            Wrap(spacing: 8, children: [
                                              OutlinedButton(
                                                  onPressed: _busy
                                                      ? null
                                                      : () => _edit(
                                                          products.data!, b),
                                                  child: const Text('แก้ไข')),
                                              TextButton(
                                                  onPressed: _busy
                                                      ? null
                                                      : () async {
                                                          final confirmed = await showDialog<
                                                                  bool>(
                                                              context: context,
                                                              builder: (context) =>
                                                                  AlertDialog(
                                                                      title: Text(
                                                                          'ลบชุด ${b['name']}?'),
                                                                      content:
                                                                          const Text(
                                                                              'ประวัติการขายเดิมยังคงอยู่'),
                                                                      actions: [
                                                                        TextButton(
                                                                            onPressed: () => Navigator.pop(context,
                                                                                false),
                                                                            child:
                                                                                const Text('กลับ')),
                                                                        FilledButton(
                                                                            onPressed: () => Navigator.pop(context,
                                                                                true),
                                                                            child:
                                                                                const Text('ลบชุด'))
                                                                      ]));
                                                          if (confirmed ==
                                                                  true &&
                                                              mounted) {
                                                            await _change({
                                                              'action':
                                                                  'delete',
                                                              'id': b['id']
                                                            });
                                                          }
                                                        },
                                                  child: const Text('ลบชุด')),
                                            ]),
                                          ]))),
                          ]);
                    })),
      );
}

class BundleEditor extends StatefulWidget {
  const BundleEditor(
      {super.key, required this.products, required this.onSave, this.initial});
  final List<Product> products;
  final Map<String, dynamic>? initial;
  final Future<void> Function(Map<String, dynamic>) onSave;
  @override
  State<BundleEditor> createState() => _BundleEditorState();
}

class _BundleEditorState extends State<BundleEditor> {
  final _form = GlobalKey<FormState>();
  late final _name =
      TextEditingController(text: widget.initial?['name'] as String?);
  late final _price = TextEditingController(
      text: widget.initial == null
          ? ''
          : ((widget.initial!['priceMinor'] as num) / 100).toStringAsFixed(2));
  late final _max =
      TextEditingController(text: '${widget.initial?['maxSets'] ?? 1}');
  final _ids = <String?>[];
  final _quantities = <TextEditingController>[];
  late DateTime _date;
  bool _busy = false;
  String? _error;
  List<Product> get _available => widget.products
      .where((p) =>
          p.modifierGroupIds.isEmpty &&
          (!p.isRecipeMode || p.recipe.isNotEmpty))
      .toList();
  @override
  void initState() {
    super.initState();
    final parts = widget.initial?['components'] as List? ?? [{}, {}];
    for (final p in parts) {
      _ids.add(_available.any((v) => v.id == p['productId'])
          ? p['productId'] as String
          : null);
      _quantities.add(TextEditingController(text: '${p['quantity'] ?? 1}'));
    }
    final old = (widget.initial?['endsAt'] as Timestamp?)
        ?.toDate()
        .toUtc()
        .add(const Duration(hours: 7));
    final now = DateTime.now().toUtc().add(const Duration(hours: 7));
    _date = old != null && old.isAfter(now)
        ? DateTime(old.year, old.month, old.day)
        : DateTime(now.year, now.month, now.day + 30);
  }

  @override
  void dispose() {
    for (final c in [_name, _price, _max, ..._quantities]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final price = double.parse(_price.text.trim()), max = int.parse(_max.text);
    final parts = [
      for (var n = 0; n < _ids.length; n++)
        {'productId': _ids[n]!, 'quantity': int.parse(_quantities[n].text)}
    ];
    final full = parts.fold<int>(
        0,
        (s, c) =>
            s +
            (_available
                            .firstWhere((p) => p.id == c['productId'])
                            .effectivePrice *
                        100)
                    .round() *
                (c['quantity'] as int));
    if (_ids.toSet().length != _ids.length ||
        (price * 100).round() >= full ||
        parts.any((c) => (c['quantity'] as int) * max > 99)) {
      setState(() => _error =
          'เลือกสินค้าไม่ซ้ำ ราคาชุดต้องต่ำกว่าราคารวม และแต่ละชนิดรวมไม่เกิน 99 ชิ้น');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSave({
        'action': 'save',
        if (widget.initial != null) 'id': widget.initial!['id'],
        'name': _name.text.trim(),
        'components': parts,
        'priceMinor': (price * 100).round(),
        'maxSets': max,
        'endsAt': DateTime.utc(_date.year, _date.month, _date.day + 1)
                .subtract(const Duration(hours: 7))
                .millisecondsSinceEpoch -
            1
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _error = e is FirebaseFunctionsException
            ? e.message
            : 'บันทึกไม่สำเร็จ กรุณาลองใหม่');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title:
            Text(widget.initial == null ? 'สร้างชุดสินค้า' : 'แก้ไขชุดสินค้า'),
        content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
                child: Form(
                    key: _form,
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextFormField(
                              controller: _name,
                              enabled: !_busy,
                              maxLength: 80,
                              decoration:
                                  const InputDecoration(labelText: 'ชื่อชุด'),
                              validator: (v) => v == null || v.trim().isEmpty
                                  ? 'ระบุชื่อชุด'
                                  : null),
                          for (var n = 0; n < _ids.length; n++)
                            Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: Column(children: [
                                  DropdownButtonFormField<String>(
                                      initialValue: _ids[n],
                                      isExpanded: true,
                                      decoration: InputDecoration(
                                          labelText: 'สินค้า ${n + 1}'),
                                      items: _available
                                          .map((p) => DropdownMenuItem(
                                              value: p.id,
                                              child: Text(p.name,
                                                  overflow:
                                                      TextOverflow.ellipsis)))
                                          .toList(),
                                      onChanged: _busy
                                          ? null
                                          : (v) => setState(() => _ids[n] = v),
                                      validator: (v) =>
                                          v == null ? 'เลือกสินค้า' : null),
                                  TextFormField(
                                      controller: _quantities[n],
                                      enabled: !_busy,
                                      keyboardType: TextInputType.number,
                                      decoration: const InputDecoration(
                                          labelText: 'จำนวนต่อชุด'),
                                      validator: (v) {
                                        final q = int.tryParse(v ?? '');
                                        return q == null || q < 1 || q > 99
                                            ? 'ระบุ 1–99'
                                            : null;
                                      }),
                                ])),
                          Wrap(spacing: 8, children: [
                            TextButton.icon(
                                onPressed: _busy || _ids.length >= 10
                                    ? null
                                    : () => setState(() {
                                          _ids.add(null);
                                          _quantities.add(
                                              TextEditingController(text: '1'));
                                        }),
                                icon: const Icon(Icons.add),
                                label: const Text('เพิ่มสินค้าในชุด')),
                            if (_ids.length > 2)
                              TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => setState(() {
                                            _ids.removeLast();
                                            _quantities.removeLast().dispose();
                                          }),
                                  child: const Text('ลบแถวสุดท้าย')),
                          ]),
                          TextFormField(
                              controller: _price,
                              enabled: !_busy,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                      decimal: true),
                              decoration: const InputDecoration(
                                  labelText: 'ราคาชุด (บาท)'),
                              validator: (v) {
                                final p = double.tryParse(v ?? '');
                                return p == null ||
                                        !p.isFinite ||
                                        p <= 0 ||
                                        !RegExp(r'^\d+(\.\d{1,2})?$')
                                            .hasMatch(v!.trim())
                                    ? 'ระบุราคาทศนิยมไม่เกิน 2 ตำแหน่ง'
                                    : null;
                              }),
                          TextFormField(
                              controller: _max,
                              enabled: !_busy,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                  labelText: 'สูงสุดกี่ชุดต่อบิล'),
                              validator: (v) {
                                final q = int.tryParse(v ?? '');
                                return q == null || q < 1 || q > 10
                                    ? 'ระบุ 1–10'
                                    : null;
                              }),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                              onPressed: _busy
                                  ? null
                                  : () async {
                                      final now = DateTime.now()
                                          .toUtc()
                                          .add(const Duration(hours: 7));
                                      final today = DateTime(
                                          now.year, now.month, now.day);
                                      final date = await showDatePicker(
                                          context: context,
                                          initialDate: _date.isBefore(today)
                                              ? today
                                              : _date,
                                          firstDate: today,
                                          lastDate: today
                                              .add(const Duration(days: 365)));
                                      if (date != null && mounted) {
                                        setState(() => _date = date);
                                      }
                                    },
                              icon: const Icon(Icons.calendar_today),
                              label: Text(
                                  'ถึง ${_date.day}/${_date.month}/${_date.year} (เวลาไทย)')),
                          const Text(
                              'เมื่อเลือกสินค้าครบจะลดให้อัตโนมัติ ก่อนคิดคูปองหรือส่วนลดท้ายบิล ใช้ร่วมกับซื้อแถมได้'),
                          if (_error != null)
                            Text(_error!,
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error)),
                        ])))),
        actions: [
          TextButton(
              onPressed: _busy ? null : () => Navigator.pop(context),
              child: const Text('ยกเลิก')),
          FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? 'กำลังบันทึก…' : 'บันทึกชุด'))
        ],
      );
}
