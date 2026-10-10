import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/cash_session.dart';
import '../models/cash_close_check.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'auth_service.dart';
import 'offline_service.dart';
import 'package:flutter/foundation.dart';

/// End-of-day cash sessions (ปิดยอดสิ้นวัน). One open session at a time; the
/// Z-report summary is snapshotted on close so history never re-queries.
class CashSessionService {
  static Future<bool> accountingEnabled() async {
    final snap = await FirebaseFirestore.instance
        .collection('shops')
        .doc(AuthService.shopId)
        .collection('accountingSettings')
        .doc('current')
        .get(const GetOptions(source: Source.server));
    return snap.data()?['enabled'] == true;
  }

  static CollectionReference<Map<String, dynamic>> _col() =>
      FirebaseFirestore.instance
          .collection('shops')
          .doc(AuthService.shopId)
          .collection('cashSessions');

  /// The currently open session, or null. Stream so the dashboard/screen
  /// reflect open/closed live.
  static Stream<CashSession?> watchOpen() => _col()
      .where('status', isEqualTo: 'open')
      .limit(1)
      .snapshots()
      .map((s) => s.docs.isEmpty
          ? null
          : CashSession.fromFirestore(s.docs.first.data(), s.docs.first.id));

  static Stream<List<CashSession>> watchHistory({int limit = 30}) => _col()
      .orderBy('openedAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((s) => s.docs
          .map((d) => CashSession.fromFirestore(d.data(), d.id))
          .toList());

  static Future<void> open({
    required double openingFloat,
    String? openedBy,
    bool acknowledgeDeviceUpdate = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = 'pending-cash-open-${AuthService.shopId}';
    final id = prefs.getString(key) ?? _col().doc().id;
    if (!await prefs.setString(key, id)) {
      throw StateError('เก็บคำขอเปิดรอบไม่สำเร็จ กรุณาลองใหม่');
    }
    try {
      await FirebaseFunctions.instanceFor(region: 'asia-southeast1')
          .httpsCallable('openCashSession')
          .call({
        'shopId': AuthService.shopId,
        'requestId': id,
        'openingFloat': openingFloat,
        'acknowledgeDeviceUpdate': acknowledgeDeviceUpdate,
      });
    } on FirebaseFunctionsException catch (e) {
      if (e.details is Map && e.details['reason'] == 'closed-open-request') {
        await prefs.remove(key);
      }
      rethrow;
    }
    await prefs.remove(key);
  }

  /// Close against the server's immutable money movements and return its saved
  /// session. A repeated close returns the first count and summary unchanged.
  static Future<CashSession> close(
    CashSession session, {
    required double countedCash,
    String? closedBy,
    bool acknowledgeLegacy = false,
  }) async {
    await _checkLocalPending();
    await FirebaseFunctions.instanceFor(region: 'asia-southeast1')
        .httpsCallable('closeCashSession')
        .call({
      'shopId': AuthService.shopId,
      'sessionId': session.id,
      'countedCash': countedCash,
      'acknowledgeLegacy': acknowledgeLegacy,
    });
    return get(session.id);
  }

  /// Advisory only: closeCashSession repeats this check in its transaction.
  static Future<CashCloseCheck> checkClose(CashSession session) async {
    await _checkLocalPending();
    final result =
        await FirebaseFunctions.instanceFor(region: 'asia-southeast1')
            .httpsCallable('getCashCloseReadiness')
            .call({'shopId': AuthService.shopId, 'sessionId': session.id});
    return CashCloseCheck.fromMap(result.data as Map);
  }

  static Future<void> _checkLocalPending() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();
    if (prefs.getString('pending-cash-movement-${AuthService.shopId}') !=
        null) {
      throw StateError(
          'มีเงินเข้า–ออกรอยืนยัน ไปที่หน้าเงินเข้า–ออก แล้วกดบันทึกเพื่อยืนยันรายการเดิมก่อนปิดรอบ');
    }
    if (prefs.getKeys().any((key) =>
        key.startsWith('pending-checkout-${AuthService.shopId}') &&
        prefs.getString(key) != null)) {
      throw StateError(
          'มีบิลขายในเครื่องรอยืนยัน ไปที่หน้าขายแล้วกดตรวจและยืนยันรายการเดิมก่อนปิดรอบ');
    }
    if (!kIsWeb &&
        [TargetPlatform.android, TargetPlatform.iOS]
            .contains(defaultTargetPlatform) &&
        await OfflineService.pendingForShop(AuthService.shopId!) > 0) {
      throw StateError('ซิงก์บิลออฟไลน์ที่ค้างในเครื่องให้ครบก่อนปิดรอบ');
    }
  }

  static Future<CashSession> get(String id) async {
    final doc =
        await _col().doc(id).get(const GetOptions(source: Source.server));
    return CashSession.fromFirestore(doc.data()!, doc.id);
  }
}
