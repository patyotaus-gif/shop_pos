import 'package:cloud_firestore/cloud_firestore.dart';

class Debt {
  final String id;
  final String customerName;
  final double amount;
  final double paidAmount;
  final DateTime createdAt;
  final String saleId;
  final String note;

  const Debt({
    required this.id,
    required this.customerName,
    required this.amount,
    this.paidAmount = 0,
    required this.createdAt,
    required this.saleId,
    this.note = '',
  });

  double get remaining => amount - paidAmount;
  bool get isPaid => remaining <= 0;

  factory Debt.fromFirestore(Map<String, dynamic> data, String id) => Debt(
        id: id,
        customerName: data['customerName'] ?? '',
        amount: (data['amount'] ?? 0).toDouble(),
        paidAmount: (data['paidAmount'] ?? 0).toDouble(),
        createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        saleId: data['saleId'] ?? '',
        note: data['note'] ?? '',
      );

  Map<String, dynamic> toFirestore() => {
        'customerName': customerName,
        'amount': amount,
        'paidAmount': paidAmount,
        'createdAt': Timestamp.fromDate(createdAt),
        'saleId': saleId,
        'note': note,
      };
}
