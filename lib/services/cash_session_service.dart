import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/cash_session.dart';
import '../models/sale.dart';
import 'auth_service.dart';

/// End-of-day cash sessions (ปิดยอดสิ้นวัน). One open session at a time; the
/// Z-report summary is snapshotted on close so history never re-queries.
class CashSessionService {
  static CollectionReference<Map<String, dynamic>> _col() =>
      FirebaseFirestore.instance
          .collection('shops')
          .doc(AuthService.shopId)
          .collection('cashSessions');

  static CollectionReference<Map<String, dynamic>> _sales() =>
      FirebaseFirestore.instance
          .collection('shops')
          .doc(AuthService.shopId)
          .collection('sales');

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
  }) async {
    await _col().add({
      'openedAt': FieldValue.serverTimestamp(),
      if (openedBy != null) 'openedBy': openedBy,
      'openingFloat': openingFloat,
      'status': 'open',
    });
  }

  /// Close [session]: pull its sales window, compute the summary, reconcile
  /// against [countedCash], and snapshot. Returns the summary for the
  /// Z-report.
  static Future<SessionSummary> close(
    CashSession session, {
    required double countedCash,
    String? closedBy,
  }) async {
    final now = DateTime.now();
    final snap = await _sales()
        .where('createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(session.openedAt))
        .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(now))
        .get();
    final sales =
        snap.docs.map((d) => Sale.fromFirestore(d.data(), d.id)).toList();
    final summary = summarizeSession(sales, session.openingFloat);

    await _col().doc(session.id).update({
      'status': 'closed',
      'closedAt': Timestamp.fromDate(now),
      if (closedBy != null) 'closedBy': closedBy,
      'countedCash': countedCash,
      'summary': summary.toMap(),
    });
    return summary;
  }
}
