import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/cart_item.dart';
import '../models/sale.dart';
import '../models/debt.dart';
import 'product_service.dart';

class SaleService {
  static final _sales = FirebaseFirestore.instance.collection('sales');
  static final _debts = FirebaseFirestore.instance.collection('debts');

  static Future<Sale> checkout({
    required List<CartItem> cart,
    required double paid,
    required double discount,
    bool isDebt = false,
    String? customerName,
  }) async {
    final total = cart.fold<double>(0, (s, e) => s + e.subtotal) - discount;
    final change = isDebt ? 0 : paid - total;

    final saleItems = cart
        .map((e) => SaleItem(
              productId: e.product.id,
              productName: e.product.name,
              price: e.product.price,
              quantity: e.quantity,
              subtotal: e.subtotal,
            ))
        .toList();

    final sale = Sale(
      id: '',
      items: saleItems,
      total: total,
      discount: discount,
      paid: isDebt ? 0 : paid,
      change: change,
      createdAt: DateTime.now(),
      isDebt: isDebt,
      customerName: customerName,
    );

    final batch = FirebaseFirestore.instance.batch();

    // Save sale
    final saleRef = _sales.doc();
    batch.set(saleRef, sale.toFirestore());

    // Deduct stock
    for (final item in cart) {
      final productRef = FirebaseFirestore.instance.collection('products').doc(item.product.id);
      batch.update(productRef, {'stock': FieldValue.increment(-item.quantity)});
    }

    // Save debt if needed
    if (isDebt && customerName != null) {
      final debtRef = _debts.doc();
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
    return Sale(
      id: saleRef.id,
      items: saleItems,
      total: total,
      discount: discount,
      paid: isDebt ? 0 : paid,
      change: change,
      createdAt: sale.createdAt,
      isDebt: isDebt,
      customerName: customerName,
    );
  }

  static Stream<List<Sale>> watchToday() {
    final start = DateTime.now();
    final startOfDay = DateTime(start.year, start.month, start.day);
    return _sales
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay))
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((s) => s.docs.map((d) => Sale.fromFirestore(d.data(), d.id)).toList());
  }

  static Stream<List<Sale>> watchByRange(DateTime from, DateTime to) => _sales
      .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(from))
      .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(to))
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((s) => s.docs.map((d) => Sale.fromFirestore(d.data(), d.id)).toList());

  static Future<void> voidSale(Sale sale) async {
    final batch = FirebaseFirestore.instance.batch();
    batch.delete(_sales.doc(sale.id));
    // Restore stock
    for (final item in sale.items) {
      final ref = FirebaseFirestore.instance.collection('products').doc(item.productId);
      batch.update(ref, {'stock': FieldValue.increment(item.quantity)});
    }
    await batch.commit();
  }
}
