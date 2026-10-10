import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';

/// Retain the exact request across timeouts/restarts so retry cannot double debit.
class CashMovementService {
  static String get _key => 'pending-cash-movement-${AuthService.shopId}';

  static Future<Map<String, dynamic>?> pending() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    return saved == null ? null : Map<String, dynamic>.from(jsonDecode(saved));
  }

  static Future<void> record(String kind, double amount, String reason) async {
    final shopId = AuthService.shopId;
    final key = _key;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(key);
    Map<String, dynamic> request;
    if (saved != null) {
      request = Map<String, dynamic>.from(jsonDecode(saved));
      if (request['kind'] != kind ||
          request['amount'] != amount ||
          request['reason'] != reason.trim()) {
        throw StateError(
            'มีรายการรอยืนยัน กรุณาปิดหน้าต่างแล้วเปิดบันทึกเงินอีกครั้งเพื่อยืนยันรายการเดิม');
      }
    } else {
      final shop = FirebaseFirestore.instance.collection('shops').doc(shopId);
      final control = await shop
          .collection('cashControl')
          .doc('current')
          .get(const GetOptions(source: Source.server));
      final sessionId = control.data()?['sessionId'];
      if (sessionId == null) {
        throw StateError('เปิดรอบที่หน้าปิดยอดสิ้นวันก่อนบันทึกเงินเข้า–ออก');
      }
      request = {
        'shopId': shopId,
        'sessionId': sessionId,
        'requestId': shop.collection('moneyMovements').doc().id,
        'kind': kind,
        'amount': amount,
        'reason': reason.trim()
      };
      if (!await prefs.setString(key, jsonEncode(request))) {
        throw StateError('เก็บรายการไม่สำเร็จ กรุณาลองใหม่');
      }
    }
    try {
      await FirebaseFunctions.instanceFor(region: 'asia-southeast1')
          .httpsCallable('recordCashMovement')
          .call(request);
    } on FirebaseFunctionsException catch (e) {
      // A definite rejection made no writes. Ambiguous transport errors retain
      // the request for an idempotent retry, including after the round closes.
      if ([
        'invalid-argument',
        'permission-denied',
        'failed-precondition',
        'unauthenticated',
        'not-found'
      ].contains(e.code)) {
        await prefs.remove(key);
      }
      rethrow;
    }
    if (!await prefs.remove(key)) {
      throw StateError(
          'บันทึกแล้ว แต่ยังล้างคำขอในเครื่องไม่ได้ กรุณายืนยันรายการเดิมอีกครั้ง');
    }
  }
}
