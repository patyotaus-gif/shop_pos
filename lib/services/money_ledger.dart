import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/sale.dart';

/// The control document serializes money writes against closing a cash drawer.
class MoneyLedger {
  static Future<Map<String, dynamic>> read(
      Transaction tx, DocumentReference<Map<String, dynamic>> shop) async {
    final snap = await tx.get(shop.collection('cashControl').doc('current'));
    return snap.data() ?? <String, dynamic>{};
  }

  static void recordSale(
      Transaction tx,
      DocumentReference<Map<String, dynamic>> shop,
      Map<String, dynamic> control,
      String saleId,
      Sale sale) {
    final openedAt = (control['openedAt'] as Timestamp?)?.toDate();
    final late = openedAt != null && sale.createdAt.isBefore(openedAt);
    tx.set(shop.collection('moneyMovements').doc('sale-$saleId'), {
      'kind': 'sale',
      'saleId': saleId,
      'amountMinor': sale.isDebt ? 0 : (sale.total * 100).round(),
      'salesMinor': (sale.total * 100).round(),
      'debtMinor': sale.isDebt ? (sale.total * 100).round() : 0,
      'method': sale.isDebt ? 'credit' : sale.paymentMethod.name,
      'occurredAt': Timestamp.fromDate(sale.createdAt),
      'recordedAt': FieldValue.serverTimestamp(),
      'sessionId': late ? null : control['sessionId'],
      'needsReconciliation': late || control['sessionId'] == null,
      'schemaVersion': 1,
      'actor': shop.id,
    });
    tx.set(
        shop.collection('cashControl').doc('current'),
        {
          'revision': FieldValue.increment(1),
        },
        SetOptions(merge: true));
  }
}
