import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/order.dart';
import 'auth_service.dart';

class OrderService {
  static CollectionReference<Map<String, dynamic>> _col() =>
      FirebaseFirestore.instance
          .collection('shops')
          .doc(AuthService.shopId)
          .collection('orders');

  static Stream<List<ShopOrder>> watchActive() => _col()
      .where('status', whereIn: [
        'pendingPayment',
        'paid',
        'accepted',
        'ready',
      ])
      .snapshots()
      .map((s) {
        final orders = s.docs.map((d) => ShopOrder.fromFirestore(d.data(), d.id)).toList();
        // Pending payment first (needs attention), then by created time.
        orders.sort((a, b) {
          if (a.status == OrderStatus.pendingPayment &&
              b.status != OrderStatus.pendingPayment) {
            return -1;
          }
          if (b.status == OrderStatus.pendingPayment &&
              a.status != OrderStatus.pendingPayment) {
            return 1;
          }
          return a.createdAt.compareTo(b.createdAt);
        });
        return orders;
      });

  static Stream<List<ShopOrder>> watchAll() => _col()
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) =>
          s.docs.map((d) => ShopOrder.fromFirestore(d.data(), d.id)).toList());

  static Stream<int> watchNewOrders() => _col()
      .where('status', isEqualTo: 'paid')
      .snapshots()
      .map((s) => s.docs.length);

  static Future<void> updateStatus(String orderId, OrderStatus status) =>
      _col().doc(orderId).update({'status': status.name});

  static Stream<List<ShopOrder>> watchPendingPayment() => _col()
      .where('status', isEqualTo: OrderStatus.pendingPayment.name)
      .snapshots()
      .map((s) {
        final orders =
            s.docs.map((d) => ShopOrder.fromFirestore(d.data(), d.id)).toList();
        orders.sort((a, b) => a.createdAt.compareTo(b.createdAt));
        return orders;
      });

  /// Mark a pending order as paid (manual confirm by the shop owner after
  /// they've eyeballed their banking app). Records the optional [paymentRef]
  /// the user typed in so it can be cross-checked later.
  static Future<void> confirmPaid(String orderId, {String? paymentRef}) =>
      _col().doc(orderId).update({
        'status': OrderStatus.paid.name,
        'paidAt': FieldValue.serverTimestamp(),
        if (paymentRef != null && paymentRef.isNotEmpty) 'paymentRef': paymentRef,
      });
}
