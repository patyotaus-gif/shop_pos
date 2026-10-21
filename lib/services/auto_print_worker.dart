import 'dart:async';
import 'dart:typed_data';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/sale.dart';
import '../utils/receipt_generator.dart';
import 'auto_print_service.dart';
import 'auto_print_queue.dart';
import 'bluetooth_printer_service.dart';
import 'kitchen_print_service.dart';

/// Runs in the Android foreground service's own Flutter engine. No routes,
/// dialogs, or Activity are used. The server spool survives process death.
class AutoPrintWorker {
  AutoPrintWorker(this.config);
  final Map<String, dynamic> config;
  String get shopId => config['shopId'] as String;
  Map<String, dynamic> get identity => {
        'deviceId': config['deviceId'],
        'session': config['session'],
      };
  bool _stopped = false, _heartbeating = false;
  bool _hasPending = false, _retryPump = false;
  Timer? _timer;
  StreamSubscription? _auth, _jobs;
  late final _queue = AutoPrintQueue(
      call: (name, data) => _call(name, data),
      send: _send,
      active: () => !_stopped && AutoPrintService.matchesUser(shopId),
      status: _status,
      errorMessage: AutoPrintService.errorMessage);

  Future<Map<String, dynamic>> _call(String method,
          [Map<String, dynamic> data = const {}]) =>
      AutoPrintService.call(method, shopId, {...identity, ...data});

  Future<void> _status(String text) =>
      AutoPrintService.channel.invokeMethod<void>('status', {'text': text});

  Future<void> start() async {
    if (!AutoPrintService.matchesUser(shopId)) {
      await stop();
      return;
    }
    _auth = FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user?.uid != shopId) unawaited(stop());
    });
    _jobs = AutoPrintService.jobs(shopId)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .snapshots()
        .listen((snapshot) {
      _hasPending = snapshot.docs.isNotEmpty;
      if (_hasPending) unawaited(pump());
    }, onError: (_) {
      unawaited(_status('ติดต่อคิวพิมพ์ไม่ได้ กำลังรอเชื่อมต่อ'));
    });
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      unawaited(heartbeat());
      if (_hasPending || _retryPump || _queue.hasPendingResult) {
        unawaited(pump());
      }
    });
    await heartbeat();
    await pump();
  }

  Future<void> heartbeat() async {
    if (_stopped || _heartbeating) return;
    _heartbeating = true;
    try {
      await _call('heartbeatAutoPrint');
    } catch (e) {
      if (AutoPrintService.sessionLost(e)) {
        await stop();
      } else {
        await _status('รออินเทอร์เน็ต • คิวพิมพ์ยังถูกเก็บไว้');
      }
    } finally {
      _heartbeating = false;
    }
  }

  Future<void> pump() async {
    if (_stopped) return;
    try {
      await _queue.pump();
      _retryPump = false;
    } catch (e) {
      _retryPump = true;
      if (AutoPrintService.sessionLost(e)) {
        await stop();
      } else {
        await _status('รอเชื่อมต่อคิว • ไม่มีการพิมพ์ซ้ำอัตโนมัติ');
      }
    }
  }

  Future<void> _send(Map<String, dynamic> job) async {
    await _status(
        job['kind'] == 'receipt' ? 'กำลังส่งใบเสร็จ' : 'กำลังส่งใบงานครัว');
    final printer = BluetoothPrinterConfig(
        address: config['address'] as String,
        name: config['name'] as String,
        paperMm: config['paperMm'] as int);
    final pdf = await _document(job, printer.paperMm)
        .timeout(const Duration(seconds: 45));
    if (_stopped || !AutoPrintService.matchesUser(shopId)) {
      throw StateError('หยุดเครื่องหลักแล้ว');
    }
    await BluetoothPrinterService.printPdf(pdf, printer, beforeSend: () async {
      if (_stopped || !AutoPrintService.matchesUser(shopId)) {
        throw StateError('หยุดเครื่องหลักแล้ว');
      }
      await _call('heartbeatAutoPrint',
          {'jobId': job['jobId'], 'attempt': job['attempt']});
    });
  }

  Future<Uint8List> _document(Map<String, dynamic> job, int paperMm) async {
    if (job['kind'] == 'kitchen') {
      return KitchenPrintService.buildTicket(job, paperMm: paperMm);
    }
    final snap = await FirebaseFirestore.instance
        .collection('shops')
        .doc(shopId)
        .collection('sales')
        .doc(job['sourceId'] as String)
        .get(const GetOptions(source: Source.server));
    final data = snap.data();
    if (data == null || data['isDebt'] == true || data['isRefunded'] == true) {
      throw StateError('บิลเปลี่ยนแปลง กรุณาตรวจสอบก่อนพิมพ์');
    }
    return ReceiptGenerator.buildReceipt(Sale.fromFirestore(data, snap.id),
        format:
            paperMm == 80 ? ReceiptGenerator.slip80 : ReceiptGenerator.slip58,
        isCopy: job['reprint'] == true);
  }

  Future<void> stop() async {
    if (_stopped) return;
    _stopped = true;
    _timer?.cancel();
    await _auth?.cancel();
    await _jobs?.cancel();
    await AutoPrintService.channel.invokeMethod<void>('stop');
  }
}
