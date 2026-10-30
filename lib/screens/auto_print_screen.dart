import '../widgets/content_width.dart';
import '../widgets/compact_action.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/auto_print_service.dart';
import '../services/bluetooth_printer_service.dart';
import 'bluetooth_printer_screen.dart';

class AutoPrintScreen extends StatefulWidget {
  const AutoPrintScreen({super.key});
  @override
  State<AutoPrintScreen> createState() => _AutoPrintScreenState();
}

class _AutoPrintScreenState extends State<AutoPrintScreen> {
  bool _busy = false, _kitchen = true, _receipts = true, _running = false;
  String? _error, _printer;
  String _status = 'ยังไม่ได้เปิดเครื่องหลักบนอุปกรณ์นี้';
  Timer? _timer;
  late final String _shopId = AuthService.shopId!;
  late final _configuration = FirebaseFirestore.instance
      .collection('shops')
      .doc(_shopId)
      .collection('autoPrintConfig')
      .doc('current')
      .snapshots();
  late final _jobs = AutoPrintService.jobs(_shopId)
      .orderBy('createdAtMs', descending: true)
      .limit(50)
      .snapshots();

  @override
  void initState() {
    super.initState();
    unawaited(_refresh());
    _timer = Timer.periodic(
        const Duration(seconds: 3), (_) => unawaited(_refresh()));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final state = await AutoPrintService.localState();
      final printer = await BluetoothPrinterService.saved();
      if (mounted) {
        setState(() {
          _running = state['running'] == true;
          _status = _running
              ? state['status'] as String? ?? 'กำลังเริ่ม'
              : 'หยุดพิมพ์บนอุปกรณ์นี้';
          _printer = _running ? state['printerName'] as String? : printer?.name;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = AutoPrintService.errorMessage(e));
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      await _refresh();
    } catch (e) {
      if (mounted) setState(() => _error = AutoPrintService.errorMessage(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _review(String id, String action) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('ตรวจใบที่เครื่องพิมพ์ก่อน'),
              content: Text(action == 'retry'
                  ? 'ตรวจว่าใบเดิมไม่ออกหรือออกไม่ครบแล้วใช่ไหม? ใบใหม่จะระบุว่าสำเนา / พิมพ์ซ้ำ เพื่อป้องกันทำอาหารซ้ำ'
                  : action == 'received'
                      ? 'ได้รับกระดาษครบแล้วใช่ไหม? ระบบจะปลดงานนี้และทำคิวถัดไป'
                      : 'ข้ามงานนี้โดยไม่ส่งพิมพ์ แล้วทำคิวถัดไป?'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('ยกเลิก')),
                FilledButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('ยืนยัน'))
              ],
            ));
    if (confirmed == true && mounted) {
      await _run(() async {
        await AutoPrintService.call(
            'reviewAutoPrint', _shopId, {'jobId': id, 'action': action});
      });
    }
  }

  Widget _job(String id, Map<String, dynamic> data) {
    final state = data['status'] as String? ?? 'pending';
    final label = switch (state) {
      'pending' => 'รอพิมพ์',
      'sending' => 'กำลังส่ง / รอตรวจผล',
      'sent' => 'ส่งข้อมูลแล้ว',
      'confirmed' => 'ยืนยันกระดาษครบแล้ว',
      'needsReview' => 'ต้องตรวจสอบ',
      'skipped' => 'ข้ามแล้ว',
      _ => state,
    };
    return Card(
        child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    '${data['kind'] == 'receipt' ? 'ใบเสร็จ' : 'ใบงานครัว'} • $label',
                    style: Theme.of(context).textTheme.titleSmall),
                Text('${data['title'] ?? ''} ${data['sourceId'] ?? ''}'.trim()),
                if ((data['reason'] ?? '').toString().isNotEmpty)
                  Text(data['reason'] as String),
                if (['sending', 'needsReview', 'sent'].contains(state))
                  Wrap(spacing: 8, children: [
                    TextButton(
                        onPressed: _busy ? null : () => _review(id, 'received'),
                        child: const Text('กระดาษครบแล้ว')),
                    TextButton(
                        onPressed: _busy ? null : () => _review(id, 'retry'),
                        child: const Text('พิมพ์ซ้ำ')),
                    TextButton(
                        onPressed: _busy ? null : () => _review(id, 'skip'),
                        child: const Text('ข้ามงาน')),
                  ]),
              ],
            )));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('พิมพ์อัตโนมัติ')),
        body: ContentWidth(
            maxWidth: 840,
            child: SafeArea(
                child: ListView(padding: const EdgeInsets.all(16), children: [
              const Text(
                  'ใช้เครื่องหลักหนึ่งเครื่องต่อร้าน รับงานจากหน้าร้านและออนไลน์ '
                  'เริ่มเก็บงานใหม่หลังเปิดโหมดนี้ งานที่รับไว้แล้วจะยังอยู่ในคิวเมื่อหยุดหรือเน็ตหลุด'),
              const SizedBox(height: 12),
              StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: _configuration,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const Text(
                          'โหลดสถานะเครื่องหลักไม่ได้ ตรวจอินเทอร์เน็ตแล้วลองใหม่');
                    }
                    final c = snapshot.data?.data();
                    return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c?['enabled'] == true
                              ? 'เครื่องหลักของร้าน: ${c?['deviceName'] ?? ''}'
                              : 'ร้านยังไม่ได้เปิดพิมพ์อัตโนมัติ'),
                          if (c?['enabled'] == true &&
                              DateTime.now().millisecondsSinceEpoch -
                                      ((c?['heartbeatAtMs'] as num?)?.toInt() ??
                                          0) >
                                  120000)
                            const Text(
                                'เครื่องหลักขาดการติดต่อ เปิดโหมดใหม่บนเครื่องหลักเพื่อรับคิวต่อ'),
                          if (c?['activeJob'] is String)
                            StreamBuilder<
                                DocumentSnapshot<Map<String, dynamic>>>(
                              stream: AutoPrintService.jobs(_shopId)
                                  .doc(c!['activeJob'] as String)
                                  .snapshots(),
                              builder: (context, job) =>
                                  job.data?.data() == null
                                      ? const SizedBox.shrink()
                                      : _job(job.data!.id, job.data!.data()!),
                            ),
                          if (c?['enabled'] == true)
                            TextButton(
                                onPressed: _busy
                                    ? null
                                    : () => _run(AutoPrintService.stopShop),
                                child: const Text('ปิดพิมพ์อัตโนมัติของร้าน')),
                        ]);
                  }),
              const Divider(),
              if (BluetoothPrinterService.supported) ...[
                Text(_status),
                Text('เครื่องพิมพ์: ${_printer ?? 'ยังไม่ได้เลือก'}'),
                CompactAction(
                    child: OutlinedButton.icon(
                        onPressed: _busy || _running
                            ? null
                            : () async {
                                await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                        builder: (_) =>
                                            const BluetoothPrinterScreen()));
                                await _refresh();
                              },
                        icon: const Icon(Icons.bluetooth),
                        label: const Text('เลือกเครื่อง / พิมพ์ทดสอบ'))),
                SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('ใบงานครัว'),
                    subtitle: const Text(
                        'โต๊ะเมื่อส่งครัว • ออนไลน์เมื่อยืนยันรับงานหรือรับเงิน • ซื้อกลับหน้าเคาน์เตอร์หลังรับเงิน'),
                    value: _kitchen,
                    onChanged: _busy || _running
                        ? null
                        : (v) => setState(() => _kitchen = v)),
                SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('ใบเสร็จเมื่อรับเงินแล้ว'),
                    subtitle: const Text(
                        'ทุกช่องทาง ไม่พิมพ์ใบเสร็จรับเงินสำหรับบิลเครดิต'),
                    value: _receipts,
                    onChanged: _busy || _running
                        ? null
                        : (v) => setState(() => _receipts = v)),
                CompactAction(
                    child: FilledButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _run(_running
                                ? AutoPrintService.stopLocal
                                : () => AutoPrintService.start(
                                    kitchen: _kitchen, receipts: _receipts)),
                        icon: Icon(_running ? Icons.pause : Icons.print),
                        label: Text(_running
                            ? 'พักเครื่องนี้ (เก็บงานเข้าคิวต่อ)'
                            : 'เปิดเครื่องนี้เป็นเครื่องหลัก'))),
                const Text(
                    'ขณะเปิดโหมดนี้มีการแจ้งเตือนสถานะและใช้แบตเตอรี่เพิ่ม '
                    'หลังรีสตาร์ทมือถือหรือบังคับปิดแอพ ให้เปิดโหมดใหม่ หากเปลี่ยนเครื่องหลักให้หยุดเครื่องเดิมก่อน'),
              ] else
                const Text(
                    'ดูคิวและตรวจงานได้จากเครื่องนี้ ใช้ Android ที่จับคู่เครื่องพิมพ์แล้วเป็นเครื่องหลัก'),
              if (_busy) const LinearProgressIndicator(),
              if (_error != null)
                Text(_error!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 20),
              Text('งานล่าสุด 50 รายการ',
                  style: Theme.of(context).textTheme.titleMedium),
              const Text('“ส่งข้อมูลแล้ว” ยังไม่ใช่การยืนยันว่ากระดาษออกครบ '
                  'หากงานค้างกำลังส่ง ให้รอ 5 นาทีก่อนตรวจผลหรือสั่งพิมพ์ซ้ำ'),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: _jobs,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const Text('โหลดคิวไม่ได้ กรุณาลองใหม่');
                    }
                    if (!snapshot.hasData) {
                      return const LinearProgressIndicator();
                    }
                    if (snapshot.data!.docs.isEmpty) {
                      return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('ยังไม่มีงานพิมพ์อัตโนมัติ'));
                    }
                    return Column(children: [
                      for (final doc in snapshot.data!.docs)
                        _job(doc.id, doc.data())
                    ]);
                  }),
            ]))),
      );
}
