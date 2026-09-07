import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/shop_database.dart';
import '../services/settings_service.dart';
import '../screens/product_form_screen.dart';
import '../screens/table_form_screen.dart';
import '../screens/settings_screen.dart';
import 'shop_operation.dart';

class ShopSetupChecklist extends StatefulWidget {
  const ShopSetupChecklist({super.key, this.alwaysShow = false});
  final bool alwaysShow;
  @override
  State<ShopSetupChecklist> createState() => _ShopSetupChecklistState();
}

class _ShopSetupChecklistState extends State<ShopSetupChecklist> {
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  bool _products = false,
      _payments = false,
      _tables = false,
      _demo = false,
      _sales = false;
  bool _restaurant = false, _dismissed = false;
  bool _error = false;
  final Set<String> _loaded = {};
  String get _key => 'setup-${ShopDatabase.shop.id}';

  @override
  void initState() {
    super.initState();
    _listen();
  }

  void _listen() {
    final shop = ShopDatabase.shop;
    void update(String name, VoidCallback action) {
      if (mounted) {
        setState(() {
          action();
          _loaded.add(name);
        });
      }
    }

    void error(Object e) {
      if (mounted) setState(() => _error = true);
    }

    _subscriptions.add(shop.snapshots().listen(
        (s) => update(
            'shop', () => _restaurant = s.data()?['tier'] == 'restaurant'),
        onError: error));
    _subscriptions.add(shop.collection('products').limit(1).snapshots().listen(
        (s) => update('products', () => _products = s.docs.isNotEmpty),
        onError: error));
    _subscriptions.add(shop.collection('tables').limit(1).snapshots().listen(
        (s) => update('tables', () => _tables = s.docs.isNotEmpty),
        onError: error));
    _subscriptions.add(shop.collection('sales').limit(1).snapshots().listen(
        (s) => update('sales', () => _sales = s.docs.isNotEmpty),
        onError: error));
    _subscriptions
        .add(shop.collection('settings').doc('shop').snapshots().listen(
            (s) => update('settings', () {
                  final data = s.data() ?? {};
                  _payments = data['onboardingCashReady'] == true ||
                      (data['promptpayId'] as String? ?? '').trim().isNotEmpty;
                }),
            onError: error));
    _loadLocal();
  }

  Future<void> _loadLocal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (mounted) {
        setState(() {
          _demo = prefs.getBool('$_key-demo') ?? false;
          _dismissed = prefs.getBool('$_key-dismissed') ?? false;
          _loaded.add('local');
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loaded.add('local'));
    }
  }

  @override
  void dispose() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    super.dispose();
  }

  Future<void> _paymentsStep() async {
    final choice = await showModalBottomSheet<String>(
        context: context,
        builder: (ctx) => SafeArea(
            child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text('ร้านจะเริ่มรับเงินแบบไหน?',
                          style: Theme.of(ctx).textTheme.titleLarge),
                      const SizedBox(height: 12),
                      FilledButton(
                          onPressed: () => Navigator.pop(ctx, 'cash'),
                          child: const Text('เริ่มจากรับเงินสด')),
                      OutlinedButton(
                          onPressed: () => Navigator.pop(ctx, 'qr'),
                          child: const Text('ไปตั้งค่า QR PromptPay')),
                      const Text(
                          'เปลี่ยนวิธีรับเงินได้ในหน้าชำระเงินของแต่ละบิล'),
                    ]))));
    if (!mounted) return;
    if (choice == 'cash') {
      await performShopOperation(context,
          () => SettingsService.saveSettings({'onboardingCashReady': true}));
    }
    if (choice == 'qr' && mounted) {
      await Navigator.push(
          context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
    }
  }

  Future<void> _demoStep() async {
    final done = await Navigator.push<bool>(
        context, MaterialPageRoute(builder: (_) => const DemoCheckoutScreen()));
    if (done == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('$_key-demo', true);
      if (mounted) setState(() => _demo = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.alwaysShow && (_dismissed || _sales)) {
      return const SizedBox.shrink();
    }
    if (_error) {
      return const Padding(
          padding: EdgeInsets.all(12),
          child: Text('ยังโหลดขั้นตอนตั้งค่าร้านไม่ได้ กรุณาตรวจการเชื่อมต่อ'));
    }
    if (_loaded.length < 6) return const LinearProgressIndicator();
    final done = [
      _products,
      _payments,
      if (_restaurant) _tables,
      _demo || _sales
    ].where((v) => v).length;
    final total = _restaurant ? 4 : 3;
    Widget step(
            String title, String subtitle, bool complete, VoidCallback onTap) =>
        ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(
                complete ? Icons.check_circle : Icons.radio_button_unchecked,
                color: complete ? Colors.green : null),
            title: Text(title),
            subtitle: Text(subtitle),
            trailing: const Icon(Icons.chevron_right),
            onTap: onTap);
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(16),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('เริ่มตั้งค่าร้าน ($done/$total)',
                  style: Theme.of(context).textTheme.titleMedium),
              const Text('ทำทีละขั้น แล้วลองใช้งานก่อนขายจริง'),
              step(
                  _restaurant ? 'เพิ่มเมนูแรก' : 'เพิ่มสินค้าแรก',
                  'ใส่ชื่อ ราคา และจำนวนคงเหลือ',
                  _products,
                  () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const ProductFormScreen()))),
              step('ตั้งค่ารับเงิน', 'เริ่มจากเงินสด หรือ QR PromptPay',
                  _payments, _paymentsStep),
              if (_restaurant)
                step(
                    'เพิ่มโต๊ะแรก',
                    'ตั้งชื่อและจำนวนที่นั่ง',
                    _tables,
                    () => Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => const TableFormScreen()))),
              step('ลองคิดเงินหนึ่งบิล', 'โหมดฝึก ไม่รับเงินจริง ไม่หักสต็อก',
                  _demo || _sales, _demoStep),
              if (!widget.alwaysShow)
                TextButton(
                    onPressed: () async {
                      final prefs = await SharedPreferences.getInstance();
                      await prefs.setBool('$_key-dismissed', true);
                      if (mounted) setState(() => _dismissed = true);
                    },
                    child: Text(done == total
                        ? 'เสร็จแล้ว ซ่อนรายการนี้'
                        : 'ทำภายหลัง · เปิดได้จากปุ่มคู่มือด้านบน')),
            ])));
  }
}

/// Deliberately local-only: a practice receipt cannot affect real accounts.
class DemoCheckoutScreen extends StatefulWidget {
  const DemoCheckoutScreen({super.key});
  @override
  State<DemoCheckoutScreen> createState() => _DemoCheckoutScreenState();
}

class _DemoCheckoutScreenState extends State<DemoCheckoutScreen> {
  int _quantity = 0;
  bool _paid = false;
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('ฝึกคิดเงิน')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const Text(
            'ข้อมูลตัวอย่างเท่านั้น ไม่มีการรับเงินจริงหรือเปลี่ยนสต็อก'),
        const SizedBox(height: 20),
        ListTile(
            title: const Text('น้ำดื่มตัวอย่าง'),
            subtitle: const Text('10 บาท / ชิ้น'),
            trailing: FilledButton(
                onPressed: _paid ? null : () => setState(() => _quantity++),
                child: const Text('เพิ่ม'))),
        Text('จำนวน $_quantity ชิ้น · รวม ${_quantity * 10} บาท'),
        const SizedBox(height: 20),
        if (!_paid)
          FilledButton(
              onPressed:
                  _quantity == 0 ? null : () => setState(() => _paid = true),
              child: const Text('จำลองรับเงินสดครบยอด')),
        if (_paid) ...[
          const Icon(Icons.check_circle, color: Colors.green, size: 48),
          const Text('ฝึกคิดเงินสำเร็จ · ไม่ใช่ใบเสร็จจริง'),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('กลับไปตั้งค่าร้าน')),
        ],
      ]));
}
