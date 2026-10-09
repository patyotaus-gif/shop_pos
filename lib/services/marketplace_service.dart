import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/marketplace_order.dart';
import '../models/supplier.dart';
import 'auth_service.dart';

/// B2B marketplace: shops browse suppliers, order stock, track delivery.
/// Available in every tier (per the GTM "marketplace อยู่ในทุก tier"
/// principle); the platform earns a 2.5% take rate at delivery.
class MarketplaceService {
  static final Map<String, Future<String>> _placing = {};
  static Future<dynamic> _call(String name, Map<String, dynamic> data) =>
      FirebaseFunctions.instanceFor(region: 'asia-southeast1')
          .httpsCallable(name)
          .call(data)
          .then((result) => result.data);

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
      _suppliersCol().where('active', isEqualTo: true).snapshots().map((s) {
        final list =
            s.docs.map((d) => Supplier.fromFirestore(d.data(), d.id)).toList();
        if (area == null || area.isEmpty) return list;
        return list
            .where((sup) => sup.area == null || sup.area == area)
            .toList();
      });

  /// Fetch one supplier by id (used by "reorder" to rebuild the cart from a
  /// past order). Returns null if the supplier doc no longer exists.
  static Future<Supplier?> getSupplier(String supplierId) async {
    final snap = await _suppliersCol().doc(supplierId).get();
    if (!snap.exists) return null;
    return Supplier.fromFirestore(snap.data()!, snap.id);
  }

  static Stream<List<SupplierProduct>> watchCatalog(String supplierId) =>
      _suppliersCol().doc(supplierId).collection('products').snapshots().map(
          (s) => s.docs
              .map((d) => SupplierProduct.fromFirestore(d.data(), d.id))
              .toList());

  // ───────────────────── Favorites / reorder ─────────────────────

  static CollectionReference<Map<String, dynamic>> _favoritesCol() =>
      FirebaseFirestore.instance
          .collection('shops')
          .doc(AuthService.shopId)
          .collection('supplierFavorites');

  /// Doc id pins a favorite to one supplier+product so the same product
  /// from two suppliers stays distinct.
  static String _favId(String supplierId, String productId) =>
      '${supplierId}_$productId';

  /// Star / unstar a product. Stores a small snapshot for display; the cart
  /// always rebuilds price/availability from the live catalog.
  static Future<void> toggleFavorite({
    required String supplierId,
    required SupplierProduct product,
    required bool makeFavorite,
  }) async {
    final ref = _favoritesCol().doc(_favId(supplierId, product.id));
    if (makeFavorite) {
      await ref.set({
        'supplierId': supplierId,
        'productId': product.id,
        'name': product.name,
        'createdAt': Timestamp.now(),
      });
    } else {
      await ref.delete();
    }
  }

  /// Live set of favorited productIds for one supplier.
  static Stream<Set<String>> watchFavoriteIds(String supplierId) =>
      _favoritesCol()
          .where('supplierId', isEqualTo: supplierId)
          .snapshots()
          .map((s) => s.docs
              .map((d) => d.data()['productId'] as String? ?? '')
              .where((id) => id.isNotEmpty)
              .toSet());

  /// productIds the shop has ordered from this supplier before — drives the
  /// "เคยสั่ง" section. Reads order history once (not a live stream).
  static Future<Set<String>> previouslyOrderedProductIds(
      String supplierId) async {
    final snap =
        await _shopOrdersCol().where('supplierId', isEqualTo: supplierId).get();
    final ids = <String>{};
    for (final doc in snap.docs) {
      for (final item in (doc.data()['items'] as List<dynamic>? ?? [])) {
        final id = (item as Map<String, dynamic>)['productId'] as String?;
        if (id != null && id.isNotEmpty) ids.add(id);
      }
    }
    return ids;
  }

  // ─────────────────────── Order placement ───────────────────────

  /// Place through the server, which validates prices and owns both copies.
  static Future<String> placeOrder({
    required Supplier supplier,
    required List<MarketplaceOrderItem> items,
  }) async {
    if (items.isEmpty) {
      throw StateError('ไม่มีรายการสั่งซื้อ');
    }
    if (items.any((i) =>
        !i.quantity.isFinite ||
        i.quantity <= 0 ||
        i.quantity > 1000000 ||
        !i.subtotal.isFinite ||
        !i.price.isFinite ||
        i.price < 0)) {
      throw StateError('จำนวนหรือราคาสั่งซื้อไม่ถูกต้อง');
    }
    if (items.fold(0.0, (amount, item) => amount + item.subtotal) <
        supplier.minOrder) {
      throw StateError('ยอดสั่งซื้อน้อยกว่าขั้นต่ำของซัพพลายเออร์');
    }
    if (AuthService.isStaff || AuthService.shopId == null) {
      throw StateError('เฉพาะเจ้าของร้าน');
    }
    final lines = items
        .map((i) => {'productId': i.productId, 'quantity': i.quantity})
        .toList()
      ..sort((a, b) =>
          (a['productId'] as String).compareTo(b['productId'] as String));
    final payload = <String, dynamic>{
      'shopId': AuthService.shopId,
      'supplierId': supplier.id,
      'items': lines,
      'expectedTotal': items.fold<double>(
          0, (amount, i) => amount + (i.subtotal * 100).round() / 100),
    };
    final identity = jsonEncode(payload);
    return _placing.putIfAbsent(
        identity,
        () => _submitOrder(identity, payload)
            .whenComplete(() => _placing.remove(identity)));
  }

  static Future<String> _submitOrder(
      String identity, Map<String, dynamic> payload) async {
    // Keep the same id across a lost reply or process restart. No customer secrets.
    final prefs = await SharedPreferences.getInstance();
    final key = 'marketplaceRequest:${base64Url.encode(utf8.encode(identity))}';
    final requestId = prefs.getString(key) ?? _shopOrdersCol().doc().id;
    if (!await prefs.setString(key, requestId)) {
      throw StateError('บันทึกคำขอในเครื่องไม่ได้ กรุณาลองใหม่');
    }
    final result = await _call(
        'marketplacePlaceOrder', {...payload, 'requestId': requestId});
    final orderId = result['orderId'] as String;
    // A cleanup failure must not turn a confirmed order into a failed checkout.
    try {
      await prefs.remove(key);
    } catch (_) {}
    return orderId;
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
    await _call('marketplaceShopOrderStatus',
        {'orderId': order.id, 'status': 'cancelled'});
  }

  /// The server validates shipped state and computes the fee from saved prices.
  static Future<void> confirmDelivered(MarketplaceOrder order) async {
    await _call('marketplaceShopOrderStatus',
        {'orderId': order.id, 'status': 'delivered'});
  }
}
