import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/customer.dart';
import 'auth_service.dart';

/// Loyalty customers for the current shop. Phone is the natural key, so
/// lookups + upserts go through [findByPhone] / [ensure].
class CustomerService {
  /// Baht spent to earn 1 point. ฿25 = 1 point keeps the math legible for
  /// shop owners and the reward meaningful (a 100-point reward ≈ ฿2,500
  /// spent). Tunable in one place.
  static const double bahtPerPoint = 25;

  static int pointsFor(double spend) => (spend / bahtPerPoint).floor();

  /// Points a customer spends for each baht of discount, unless the shop
  /// sets its own rate in settings.
  static const int defaultPointsPerBaht = 10;

  /// Whole baht a customer can take off this bill: limited by their points
  /// and by what is still payable after other discounts.
  static int maxRedeemBaht(
      {required int points,
      required int pointsPerBaht,
      required double payable}) {
    if (pointsPerBaht <= 0 || points <= 0 || payable <= 0) return 0;
    final byPoints = points ~/ pointsPerBaht;
    final byBill = payable.floor();
    return byPoints < byBill ? byPoints : byBill;
  }

  static CollectionReference<Map<String, dynamic>> _col() =>
      FirebaseFirestore.instance
          .collection('shops')
          .doc(AuthService.shopId)
          .collection('customers');

  static Stream<List<Customer>> watchAll() => _col()
      .orderBy('lastVisitAt', descending: true)
      .snapshots()
      .map((s) =>
          s.docs.map((d) => Customer.fromFirestore(d.data(), d.id)).toList());

  static Future<Customer?> findByPhone(String phone) async {
    final clean = phone.trim();
    if (clean.isEmpty) return null;
    final snap =
        await _col().where('phone', isEqualTo: clean).limit(1).get();
    if (snap.docs.isEmpty) return null;
    return Customer.fromFirestore(snap.docs.first.data(), snap.docs.first.id);
  }

  /// Find an existing customer by phone or create a new one. Returns the
  /// customer (with id). Used at checkout when the cashier attaches a
  /// phone to the sale.
  static Future<Customer> ensure({
    required String phone,
    required String name,
  }) async {
    final existing = await findByPhone(phone);
    if (existing != null) return existing;
    final ref = _col().doc();
    final customer = Customer(
      id: ref.id,
      name: name.trim().isEmpty ? phone.trim() : name.trim(),
      phone: phone.trim(),
      createdAt: DateTime.now(),
      lastVisitAt: DateTime.now(),
    );
    await ref.set(customer.toFirestore());
    return customer;
  }

  static Future<int> pointsOf(String customerId) async {
    final snap = await _col().doc(customerId).get();
    return (snap.data()?['points'] as num? ?? 0).toInt();
  }

  /// Customer picked for a ค้างชำระ bill. Phone is optional here, so reuse a
  /// record by phone first, then by exact name, before creating a new one.
  static Future<Customer> ensureByName({
    required String name,
    String phone = '',
  }) async {
    final cleanName = name.trim();
    if (cleanName.isEmpty) throw StateError('กรุณาระบุชื่อลูกค้า');
    final byPhone = await findByPhone(phone);
    if (byPhone != null) return byPhone;
    final byName =
        await _col().where('name', isEqualTo: cleanName).limit(1).get();
    if (byName.docs.isNotEmpty) {
      return Customer.fromFirestore(
          byName.docs.first.data(), byName.docs.first.id);
    }
    final ref = _col().doc();
    final customer = Customer(
      id: ref.id,
      name: cleanName,
      phone: phone.trim(),
      createdAt: DateTime.now(),
      lastVisitAt: DateTime.now(),
    );
    await ref.set(customer.toFirestore());
    return customer;
  }

  /// Apply a purchase: accrue points + bump totalSpent + stamp visit.
  /// Atomic via FieldValue increments so concurrent sales don't clobber.
  static Future<void> recordPurchase({
    required String customerId,
    required double spend,
  }) async {
    await _col().doc(customerId).update({
      'points': FieldValue.increment(pointsFor(spend)),
      'totalSpent': FieldValue.increment(spend),
      'lastVisitAt': Timestamp.now(),
    });
  }

  /// Redeem (subtract) points — e.g. when applied as a discount. Guarded
  /// so the balance can't go negative.
  static Future<void> redeemPoints({
    required String customerId,
    required int points,
  }) async {
    if (points <= 0) return;
    await _col().doc(customerId).update({
      'points': FieldValue.increment(-points),
    });
  }
}
