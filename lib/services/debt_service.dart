import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/debt.dart';

class DebtService {
  static final _col = FirebaseFirestore.instance.collection('debts');

  static Stream<List<Debt>> watchUnpaid() => _col
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs
          .map((d) => Debt.fromFirestore(d.data(), d.id))
          .where((d) => !d.isPaid)
          .toList());

  static Stream<List<Debt>> watchAll() => _col
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map((d) => Debt.fromFirestore(d.data(), d.id)).toList());

  static Future<void> recordPayment(String debtId, double amount) =>
      _col.doc(debtId).update({'paidAmount': FieldValue.increment(amount)});

  static Future<void> delete(String id) => _col.doc(id).delete();
}
