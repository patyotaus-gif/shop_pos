import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import '../services/auth_service.dart';

/// Isolated test order: never returns PaymentResult or calls sale settlement.
class OmiseTestOrderScreen extends StatefulWidget {
  const OmiseTestOrderScreen({super.key});
  @override
  State<OmiseTestOrderScreen> createState() => _OmiseTestOrderScreenState();
}

class _OmiseTestOrderScreenState extends State<OmiseTestOrderScreen>
    with WidgetsBindingObserver {
  Timer? _timer;
  String? _id;
  String _message = 'กำลังเตรียมออเดอร์ทดสอบ…';
  String _status = 'awaiting_payment';
  bool _checking = false;
  bool _opening = false;
  late final String _uid = AuthService.currentUser!.uid;
  String get _key => 'omise-test-order:$_uid';
  bool get _terminal =>
      ['confirmed', 'cancelled', 'payment_failed'].contains(_status);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_terminal &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        _refresh();
      }
    });
  }

  Future<void> _load({bool newOrder = false}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final id = newOrder
          ? const Uuid().v4()
          : prefs.getString(_key) ?? const Uuid().v4();
      await prefs.setString(_key, id);
      if (!mounted) return;
      setState(() {
        _id = id;
        _status = 'awaiting_payment';
        _message = 'รอลูกค้าเริ่มชำระเงินทดสอบ';
      });
      await _refresh();
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'เตรียมรายการไม่ได้ กรุณาเปิดหน้านี้ใหม่');
      }
    }
  }

  Future<void> _refresh() async {
    if (_id == null ||
        _checking ||
        !mounted ||
        AuthService.currentUser?.uid != _uid) {
      return;
    }
    _checking = true;
    final id = _id;
    try {
      final result =
          await FirebaseFunctions.instanceFor(region: 'asia-southeast1')
              .httpsCallable('omiseSandboxStatus')
              .call({'attemptId': id});
      final data = Map<String, dynamic>.from(result.data as Map);
      if (data['testMode'] != true ||
          data['amount'] != 10000 ||
          data['attemptId'] != id) {
        throw StateError('Invalid test order');
      }
      if (!mounted || id != _id) return;
      setState(() {
        _status = data['orderStatus'] as String? ?? 'awaiting_payment';
        _message = switch (_status) {
          'confirmed' => 'ยืนยันออเดอร์ทดสอบอัตโนมัติแล้ว',
          'cancelled' => 'ออเดอร์ทดสอบถูกยกเลิก / คืนเงิน',
          'payment_failed' => 'ชำระไม่สำเร็จ ออเดอร์ยังไม่ยืนยัน',
          _ => 'รอผลชำระจาก Omise — ระบบตรวจให้อัตโนมัติ',
        };
      });
    } on FirebaseFunctionsException catch (e) {
      if (mounted && id == _id) {
        setState(() => _message = e.code == 'not-found'
            ? 'รอลูกค้าเริ่มชำระเงินทดสอบ'
            : 'ยังตรวจผลไม่ได้ ระบบจะตรวจซ้ำ กรุณาอย่าจ่ายซ้ำ');
      }
    } catch (_) {
      if (mounted) setState(() => _message = 'ยังยืนยันผลไม่ได้ ระบบจะตรวจซ้ำ');
    } finally {
      _checking = false;
    }
  }

  Future<void> _open() async {
    if (_id == null || _opening) return;
    setState(() => _opening = true);
    try {
      final ok = await launchUrl(
          Uri.https('pok-pok.app', '/payment-test/', {'newAttempt': _id!}),
          mode: LaunchMode.inAppBrowserView);
      if (!ok) throw StateError('Launch failed');
    } catch (_) {
      if (mounted) {
        setState(() => _message = 'เปิดหน้าลูกค้าชำระเงินไม่ได้ กรุณาลองใหม่');
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('ออเดอร์ทดสอบ Omise')),
        body: Center(
            child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: ListView(padding: const EdgeInsets.all(24), children: [
                  const Text('TEST MODE · เงินจำลอง',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 16),
                  const Text('สินค้าทดสอบ × 1\nรวม 100.00 บาท'),
                  const SizedBox(height: 16),
                  Text(_message,
                      style: Theme.of(context).textTheme.titleMedium),
                  if (_id != null) SelectableText('TEST-$_id'),
                  const SizedBox(height: 24),
                  const Text(
                      'พร้อมเพย์ / บัตร / TrueMoney\nหน้าลูกค้าทดสอบต้องเข้าสู่ระบบผู้ดูแล Pokpok\n\n'
                      'พร้อมเพย์ Test Mode ให้จำลอง Successful หรือ Failed ใน Omise Dashboard ไม่ต้องโอนเงินจริง '
                      'จากนั้นกลับหน้านี้เพื่อดูผลยืนยันอัตโนมัติ\n\n'
                      'ออเดอร์ทดสอบแยกจากบิลจริง ไม่บันทึกยอดขายหรือตัดสต๊อก'),
                  const SizedBox(height: 16),
                  if (!_terminal)
                    OutlinedButton(
                        onPressed: _id == null || _opening ? null : _open,
                        child: const Text('เปิดหน้าลูกค้าชำระเงินทดสอบ')),
                  if (_terminal)
                    OutlinedButton(
                        onPressed: () => _load(newOrder: true),
                        child: const Text('สร้างออเดอร์ทดสอบใหม่')),
                ]))),
      );
}
