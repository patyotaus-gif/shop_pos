import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../widgets/compact_action.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/cart_item.dart';
import '../models/product.dart';
import '../models/modifier_group.dart';
import '../services/offline_service.dart';
import '../widgets/modifier_picker_sheet.dart';
import '../widgets/sale_product_grid.dart';
import '../utils/operation_error.dart';

class OfflineEntryButton extends StatelessWidget {
  const OfflineEntryButton({super.key, this.allowPrepare = false});
  final bool allowPrepare;
  @override
  Widget build(BuildContext context) => TextButton.icon(
      icon: const Icon(Icons.wifi_off),
      label: const Text('ขายออฟไลน์ / บิลค้าง'),
      onPressed: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => OfflineEntryScreen(allowPrepare: allowPrepare))));
}

class OfflineEntryScreen extends StatefulWidget {
  const OfflineEntryScreen({super.key, this.allowPrepare = false});
  final bool allowPrepare;
  @override
  State<OfflineEntryScreen> createState() => _OfflineEntryState();
}

class _OfflineEntryState extends State<OfflineEntryScreen> {
  late Future<List<Map<String, Object?>>> _profiles = OfflineService.profiles();
  bool _busy = false;
  String? _error;
  Future<String?> _pin(bool create) async {
    String pin = '', confirm = '';
    return showDialog<String>(
        context: context,
        builder: (ctx) => StatefulBuilder(
            builder: (ctx, update) => AlertDialog(
                    title: Text(
                        create ? 'ตั้ง PIN ออฟไลน์ 6–8 หลัก' : 'PIN ออฟไลน์'),
                    content: Column(mainAxisSize: MainAxisSize.min, children: [
                      const Text(
                          'PIN นี้เปิดได้เฉพาะหน้าขายเงินสด ไม่เปิดเมนูเจ้าของ'),
                      TextField(
                          obscureText: true,
                          keyboardType: TextInputType.number,
                          maxLength: 8,
                          onChanged: (v) => update(() => pin = v),
                          decoration:
                              const InputDecoration(labelText: 'PIN ออฟไลน์')),
                      if (create)
                        TextField(
                            obscureText: true,
                            keyboardType: TextInputType.number,
                            maxLength: 8,
                            onChanged: (v) => update(() => confirm = v),
                            decoration:
                                const InputDecoration(labelText: 'ยืนยัน PIN')),
                    ]),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('ยกเลิก')),
                      FilledButton(
                          onPressed: RegExp(r'^\d{6,8}$').hasMatch(pin) &&
                                  (!create || pin == confirm)
                              ? () => Navigator.pop(ctx, pin)
                              : null,
                          child: const Text('เข้าใช้งาน'))
                    ])));
  }

  Future<void> _open([Map<String, Object?>? profile]) async {
    final pin = await _pin(profile == null);
    if (pin == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final p = profile == null
          ? await OfflineService.prepare(pin)
          : await OfflineService.unlock(profile, pin);
      if (!mounted) return;
      await Navigator.push(context,
          MaterialPageRoute(builder: (_) => OfflineCashScreen(permit: p)));
      OfflineService.lock();
    } catch (e) {
      if (mounted) setState(() => _error = operationError(e));
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _profiles = OfflineService.profiles();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('ขายเงินสดออฟไลน์')),
      body: ListView(padding: const EdgeInsets.all(20), children: [
        const Text(
            'เตรียมข้อมูลขณะมีเน็ต ใช้ขายเงินสดได้ 12 ชั่วโมงตามราคาที่เตรียมไว้ บิลเก็บในเครื่องและส่งอัตโนมัติเมื่อเชื่อมต่อได้ ห้ามล้างข้อมูลหรือถอนแอปขณะมีบิลค้าง'),
        if (widget.allowPrepare)
          FilledButton.icon(
              onPressed: _busy ? null : () => _open(),
              icon: const Icon(Icons.download),
              label: const Text('เตรียมข้อมูลและตั้ง PIN (ใช้อินเทอร์เน็ต)')),
        if (_busy) const LinearProgressIndicator(),
        if (_error != null)
          Text(_error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error)),
        FutureBuilder<List<Map<String, Object?>>>(
            future: _profiles,
            builder: (context, snap) {
              if (snap.hasError) return Text(operationError(snap.error!));
              if (!snap.hasData) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.data!.isEmpty) {
                return const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                        'ยังไม่ได้เตรียมข้อมูล เข้าสู่ระบบแล้วเปิดเมนูขายออฟไลน์จากหน้าขายก่อน'));
              }
              return Column(
                  children: snap.data!.reversed.map((p) {
                final data = jsonDecode(p['data'] as String);
                return ListTile(
                    leading: const Icon(Icons.lock_outline),
                    title: Text(p['label'] as String),
                    subtitle: Text(
                        'ขายได้ถึง ${DateTime.parse(data['expiresAt']).toLocal()}'),
                    onTap: _busy ? null : () => _open(p));
              }).toList());
            }),
      ]));
}

class OfflineCashScreen extends StatefulWidget {
  const OfflineCashScreen({super.key, required this.permit});
  final Map<String, dynamic> permit;
  @override
  State<OfflineCashScreen> createState() => _OfflineCashState();
}

class _OfflineCashState extends State<OfflineCashScreen>
    with WidgetsBindingObserver {
  final List<CartItem> _cart = [];
  bool _busy = false;
  String _search = '';
  String? _error;
  List<Map<String, Object?>> _bills = [];
  late final _products = (widget.permit['products'] as List)
      .map((p) => Product.fromFirestore(
          Map<String, dynamic>.from(p), p['id'] as String))
      .toList();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    OfflineService.changes.addListener(_refresh);
    OfflineService.start();
    _refresh();
    unawaited(OfflineService.sync());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    OfflineService.changes.removeListener(_refresh);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
      unawaited(OfflineService.sync());
    }
  }

  Future<void> _refresh() async {
    final bills = await (await OfflineService.store)
        .receipts(permit: widget.permit['id']);
    if (mounted) setState(() => _bills = bills);
  }

  double get _total => OfflineService.cartTotal(_cart);
  Future<void> _add(Product p) async {
    final sold = _bills.fold<int>(
        0,
        (sum, row) =>
            sum +
            (jsonDecode(row['payload'] as String)['items'] as List)
                .where((i) => i['productId'] == p.id)
                .fold<int>(0, (n, i) => n + (i['quantity'] as int)));
    final inCart = _cart
        .where((i) => i.product.id == p.id)
        .fold<int>(0, (n, i) => n + i.quantity);
    if (_cart.length >= 50 || (!p.isRecipeMode && sold + inCart >= p.stock)) {
      setState(() => _error = 'สต็อกในเครื่องไม่พอ หรือครบ 50 รายการแล้ว');
      return;
    }
    ModifierPick? pick;
    if (p.modifierGroupIds.isNotEmpty) {
      final groups = (widget.permit['groups'] as List)
          .where((g) => p.modifierGroupIds.contains(g['id']))
          .map((g) => ModifierGroup.fromFirestore(
              Map<String, dynamic>.from(g), g['id'] as String))
          .toList();
      if (groups.length != p.modifierGroupIds.length) {
        setState(() => _error = 'ตัวเลือกสินค้าไม่ครบ กรุณาเตรียมข้อมูลใหม่');
        return;
      }
      pick =
          await showModifierPicker(context, product: p, offlineGroups: groups);
      if (pick == null || !mounted) return;
    }
    if (_busy) return;
    setState(() => _cart.add(CartItem(
        product: p,
        modifiers: pick?.modifiers ?? const [],
        notes: pick?.notes)));
  }

  Future<void> _pay() async {
    if (_busy) return;
    final total = _total;
    String amount = total.toStringAsFixed(2);
    final paid = await showDialog<double>(
        context: context,
        builder: (ctx) => AlertDialog(
                title: Text('เงินสด ฿${total.toStringAsFixed(2)}'),
                content: TextFormField(
                    initialValue: amount,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (v) => amount = v,
                    decoration: const InputDecoration(labelText: 'เงินที่รับ')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('ยกเลิก')),
                  FilledButton(
                      onPressed: () =>
                          Navigator.pop(ctx, double.tryParse(amount) ?? -1),
                      child: const Text('บันทึกบิลเงินสด'))
                ]));
    if (paid == null || !mounted) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final bill =
          await OfflineService.checkout(widget.permit, List.of(_cart), paid);
      if (!mounted) return;
      setState(() => _cart.clear());
      await _receipt(bill);
    } catch (e) {
      if (mounted) setState(() => _error = operationError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _print(Map<String, dynamic> bill) async {
    final regular = pw.Font.ttf(
        await rootBundle.load('assets/fonts/IBMPlexSansThai-Regular.ttf'));
    final doc = pw.Document(theme: pw.ThemeData.withFont(base: regular));
    doc.addPage(pw.Page(
        pageFormat: PdfPageFormat.roll80,
        build: (_) => pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(widget.permit['shopName'] as String),
                  pw.Text('ใบเสร็จเงินสด · บันทึกออฟไลน์'),
                  pw.Text('O-${bill['id']}',
                      style: const pw.TextStyle(fontSize: 8)),
                  pw.Text(bill['createdAt'] as String),
                  ...(bill['displayItems'] as List).map((i) => pw.Text(
                      '${i['name']} ${i['options']} x${i['quantity']}  ${i['subtotal']}')),
                  pw.Text('รวม ${bill['total']} บาท'),
                  pw.Text(
                      'รับ ${bill['paid']} ทอน ${((bill['paid'] as num) - (bill['total'] as num)).toStringAsFixed(2)}'),
                ])));
    await Printing.layoutPdf(onLayout: (_) => doc.save());
  }

  Future<void> _receipt(Map<String, dynamic> bill) => showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
              title: const Text('บันทึกบิลในเครื่องแล้ว'),
              content: SingleChildScrollView(
                  child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    SelectableText('O-${bill['id']}'),
                    Text(
                        'รวม ฿${bill['total']} · เงินทอน ฿${((bill['paid'] as num) - (bill['total'] as num)).toStringAsFixed(2)}'),
                    ...(bill['displayItems'] as List).map((i) => Text(
                        '${i['name']} ${i['options']} × ${i['quantity']}')),
                    const Text('ตรวจสถานะการส่งได้ที่ “บิลในเครื่อง”'),
                  ])),
              actions: [
                TextButton(
                    onPressed: () async {
                      try {
                        await _print(bill);
                      } catch (e) {
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(content: Text(operationError(e))));
                        }
                      }
                    },
                    child: const Text('พิมพ์')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('ขายบิลต่อไป'))
              ]));
  void _history() => showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => SizedBox(
          height: MediaQuery.sizeOf(context).height * .75,
          child: ListView(children: [
            const ListTile(title: Text('บิลในเครื่อง — แตะเพื่อดูหรือพิมพ์')),
            ..._bills.map((row) {
              final bill = Map<String, dynamic>.from(
                  jsonDecode(row['payload'] as String));
              return ListTile(
                  title: Text(
                      '฿${bill['total']} · ${row['status'] == 'synced' ? 'ส่งแล้ว' : row['status'] == 'review' ? 'ต้องตรวจสอบ' : 'รอส่ง'}'),
                  subtitle: Text('${bill['createdAt']}\n${row['message']}'),
                  onTap: () => _receipt(bill));
            }),
          ])));
  @override
  Widget build(BuildContext context) {
    final expired =
        DateTime.now().isAfter(DateTime.parse(widget.permit['expiresAt']));
    final products = _products
        .where((p) =>
            p.name.toLowerCase().contains(_search.toLowerCase()) ||
            p.barcode.contains(_search))
        .toList();
    return PopScope(
        canPop: !_busy && _cart.isEmpty,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop && !_busy) {
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('ล้างตะกร้าก่อนออกจากหน้าขาย')));
          }
        },
        child: Scaffold(
            appBar: AppBar(
                title: Text('เงินสดออฟไลน์ · ${widget.permit['name']}'),
                actions: [
                  IconButton(
                      onPressed: _busy ? null : _history,
                      icon: const Icon(Icons.receipt_long),
                      tooltip: 'บิลในเครื่อง'),
                  IconButton(
                      onPressed: () => OfflineService.sync(),
                      icon: const Icon(Icons.sync),
                      tooltip: 'ลองซิงก์')
                ]),
            body: Column(children: [
              Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(expired
                      ? 'สิทธิ์ขายหมดอายุแล้ว ยังดูและซิงก์บิลเก่าได้'
                      : 'ราคา ณ ตอนเตรียมข้อมูล · รอส่ง ${_bills.where((r) => r['status'] == 'pending').length} บิล · ต้องตรวจสอบ ${_bills.where((r) => r['status'] == 'review' || (r['message'] as String).isNotEmpty).length} บิล')),
              if (_error != null)
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: TextField(
                      onChanged: (v) => setState(() => _search = v),
                      decoration: const InputDecoration(
                          labelText: 'ค้นหาสินค้าหรือบาร์โค้ด',
                          prefixIcon: Icon(Icons.search)))),
              Expanded(
                  child: SaleProductGrid(
                      itemCount: products.length,
                      itemBuilder: (context, i) {
                        final p = products[i];
                        return SaleProductCard(
                            product: p,
                            showPromotion: false,
                            onTap: _busy || expired ? null : () => _add(p));
                      })),
              const Divider(),
              SizedBox(
                  height: 140,
                  child: ListView(
                      children: _cart
                          .asMap()
                          .entries
                          .map((e) => ListTile(
                              dense: true,
                              title: Text(
                                  '${e.value.product.name} × ${e.value.quantity}'),
                              subtitle: Text(
                                  '฿${OfflineService.lineTotal(e.value).toStringAsFixed(2)}'),
                              trailing: IconButton(
                                  icon: const Icon(Icons.remove_circle_outline),
                                  onPressed: _busy
                                      ? null
                                      : () => setState(
                                          () => _cart.removeAt(e.key)))))
                          .toList())),
              SafeArea(
                  top: false,
                  child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: ActionButtons(children: [
                        TextButton(
                            onPressed: _busy
                                ? null
                                : () => setState(() => _cart.clear()),
                            child: const Text('ล้างตะกร้า')),
                        FilledButton(
                            onPressed:
                                _busy || expired || _cart.isEmpty ? null : _pay,
                            child: Text(_busy
                                ? 'กำลังบันทึก…'
                                : 'รับเงินสด ฿${_total.toStringAsFixed(2)}'))
                      ]))),
            ])));
  }
}
