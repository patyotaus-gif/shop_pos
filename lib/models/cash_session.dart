import 'package:cloud_firestore/cloud_firestore.dart';

import 'sale.dart';

/// End-of-day cash session (ปิดยอดสิ้นวัน). A pure reporting wrapper — sales
/// are never gated by a session; closing just snapshots the period and
/// reconciles the drawer.
class CashSession {
  final String id;
  final DateTime openedAt;
  final String? openedBy;
  final double openingFloat;
  final bool closed;
  final DateTime? closedAt;
  final String? closedBy;
  final double? countedCash;
  final SessionSummary? summary; // snapshot written at close
  final int accountingVersion;
  final bool needsReconciliation;

  const CashSession({
    required this.id,
    required this.openedAt,
    this.openedBy,
    this.openingFloat = 0,
    this.closed = false,
    this.closedAt,
    this.closedBy,
    this.countedCash,
    this.summary,
    this.accountingVersion = 0,
    this.needsReconciliation = false,
  });

  factory CashSession.fromFirestore(Map<String, dynamic> d, String id) =>
      CashSession(
        id: id,
        openedAt: (d['openedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        openedBy: d['openedBy'] as String?,
        openingFloat: (d['openingFloat'] ?? 0).toDouble(),
        closed: d['status'] == 'closed',
        closedAt: (d['closedAt'] as Timestamp?)?.toDate(),
        closedBy: d['closedBy'] as String?,
        countedCash: (d['countedCash'] as num?)?.toDouble(),
        accountingVersion: (d['accountingVersion'] as num? ?? 0).toInt(),
        needsReconciliation: d['needsReconciliation'] == true,
        summary: d['summary'] is Map
            ? SessionSummary.fromMap(Map<String, dynamic>.from(d['summary']))
            : null,
      );
}

/// Aggregated numbers for a session — computed by [summarizeSession] and
/// snapshotted on the session at close so the Z-report never re-queries.
class SessionSummary {
  final int billCount;
  final double grossTotal;
  final Map<String, double> byMethod; // paymentMethod name → total (non-debt)
  final double debtTotal;
  final double refundTotal;
  final double cashSales;
  final double expectedCash; // openingFloat + cashSales − cashRefunds
  final double openingFloat;
  final double debtCollections;
  final int pendingOrderCount;
  final int openTableCount;
  final int futureOrderCount;

  const SessionSummary({
    required this.billCount,
    required this.grossTotal,
    required this.byMethod,
    required this.debtTotal,
    required this.refundTotal,
    required this.cashSales,
    required this.expectedCash,
    required this.openingFloat,
    this.debtCollections = 0,
    this.pendingOrderCount = 0,
    this.openTableCount = 0,
    this.futureOrderCount = 0,
  });

  double overShort(double countedCash) => countedCash - expectedCash;

  Map<String, dynamic> toMap() => {
        'billCount': billCount,
        'grossTotal': grossTotal,
        'byMethod': byMethod,
        'debtTotal': debtTotal,
        'refundTotal': refundTotal,
        'cashSales': cashSales,
        'expectedCash': expectedCash,
        'openingFloat': openingFloat,
        'debtCollections': debtCollections,
        'pendingOrderCount': pendingOrderCount,
        'openTableCount': openTableCount,
        'futureOrderCount': futureOrderCount,
      };

  factory SessionSummary.fromMap(Map<String, dynamic> m) => SessionSummary(
        billCount: (m['billCount'] ?? 0) as int,
        grossTotal: (m['grossTotal'] ?? 0).toDouble(),
        byMethod: {
          for (final e in ((m['byMethod'] as Map?) ?? const {}).entries)
            e.key as String: (e.value as num).toDouble()
        },
        debtTotal: (m['debtTotal'] ?? 0).toDouble(),
        refundTotal: (m['refundTotal'] ?? 0).toDouble(),
        cashSales: (m['cashSales'] ?? 0).toDouble(),
        expectedCash: (m['expectedCash'] ?? 0).toDouble(),
        openingFloat: (m['openingFloat'] ?? 0).toDouble(),
        debtCollections: (m['debtCollections'] ?? 0).toDouble(),
        pendingOrderCount: (m['pendingOrderCount'] as num? ?? 0).toInt(),
        openTableCount: (m['openTableCount'] as num? ?? 0).toInt(),
        futureOrderCount: (m['futureOrderCount'] as num? ?? 0).toInt(),
      );
}

/// Legacy same-window preview only. Live closing uses dated money movements
/// on the server, including collections and refunds of older sales.
SessionSummary summarizeSession(List<Sale> sales, double openingFloat) {
  final byMethod = <String, double>{};
  double gross = 0, debt = 0, refund = 0, cashSales = 0;

  for (final s in sales) {
    if (s.isRefunded) {
      refund += s.total;
      continue;
    }
    gross += s.total;
    if (s.isDebt) {
      debt += s.total;
      continue;
    }
    final key = s.paymentMethod.name;
    byMethod[key] = (byMethod[key] ?? 0) + s.total;
    if (s.paymentMethod == PaymentMethod.cash) cashSales += s.total;
  }

  return SessionSummary(
    billCount: sales.length,
    grossTotal: gross,
    byMethod: byMethod,
    debtTotal: debt,
    refundTotal: refund,
    cashSales: cashSales,
    expectedCash: openingFloat + cashSales,
    openingFloat: openingFloat,
  );
}
