import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../services/shop_database.dart';

class ConnectionStatusBanner extends StatefulWidget {
  const ConnectionStatusBanner({super.key});
  @override
  State<ConnectionStatusBanner> createState() => _ConnectionStatusBannerState();
}

class _ConnectionStatusBannerState extends State<ConnectionStatusBanner>
    with WidgetsBindingObserver {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _subscription;
  Timer? _timer;
  bool _probing = false;
  bool _pending = false;
  String? _message = 'กำลังตรวจการเชื่อมต่อ';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final shop = ShopDatabase.shop;
    _subscription = shop.snapshots(includeMetadataChanges: true).listen((snap) {
      if (!mounted) return;
      setState(() {
        _pending = snap.metadata.hasPendingWrites;
        _message = _pending
            ? 'กำลังรอยืนยันการบันทึก'
            : snap.metadata.isFromCache
                ? 'แสดงข้อมูลในเครื่อง · กำลังรอเชื่อมต่อ'
                : null;
      });
    }, onError: (Object _) {
      if (mounted) {
        setState(() => _message = 'ตรวจสอบการเชื่อมต่อหรือบัญชีที่เข้าสู่ระบบ');
      }
    });
    _probe();
    _timer = Timer.periodic(const Duration(seconds: 30), (_) => _probe());
  }

  Future<void> _probe() async {
    if (_probing ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.paused) {
      return;
    }
    _probing = true;
    try {
      await ShopDatabase.shop
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 10));
      if (mounted) {
        setState(() => _message = _pending ? 'กำลังรอยืนยันการบันทึก' : null);
      }
    } catch (error) {
      if (mounted) {
        setState(() => _message = error is FirebaseException &&
                ['permission-denied', 'unauthenticated'].contains(error.code)
            ? 'กรุณาตรวจสอบบัญชีและสิทธิ์เข้าถึงร้าน'
            : 'ติดต่อระบบไม่ได้ · ตรวจอินเทอร์เน็ตก่อนยืนยันบิล');
      }
    } finally {
      _probing = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _probe();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _message == null
      ? const SizedBox.shrink()
      : Material(
          color: Theme.of(context).colorScheme.secondaryContainer,
          child: SafeArea(
              top: false,
              child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  child: Row(children: [
                    const Icon(Icons.cloud_sync_outlined, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(_message!,
                            style: const TextStyle(fontSize: 12))),
                    IconButton(
                        tooltip: 'ตรวจการเชื่อมต่ออีกครั้ง',
                        onPressed: _probe,
                        icon: const Icon(Icons.refresh, size: 20))
                  ]))));
}
