import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/cart_item.dart';
import '../models/sale.dart';
import '../models/debt.dart';
import '../utils/receipt_number.dart';
import 'customer_service.dart';
import 'entitlements.dart';
import 'notification_service.dart';
import 'product_service.dart';
import 'shop_service.dart';
import 'shop_database.dart';

class SaleService {
  static DocumentReference<Map<String, dynamic>> _shopDoc() =>
      ShopDatabase.shop;
  static CollectionReference<Map<String, dynamic>> _salesCol() =>
      _shopDoc().collection('sales');
  static bool _running = false;
  static String _pendingKey(String shopId) => 'pending-checkout-$shopId';

  static Future<Sale?> pendingCheckout() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_pendingKey(_shopDoc().id));
    if (raw == null) return null;
    final data = Map<String, dynamic>.from(jsonDecode(raw));
    data['createdAt'] =
        Timestamp.fromMillisecondsSinceEpoch(data['createdAt'] as int);
    return Sale.fromFirestore(data, data['id'] as String);
  }

  static Future<Sale> checkout({
    required List<CartItem> cart,
    required double paid,
    required double discount,
    bool isDebt = false,
    String? customerName,
    PaymentMethod paymentMethod = PaymentMethod.cash,
    String? staffName,
    String? loyaltyCustomerId,
  }) async {
    if (_running) throw StateError('กำลังบันทึกรายการ กรุณารอสักครู่');
    _running = true;
    try {
      final shop = _shopDoc();
      final prefs = await SharedPreferences.getInstance();
      final key = _pendingKey(shop.id);
      // A confirmed, unresolved payment always keeps its original ID/payload,
      // even if the app was restarted before the server response arrived.
      if (prefs.getString(key) == null) {
        final items = cart
            .map((e) => SaleItem(
                productId: e.product.id,
                productName: e.product.name,
                price: e.product.effectivePrice,
                costPrice: e.product.costPrice,
                quantity: e.quantity,
                subtotal: e.subtotal))
            .toList();
        final total =
            items.fold<double>(0, (amount, e) => amount + e.subtotal) - discount;
        final sale = Sale(
            id: shop.collection('sales').doc().id,
            items: items,
            total: total,
            discount: discount,
            paid: isDebt ? 0 : paid,
            change: isDebt || paymentMethod != PaymentMethod.cash
                ? 0
                : paid - total,
            createdAt: DateTime.now(),
            isDebt: isDebt,
            customerName: customerName,
            paymentMethod: paymentMethod,
            staffName: staffName);
        validateSale(sale);
        final stored = {
          ...sale.toFirestore(),
          'id': sale.id,
          'createdAt': sale.createdAt.millisecondsSinceEpoch,
          if (loyaltyCustomerId != null) 'loyaltyCustomerId': loyaltyCustomerId
        };
        if (!await prefs.setString(key, jsonEncode(stored))) {
          throw StateError(
              'เก็บรายการในเครื่องไม่สำเร็จ กรุณาลองใหม่ก่อนรับเงิน');
        }
      }
      return await _resume(shop, prefs, key);
    } finally {
      _running = false;
    }
  }

  static Future<Sale> resumeCheckout() =>
      checkout(cart: const [], paid: 0, discount: 0);

  static Future<Sale> _resume(DocumentReference<Map<String, dynamic>> shop,
      SharedPreferences prefs, String key) async {
    final data = Map<String, dynamic>.from(jsonDecode(prefs.getString(key)!));
    data['createdAt'] =
        Timestamp.fromMillisecondsSinceEpoch(data['createdAt'] as int);
    final draft = Sale.fromFirestore(data, data['id'] as String);
    final Sale result;
    try {
      result = await commitSale(shop, draft,
          loyaltyCustomerId: data['loyaltyCustomerId'] as String?);
    } on StateError {
      // Validation failures occur before any write; this draft can be edited.
      await prefs.remove(key);
      rethrow;
    }
    // Failure of local cleanup or notifications cannot turn a saved sale into
    // an apparent payment failure. A leftover draft replays the same sale ID.
    try {
      await prefs.remove(key);
    } catch (_) {}
    unawaited(_notifyLowStock(draft));
    return result;
  }

  static void validateSale(Sale sale) {
    if (sale.items.isEmpty ||
        sale.items.any(
            (i) => i.quantity <= 0 || !i.subtotal.isFinite || i.subtotal < 0) ||
        !sale.total.isFinite ||
        sale.total < 0 ||
        !sale.discount.isFinite ||
        sale.discount < 0 ||
        !sale.paid.isFinite ||
        sale.paid < 0) {
      throw StateError('กรุณาตรวจสอบรายการ ราคา และส่วนลด');
    }
    if (!sale.isDebt &&
        sale.paymentMethod == PaymentMethod.cash &&
        sale.paid + 0.001 < sale.total) {
      throw StateError('จำนวนเงินที่รับน้อยกว่ายอดบิล');
    }
    if (sale.isDebt && (sale.customerName?.trim().isEmpty ?? true)) {
      throw StateError('กรุณาระบุชื่อลูกค้าสำหรับขายเชื่อ');
    }
  }

  /// Public for transaction tests; the same ID is safe to replay.
  static Future<Sale> commitSale(
      DocumentReference<Map<String, dynamic>> shop, Sale draft,
      {String? loyaltyCustomerId}) async {
    validateSale(draft);
    final saleRef = shop.collection('sales').doc(draft.id);
    final counterRef = shop.collection('counters').doc('receipt');
    return shop.firestore.runTransaction<Sale>((tx) async {
      final existing = await tx.get(saleRef);
      if (existing.exists) {
        return Sale.fromFirestore(existing.data()!, existing.id);
      }
      final counter = await tx.get(counterRef);
      final quantities = <String, int>{};
      for (final item in draft.items) {
        quantities.update(item.productId, (q) => q + item.quantity,
            ifAbsent: () => item.quantity);
      }
      for (final entry in quantities.entries) {
        final product =
            await tx.get(shop.collection('products').doc(entry.key));
        if (!product.exists) {
          throw StateError('มีสินค้าถูกลบ กรุณาตรวจสอบตะกร้า');
        }
        if ((product.data()?['stock'] as num? ?? 0) < entry.value) {
          throw StateError('สินค้าคงเหลือไม่พอ: ${product.data()?['name'] ?? entry.key}');
        }
      }
      final customerRef = loyaltyCustomerId == null
          ? null
          : shop.collection('customers').doc(loyaltyCustomerId);
      final customer = customerRef == null ? null : await tx.get(customerRef);
      final day = receiptDay(draft.createdAt);
      final next = nextReceiptSeq(counter.data()?['day'] as String?, day,
          (counter.data()?['seq'] as num? ?? 0).toInt());
      final payload = {
        ...draft.toFirestore(),
        'receiptNo': formatReceiptNo(next.day, next.seq)
      };
      tx.set(saleRef, payload);
      for (final entry in quantities.entries) {
        tx.update(shop.collection('products').doc(entry.key),
            {'stock': FieldValue.increment(-entry.value)});
      }
      if (draft.isDebt) {
        tx.set(
            shop.collection('debts').doc(draft.id),
            Debt(
                    id: draft.id,
                    customerName: draft.customerName!,
                    amount: draft.total,
                    createdAt: draft.createdAt,
                    saleId: draft.id)
                .toFirestore());
      }
      if (customer?.exists == true) {
        tx.update(customerRef!, {
          'points':
              FieldValue.increment(CustomerService.pointsFor(draft.total)),
          'totalSpent': FieldValue.increment(draft.total),
          'lastVisitAt': Timestamp.fromDate(draft.createdAt)
        });
      }
      tx.set(counterRef, {'day': next.day, 'seq': next.seq});
      return Sale.fromFirestore(payload, draft.id);
    });
  }

  static Future<void> _notifyLowStock(Sale sale) async {
    try {
      final shop = await ShopService.getCurrentShop();
      if (shop == null || !Entitlements.canUseInventory(shop.tier)) return;
      final products = await ProductService.watchAll().first;
      for (final product in products.where(
          (p) => sale.items.any((i) => i.productId == p.id) && p.isLowStock)) {
        await NotificationService.showLowStock(product.name, product.stock);
      }
    } catch (_) {}
  }

  static Stream<List<Sale>> watchToday() {
    final start = DateTime.now();
    final startOfDay = DateTime(start.year, start.month, start.day);
    return _salesCol()
        .where('createdAt',
            isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) =>
            s.docs.map((d) => Sale.fromFirestore(d.data(), d.id)).toList());
  }

  static Stream<List<Sale>> watchByRange(DateTime from, DateTime to) =>
      _salesCol()
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
          .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(to))
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((s) =>
              s.docs.map((d) => Sale.fromFirestore(d.data(), d.id)).toList());

  static Stream<List<Sale>> watchByCustomer(String customerName) => _salesCol()
          .where('customerName', isEqualTo: customerName)
          .snapshots()
          .map((s) {
        final list =
            s.docs.map((d) => Sale.fromFirestore(d.data(), d.id)).toList();
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return list;
      });

  static final Set<String> _refunding = {};
  static Future<void> refundSale(Sale sale, {String reason = ''}) async {
    final shop = _shopDoc();
    final key = '${shop.id}/${sale.id}';
    if (!_refunding.add(key)) {
      throw StateError('กำลังคืนเงินรายการนี้ กรุณารอสักครู่');
    }
    try {
      if (sale.stripePaymentIntentId != null) {
        await FirebaseFunctions.instanceFor(region: 'asia-southeast1')
            .httpsCallable('createRefund')
            .call({'shopId': shop.id, 'saleId': sale.id, 'reason': reason});
      } else {
        await refundLocal(shop, sale.id, reason: reason);
      }
    } finally {
      _refunding.remove(key);
    }
  }

  static Future<void> refundLocal(
      DocumentReference<Map<String, dynamic>> shop, String saleId,
      {String reason = ''}) async {
    final ref = shop.collection('sales').doc(saleId);
    // Resolve legacy auto-ID debts; the refund flag guards their deletion too.
    final debts = await shop
        .collection('debts')
        .where('saleId', isEqualTo: saleId)
        .get(const GetOptions(source: Source.server));
    await shop.firestore.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw StateError('ไม่พบบิลที่ต้องการคืนเงิน');
      final sale = Sale.fromFirestore(snap.data()!, snap.id);
      if (sale.isRefunded) return;
      if (sale.stripePaymentIntentId != null) {
        throw StateError('กรุณาคืนเงินรายการนี้ผ่านระบบออนไลน์');
      }
      final quantities = <String, int>{};
      for (final item in sale.items) {
        quantities.update(item.productId, (q) => q + item.quantity,
            ifAbsent: () => item.quantity);
      }
      final restorable = <String, int>{};
      for (final entry in quantities.entries) {
        if ((await tx.get(shop.collection('products').doc(entry.key))).exists) {
          restorable[entry.key] = entry.value;
        }
      }
      tx.update(ref, {
        'isRefunded': true,
        'refundedAt': Timestamp.now(),
        'refundReason': reason
      });
      for (final entry in restorable.entries) {
        tx.update(shop.collection('products').doc(entry.key),
            {'stock': FieldValue.increment(entry.value)});
      }
      if (sale.isDebt) {
        for (final debt in debts.docs) {
          tx.delete(debt.reference);
        }
      }
    });
  }
}
