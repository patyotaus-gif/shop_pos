import 'package:cloud_functions/cloud_functions.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/debt.dart';
import 'auth_service.dart';

class DebtService {
  static CollectionReference<Map<String, dynamic>> _col() =>
      FirebaseFirestore.instance
          .collection('shops')
          .doc(AuthService.shopId)
          .collection('debts');

  static Stream<List<Debt>> watchUnpaid() => _col()
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs
          .map((d) => Debt.fromFirestore(d.data(), d.id))
          .where((d) => !d.isPaid)
          .toList());

  static Stream<List<Debt>> watchAll() =>
      _col().orderBy('createdAt', descending: true).snapshots().map((s) =>
          s.docs.map((d) => Debt.fromFirestore(d.data(), d.id)).toList());

  static Future<void> recordPayment(String debtId, double amount,
      {required String requestId,
      required String method,
      required double expectedPaidAmount}) async {
    await FirebaseFunctions.instanceFor(region: 'asia-southeast1')
        .httpsCallable('collectDebtPayment')
        .call({
      'shopId': AuthService.shopId,
      'debtId': debtId,
      'amount': amount,
      'requestId': requestId,
      'method': method,
      'expectedPaidAmount': expectedPaidAmount,
    });
  }
}
