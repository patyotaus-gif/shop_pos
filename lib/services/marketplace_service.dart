import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/marketplace_order.dart';
import '../models/supplier.dart';
import 'auth_service.dart';
import 'shop_service.dart';

/// B2B marketplace: shops browse suppliers, order stock, track delivery.
/// Available in every tier (per the GTM "marketplace อยู่ในทุก tier"
/// principle); the platform earns a 2.5% take rate at delivery.
class MarketplaceService {
  static const double takeRate = 0.025; // 2.5%

  static CollectionReference<Map<String, dynamic>> _suppliersCol() =>
      FirebaseFirestore.instance.collection('suppliers');

  static CollectionReference<Map<String, dynamic>> _shopOrdersCol() =>
      FirebaseFirestore.instance
          .collection('shops')
          .doc(AuthService.shopId)
          .collection('marketplaceOrders');

  // ───────────────────────── Suppliers ─────────────────────────

  /// Active suppliers, optionally filtered to the shop's area. Area match
  /// is done client-side so a missing area on either side still shows the
  /// supplier (fail-open — better to show too many than hide stock the
  /// shop could actually buy).
  static Stream<List<Supplier>> watchSuppliers({String? area}) =>
      _suppliersCol()
          .where('active', isEqualTo: true)
          .snapshots()
          .map((s) {
        final list = s.docs
            .map((d) => Supplier.fromFirestore(d.data(), d.id))
            .toList();
        if (area == null || area.isEmpty) return list;
        return list
            .where((sup) => sup.area == null || sup.area == area)
            .toList();
      });

  static Stream<List<SupplierProduct>> watchCatalog(String supplierId) =>
      _suppliersCol()
          .doc(supplierId)
          .collection('products')
          .snapshots()
          .map((s) => s.docs
              .map((d) => SupplierProduct.fromFirestore(d.data(), d.id))
              .toList());

  // ─────────────────────── Order placement ───────────────────────

  /// Place an order with [supplier]. Writes the same order doc to both the
  /// shop's and the supplier's subcollections (shared id) so each side
  /// queries its own. Returns the order id.
  static Future<String> placeOrder({
    required Supplier supplier,
    required List<MarketplaceOrderItem> items,
  }) async {
    if (items.isEmpty) {
      throw StateError('ไม่มีรายการสั่งซื้อ');
    }
    final shop = await ShopService.getCurrentShop();
    final shopId = AuthService.shopId!;

    final orderRef = _shopOrdersCol().doc();
    final supplierOrderRef =
        _suppliersCol().doc(supplier.id).collection('orders').doc(orderRef.id);

    final order = MarketplaceOrder(
      id: orderRef.id,
      shopId: shopId,
      shopName: shop?.name ?? 'ร้านค้า',
      supplierId: supplier.id,
      supplierName: supplier.name,
      items: items,
      createdAt: DateTime.now(),
    );

    final batch = FirebaseFirestore.instance.batch();
    batch.set(orderRef, order.toFirestore());
    batch.set(supplierOrderRef, order.toFirestore());
    await batch.commit();
    return orderRef.id;
  }

  /// The shop's marketplace order history, newest first.
  static Stream<List<MarketplaceOrder>> watchMyOrders() => _shopOrdersCol()
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs
          .map((d) => MarketplaceOrder.fromFirestore(d.data(), d.id))
          .toList());

  /// Cancel a placed/accepted order (shop side). Mirrors to the supplier
  /// copy. Can't cancel once shipped/delivered.
  static Future<void> cancelOrder(MarketplaceOrder order) async {
    if (order.status == MarketplaceOrderStatus.shipped ||
        order.status == MarketplaceOrderStatus.delivered) {
      throw StateError('ยกเลิกไม่ได้ — ของกำลังส่ง/ส่งแล้ว');
    }
    final batch = FirebaseFirestore.instance.batch();
    batch.update(_shopOrdersCol().doc(order.id),
        {'status': MarketplaceOrderStatus.cancelled.name});
    batch.update(
        _suppliersCol().doc(order.supplierId).collection('orders').doc(order.id),
        {'status': MarketplaceOrderStatus.cancelled.name});
    await batch.commit();
  }

  /// Confirm receipt of a delivered order (shop side). Stamps the take
  /// rate (2.5% of subtotal) onto both copies — this is the billing
  /// trigger the platform reconciles monthly. Marking delivered is the
  /// shop's action here; in production a supplier-driven flow + Cloud
  /// Function would own the money movement, but recording it on the doc
  /// keeps the data correct in the meantime.
  static Future<void> confirmDelivered(MarketplaceOrder order) async {
    final fee =
        double.parse((order.subtotal * takeRate).toStringAsFixed(2));
    final patch = {
      'status': MarketplaceOrderStatus.delivered.name,
      'takeRate': fee,
      'deliveredAt': Timestamp.now(),
    };
    final batch = FirebaseFirestore.instance.batch();
    batch.update(_shopOrdersCol().doc(order.id), patch);
    batch.update(
        _suppliersCol().doc(order.supplierId).collection('orders').doc(order.id),
        patch);
    await batch.commit();
  }
}
