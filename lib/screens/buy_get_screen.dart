import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import '../models/product.dart';
import '../services/auth_service.dart';
import '../services/product_service.dart';
import '../services/shop_database.dart';

class BuyGetScreen extends StatefulWidget {
  const BuyGetScreen({super.key});
  @override
  State<BuyGetScreen> createState() => _BuyGetScreenState();
}

class _BuyGetScreenState extends State<BuyGetScreen> {
  late final _products = ProductService.watchAll();
  late final _promotions =
      ShopDatabase.shop.collection('buyGetPromotions').snapshots();
  String _query = '';
  final _busy = <String>{};

  Future<void> _manage(Map<String, dynamic> data) async {
    await FirebaseFunctions.instanceFor(region: 'asia-southeast1')
        .httpsCallable('manageBuyGet')
        .call({...data, 'shopId': AuthService.shopId});
  }

  Future<void> _toggle(String id, bool active) async {
    setState(() => _busy.add(id));
    try {
      await _manage({'action': 'toggle', 'buyProductId': id, 'active': active});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(e is FirebaseFunctionsException
                ? e.message ?? 'บันทึกไม่สำเร็จ'
                : 'บันทึกไม่สำเร็จ กรุณาลองใหม่')));
      }
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('ซื้อแถม')),
        body: AuthService.isStaff
            ? const Center(child: Text('เฉพาะเจ้าของร้าน'))
            : StreamBuilder<List<Product>>(
                stream: _products,
                builder: (context, products) => StreamBuilder<
                        QuerySnapshot<Map<String, dynamic>>>(
                    stream: _promotions,
                    builder: (context, promos) {
                      if (products.hasError || promos.hasError) {
                        return const Center(
                            child: Text('โหลดไม่สำเร็จ กรุณาเปิดหน้านี้ใหม่'));
                      }
                      if (!products.hasData || !promos.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      final configs = {
                        for (final doc in promos.data!.docs) doc.id: doc.data()
                      };
                      final all = products.data!;
                      final filtered = all
                          .where((p) => p.name.toLowerCase().contains(_query));
                      return ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            const Text(
                                'ซื้อครบ รับของแถมที่เคาน์เตอร์และลิงก์สั่งสินค้าที่ชำระก่อนรับ\n'
                                '1 โปรต่อสินค้าที่ซื้อ • ใช้ร่วมกับราคาโปรและส่วนลดท้ายบิลได้ โค้ดส่วนลดใช้เฉพาะออนไลน์\n'
                                'ต้องเชื่อมอินเทอร์เน็ต ไม่ใช้กับบิลโต๊ะแบบจ่ายทีหลัง\n'
                                'ของแถมไม่สะสมสิทธิ์ต่อ และตัดสต็อก/วัตถุดิบตามจริง หากของไม่พอต้องปรับตะกร้าก่อนสั่ง'),
                            const SizedBox(height: 12),
                            TextField(
                                decoration: const InputDecoration(
                                    labelText: 'ค้นหาสินค้าที่ต้องซื้อ',
                                    prefixIcon: Icon(Icons.search)),
                                onChanged: (value) => setState(
                                    () => _query = value.trim().toLowerCase())),
                            const SizedBox(height: 12),
                            if (all.isEmpty)
                              const Text('เพิ่มสินค้าก่อนตั้งโปรซื้อแถม'),
                            for (final product in filtered)
                              Builder(builder: (context) {
                                final c = configs[product.id];
                                final until =
                                    (c?['endsAt'] as Timestamp?)?.toDate();
                                final expired = until != null &&
                                    !until.isAfter(DateTime.now());
                                final thai = until
                                    ?.toUtc()
                                    .add(const Duration(hours: 7));
                                return Card(
                                    child: Padding(
                                        padding: const EdgeInsets.all(12),
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(product.name,
                                                  style: const TextStyle(
                                                      fontWeight:
                                                          FontWeight.bold)),
                                              if (c != null) ...[
                                                Text(
                                                    'ซื้อ ${c['buyQuantity']} แถม ${c['giftName']} ${c['giftQuantity']} ชิ้น'),
                                                Text(
                                                    'สูงสุด ${c['maxSets']} ชุดต่อออเดอร์'),
                                                if (thai != null)
                                                  Text(
                                                      'ถึง ${thai.day}/${thai.month}/${thai.year} สิ้นวัน (เวลาไทย)'),
                                                SwitchListTile(
                                                    contentPadding:
                                                        EdgeInsets.zero,
                                                    title: Text(expired
                                                        ? 'หมดอายุ'
                                                        : c['active'] == true
                                                            ? 'เปิดใช้งาน'
                                                            : 'ปิดใช้งาน'),
                                                    value:
                                                        c['active'] == true &&
                                                            !expired,
                                                    onChanged: expired ||
                                                            _busy.contains(
                                                                product.id)
                                                        ? null
                                                        : (value) => _toggle(
                                                            product.id, value)),
                                              ],
                                              OutlinedButton.icon(
                                                  icon: const Icon(
                                                      Icons.card_giftcard),
                                                  label: Text(c == null
                                                      ? 'ตั้งโปรซื้อแถม'
                                                      : 'แก้ไขโปรซื้อแถม'),
                                                  onPressed: () => showDialog(
                                                      context: context,
                                                      barrierDismissible: false,
                                                      builder: (_) =>
                                                          BuyGetEditor(
                                                              product: product,
                                                              products: all,
                                                              initial: c,
                                                              onSave:
                                                                  _manage))),
                                            ])));
                              }),
                          ]);
                    })),
      );
}

class BuyGetEditor extends StatefulWidget {
  const BuyGetEditor(
      {super.key,
      required this.product,
      required this.products,
      required this.onSave,
      this.initial});
  final Product product;
  final List<Product> products;
  final Map<String, dynamic>? initial;
  final Future<void> Function(Map<String, dynamic>) onSave;
  @override
  State<BuyGetEditor> createState() => _BuyGetEditorState();
}

class _BuyGetEditorState extends State<BuyGetEditor> {
  final _form = GlobalKey<FormState>();
  late final _buy =
      TextEditingController(text: '${widget.initial?['buyQuantity'] ?? 2}');
  late final _gift =
      TextEditingController(text: '${widget.initial?['giftQuantity'] ?? 1}');
  late final _max =
      TextEditingController(text: '${widget.initial?['maxSets'] ?? 1}');
  late final _choices =
      widget.products.where((p) => p.modifierGroupIds.isEmpty).toList();
  String? _giftId, _error;
  bool _saving = false;
  late DateTime _date;
  @override
  void initState() {
    super.initState();
    final desired = widget.initial?['giftProductId'] ?? widget.product.id;
    _giftId = _choices.any((p) => p.id == desired) ? desired as String : null;
    final until = (widget.initial?['endsAt'] as Timestamp?)?.toDate();
    final thai = (until != null && until.isAfter(DateTime.now())
            ? until
            : DateTime.now().add(const Duration(days: 30)))
        .toUtc()
        .add(const Duration(hours: 7));
    _date = DateTime(thai.year, thai.month, thai.day);
  }

  @override
  void dispose() {
    _buy.dispose();
    _gift.dispose();
    _max.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    if (int.parse(_gift.text) * int.parse(_max.text) > 99) {
      setState(() => _error = 'ของแถมรวมต้องไม่เกิน 99 ชิ้นต่อออเดอร์');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave({
        'action': 'save',
        'buyProductId': widget.product.id,
        'giftProductId': _giftId,
        'buyQuantity': int.parse(_buy.text),
        'giftQuantity': int.parse(_gift.text),
        'maxSets': int.parse(_max.text),
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
              : 'บันทึกไม่สำเร็จ กรุณาลองใหม่';
        });
      }
    }
  }

  Widget _number(TextEditingController controller, String label, int limit) =>
      TextFormField(
          controller: controller,
          enabled: !_saving,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(labelText: label),
          validator: (value) {
            final n = int.tryParse(value ?? '');
            return n == null || n < 1 || n > limit
                ? 'ระบุจำนวนเต็ม 1–$limit'
                : null;
          });

  @override
  Widget build(BuildContext context) => PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: const Text('ตั้งโปรซื้อแถม'),
        content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
                child: Form(
                    key: _form,
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('ซื้อ ${widget.product.name}'),
                          _number(_buy, 'จำนวนที่ต้องซื้อ', 99),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                              initialValue: _giftId,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                  labelText: 'สินค้าที่แถม'),
                              items: _choices
                                  .map((p) => DropdownMenuItem(
                                      value: p.id,
                                      child: Text(p.name,
                                          overflow: TextOverflow.ellipsis)))
                                  .toList(),
                              onChanged: _saving
                                  ? null
                                  : (value) => setState(() => _giftId = value),
                              validator: (value) =>
                                  value == null ? 'เลือกสินค้าแถม' : null),
                          const Text(
                              'เลือกได้เฉพาะสินค้าที่ไม่มีตัวเลือกเสริม เพื่อให้ร้านเตรียมของแถมได้ตรงกัน'),
                          _number(_gift, 'จำนวนแถมต่อชุด', 99),
                          _number(_max, 'สูงสุดกี่ชุดต่อออเดอร์', 10),
                          TextButton.icon(
                              icon: const Icon(Icons.event),
                              label: Text(
                                  'ถึง ${_date.day}/${_date.month}/${_date.year} (เวลาไทย)'),
                              onPressed: _saving
                                  ? null
                                  : () async {
                                      final thai = DateTime.now()
                                          .toUtc()
                                          .add(const Duration(hours: 7));
                                      final today = DateTime(
                                          thai.year, thai.month, thai.day);
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
                                    }),
                          const Text(
                              'บันทึกแล้วเริ่มใช้ทันที แทนโปรเดิมของสินค้านี้ ออเดอร์ที่สร้างแล้วไม่เปลี่ยน\n'
                              'ของแถมราคา 0 บาท แต่มีต้นทุนและใช้สต็อกตามจริง'),
                          if (_error != null)
                            Text(_error!,
                                style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.error)),
                        ])))),
        actions: [
          TextButton(
              onPressed: _saving ? null : () => Navigator.pop(context),
              child: const Text('ยกเลิก')),
          FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(_saving ? 'กำลังบันทึก…' : 'บันทึก'))
        ],
      ));
}
