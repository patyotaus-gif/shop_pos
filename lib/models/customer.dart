import 'package:cloud_firestore/cloud_firestore.dart';

/// A loyalty customer, keyed by phone number within a shop. Lives at
/// `shops/{shopId}/customers/{customerId}`. Distinct from the `debts`
/// collection (which is keyed by free-text name for credit tracking) —
/// loyalty needs a stable identity (phone) to accrue points across visits.
///
/// Loyalty is a Full/Restaurant feature; lower tiers never write here.
class Customer {
  final String id;
  final String name;
  final String phone;

  /// Lifetime points balance. Earned on purchase, spent on redemption.
  final int points;

  /// Lifetime spend in baht — useful for "top customers" later.
  final double totalSpent;

  final DateTime createdAt;
  final DateTime? lastVisitAt;

  const Customer({
    required this.id,
    required this.name,
    required this.phone,
    this.points = 0,
    this.totalSpent = 0,
    required this.createdAt,
    this.lastVisitAt,
  });

  factory Customer.fromFirestore(Map<String, dynamic> data, String id) =>
      Customer(
        id: id,
        name: data['name'] ?? '',
        phone: data['phone'] ?? '',
        points: (data['points'] ?? 0) as int,
        totalSpent: (data['totalSpent'] ?? 0).toDouble(),
        createdAt:
            (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        lastVisitAt: (data['lastVisitAt'] as Timestamp?)?.toDate(),
      );

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'phone': phone,
        'points': points,
        'totalSpent': totalSpent,
        'createdAt': Timestamp.fromDate(createdAt),
        if (lastVisitAt != null) 'lastVisitAt': Timestamp.fromDate(lastVisitAt!),
      };
}
