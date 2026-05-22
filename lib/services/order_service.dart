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
      .where('status', whereIn: ['paid', 'accepted', 'ready'])
      .snapshots()
      .map((s) {
        final orders = s.docs.map((d) => ShopOrder.fromFirestore(d.data(), d.id)).toList();
        orders.sort((a, b) => a.createdAt.compareTo(b.createdAt));
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
}
