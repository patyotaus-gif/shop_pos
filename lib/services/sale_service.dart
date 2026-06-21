import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../models/cart_item.dart';
import '../models/sale.dart';
import '../models/debt.dart';
import 'auth_service.dart';
import 'customer_service.dart';
import 'notification_service.dart';
import 'product_service.dart';

class SaleService {
  static DocumentReference<Map<String, dynamic>> _shopDoc() =>
      FirebaseFirestore.instance
          .collection('shops')
          .doc(AuthService.shopId);

  static CollectionReference<Map<String, dynamic>> _salesCol() =>
      _shopDoc().collection('sales');

  static CollectionReference<Map<String, dynamic>> _debtsCol() =>
      _shopDoc().collection('debts');

  static CollectionReference<Map<String, dynamic>> _productsCol() =>
      _shopDoc().collection('products');

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
    final total =
        cart.fold<double>(0, (s, e) => s + e.subtotal) - discount;
    final change =
        isDebt || paymentMethod != PaymentMethod.cash ? 0.0 : paid - total;

    final saleItems = cart
        .map((e) => SaleItem(
              productId: e.product.id,
              productName: e.product.name,
              price: e.product.effectivePrice,
              costPrice: e.product.costPrice,
              quantity: e.quantity,
              subtotal: e.subtotal,
            ))
        .toList();

    final sale = Sale(
      id: '',
      items: saleItems,
      total: total,
      discount: discount,
      paid: isDebt ? 0.0 : paid,
      change: change,
      createdAt: DateTime.now(),
      isDebt: isDebt,
      customerName: customerName,
      paymentMethod: paymentMethod,
      staffName: staffName,
    );

    final batch = FirebaseFirestore.instance.batch();

    // Save sale
    final saleRef = _salesCol().doc();
    batch.set(saleRef, sale.toFirestore());

    // Deduct stock
    for (final item in cart) {
      final productRef = _productsCol().doc(item.product.id);
      batch.update(productRef, {'stock': FieldValue.increment(-item.quantity)});
    }

    // Save debt if needed
    if (isDebt && customerName != null) {
      final debtRef = _debtsCol().doc();
      final debt = Debt(
        id: '',
        customerName: customerName,
        amount: total,
        createdAt: DateTime.now(),
        saleId: saleRef.id,
      );
      batch.set(debtRef, debt.toFirestore());
    }

    await batch.commit();

    // Accrue loyalty points if a customer was attached. Best-effort —
    // outside the batch so a loyalty hiccup never fails the sale itself.
    if (loyaltyCustomerId != null) {
      try {
        await CustomerService.recordPurchase(
          customerId: loyaltyCustomerId,
          spend: total,
        );
      } catch (_) {}
    }

    // Check low stock and notify
    for (final item in cart) {
      final product = await ProductService.getByBarcode(item.product.barcode);
      if (product != null && product.isLowStock) {
        await NotificationService.showLowStock(product.name, product.stock);
      }
    }

    return Sale(
      id: saleRef.id,
      items: saleItems,
      total: total,
      discount: discount,
      paid: isDebt ? 0.0 : paid,
      change: change,
      createdAt: sale.createdAt,
      isDebt: isDebt,
      customerName: customerName,
      paymentMethod: paymentMethod,
      staffName: staffName,
    );
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
          .where('createdAt',
              isGreaterThanOrEqualTo: Timestamp.fromDate(from))
          .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(to))
          .orderBy('createdAt', descending: true)
          .snapshots()
          .map((s) =>
              s.docs.map((d) => Sale.fromFirestore(d.data(), d.id)).toList());

  static Stream<List<Sale>> watchByCustomer(String customerName) =>
      _salesCol()
          .where('customerName', isEqualTo: customerName)
          .snapshots()
          .map((s) {
        final list = s.docs
            .map((d) => Sale.fromFirestore(d.data(), d.id))
            .toList();
        list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
        return list;
      });

  static Future<void> refundSale(Sale sale, {String reason = ''}) async {
    if (sale.paymentMethod == PaymentMethod.online &&
        sale.stripePaymentIntentId != null) {
      // Online order — delegate to Firebase Function (handles Stripe + Firestore)
      final fn = FirebaseFunctions.instanceFor(region: 'asia-southeast1')
          .httpsCallable('createRefund');
      await fn.call({
        'shopId': AuthService.shopId,
        'saleId': sale.id,
        'reason': reason,
      });
      return;
    }

    // Cash / transfer / QR — handle locally
    final batch = FirebaseFirestore.instance.batch();
    batch.update(_salesCol().doc(sale.id), {
      'isRefunded': true,
      'refundedAt': Timestamp.now(),
      'refundReason': reason,
    });
    for (final item in sale.items) {
      batch.update(_productsCol().doc(item.productId),
          {'stock': FieldValue.increment(item.quantity)});
    }
    if (sale.isDebt) {
      final debtSnap = await _debtsCol()
          .where('saleId', isEqualTo: sale.id)
          .limit(1)
          .get();
      for (final doc in debtSnap.docs) {
        batch.delete(doc.reference);
      }
    }
    await batch.commit();
  }
}
