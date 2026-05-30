import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/product.dart';
import '../models/restaurant_table.dart';
import '../models/sale.dart';
import '../models/table_order.dart';
import 'auth_service.dart';

/// Tables + their open tabs.
///
/// Tabs live in a separate `tableOrders` collection rather than overloading
/// `sales` with an `open` status — keeps Sale's "completed transaction"
/// semantics intact (reports, refunds, dashboards) and lets restaurant-only
/// fields (modifiers, kitchen status) grow on TableOrder without bloating
/// the retail Sale doc.
class TableService {
  static DocumentReference<Map<String, dynamic>> _shopDoc() =>
      FirebaseFirestore.instance
          .collection('shops')
          .doc(AuthService.shopId);

  static CollectionReference<Map<String, dynamic>> _tablesCol() =>
      _shopDoc().collection('tables');

  static CollectionReference<Map<String, dynamic>> _tableOrdersCol() =>
      _shopDoc().collection('tableOrders');

  static CollectionReference<Map<String, dynamic>> _salesCol() =>
      _shopDoc().collection('sales');

  static CollectionReference<Map<String, dynamic>> _productsCol() =>
      _shopDoc().collection('products');

  // ───────────────────────── Tables CRUD ─────────────────────────

  static Stream<List<RestaurantTable>> watchTables() => _tablesCol()
      .orderBy('createdAt')
      .snapshots()
      .map((s) => s.docs
          .map((d) => RestaurantTable.fromFirestore(d.data(), d.id))
          .toList());

  static Future<RestaurantTable?> getTable(String tableId) async {
    final snap = await _tablesCol().doc(tableId).get();
    if (!snap.exists) return null;
    return RestaurantTable.fromFirestore(snap.data()!, snap.id);
  }

  static Future<String> createTable({
    required String name,
    int capacity = 4,
    String? section,
  }) async {
    final ref = _tablesCol().doc();
    final table = RestaurantTable(
      id: ref.id,
      name: name,
      capacity: capacity,
      section: section,
      createdAt: DateTime.now(),
    );
    await ref.set(table.toFirestore());
    return ref.id;
  }

  static Future<void> updateTable(RestaurantTable table) async {
    await _tablesCol().doc(table.id).update({
      'name': table.name,
      'capacity': table.capacity,
      if (table.section != null) 'section': table.section,
    });
  }

  static Future<void> deleteTable(String tableId) async {
    // Caller is expected to check the table has no open order; we only
    // delete the doc itself here.
    await _tablesCol().doc(tableId).delete();
  }

  // ─────────────────────── Open tab workflow ───────────────────────

  /// Watch the single open order for [tableId] (or null if the table is
  /// available). Uses limit(1) since a table only ever has one open tab.
  static Stream<TableOrder?> watchOpenOrderForTable(String tableId) =>
      _tableOrdersCol()
          .where('tableId', isEqualTo: tableId)
          .where('status', isEqualTo: 'open')
          .limit(1)
          .snapshots()
          .map((s) => s.docs.isEmpty
              ? null
              : TableOrder.fromFirestore(s.docs.first.data(), s.docs.first.id));

  /// Open a new tab on [table]. Marks the table occupied and writes an
  /// empty TableOrder doc. Returns the new order id.
  static Future<String> openOrder(RestaurantTable table) async {
    final orderRef = _tableOrdersCol().doc();
    final order = TableOrder(
      id: orderRef.id,
      tableId: table.id,
      tableName: table.name,
      items: const [],
      openedAt: DateTime.now(),
    );

    final batch = FirebaseFirestore.instance.batch();
    batch.set(orderRef, order.toFirestore());
    batch.update(_tablesCol().doc(table.id), {
      'status': TableStatus.occupied.name,
      'currentOrderId': orderRef.id,
    });
    await batch.commit();
    return orderRef.id;
  }

  /// Append [item] to the tab. If the same productId is already there with
  /// no notes, bump its quantity instead of pushing a duplicate row.
  static Future<void> addItem(
      String orderId, TableOrderItem item) async {
    final ref = _tableOrdersCol().doc(orderId);
    final snap = await ref.get();
    if (!snap.exists) return;
    final order = TableOrder.fromFirestore(snap.data()!, snap.id);

    final mergedIndex = order.items.indexWhere(
      (i) => i.productId == item.productId && i.notes == item.notes,
    );
    final List<TableOrderItem> next;
    if (mergedIndex >= 0) {
      next = [...order.items];
      next[mergedIndex] = next[mergedIndex]
          .copyWith(quantity: next[mergedIndex].quantity + item.quantity);
    } else {
      next = [...order.items, item];
    }
    await ref.update({'items': next.map((e) => e.toMap()).toList()});
  }

  /// Update the qty of the item at [index]. Pass qty <= 0 to remove the row.
  static Future<void> setItemQuantity(
      String orderId, int index, int quantity) async {
    final ref = _tableOrdersCol().doc(orderId);
    final snap = await ref.get();
    if (!snap.exists) return;
    final order = TableOrder.fromFirestore(snap.data()!, snap.id);
    if (index < 0 || index >= order.items.length) return;

    final next = [...order.items];
    if (quantity <= 0) {
      next.removeAt(index);
    } else {
      next[index] = next[index].copyWith(quantity: quantity);
    }
    await ref.update({'items': next.map((e) => e.toMap()).toList()});
  }

  /// Close the tab: create a matching Sale, deduct stock, free the table.
  /// Returns the new Sale id. Throws if the tab is empty.
  static Future<String> closeOrder({
    required TableOrder order,
    required double paid,
    required double discount,
    required PaymentMethod paymentMethod,
  }) async {
    if (order.items.isEmpty) {
      throw StateError('ไม่มีรายการในออเดอร์');
    }

    final subtotal =
        order.items.fold<double>(0, (s, i) => s + i.subtotal);
    final total = subtotal - discount;
    final change =
        paymentMethod == PaymentMethod.cash ? (paid - total) : 0.0;

    final saleItems = order.items
        .map((i) => SaleItem(
              productId: i.productId,
              productName: i.productName,
              price: i.price,
              costPrice: i.costPrice,
              quantity: i.quantity,
              subtotal: i.subtotal,
            ))
        .toList();

    final sale = Sale(
      id: '',
      items: saleItems,
      total: total,
      discount: discount,
      paid: paid,
      change: change,
      createdAt: DateTime.now(),
      paymentMethod: paymentMethod,
      customerName: 'โต๊ะ ${order.tableName}',
    );

    final batch = FirebaseFirestore.instance.batch();

    final saleRef = _salesCol().doc();
    batch.set(saleRef, sale.toFirestore());

    // Deduct stock for any items that track inventory. Recipe-style menu
    // items typically have stock = 9999; that's fine — decrement still
    // works, just won't ever go low.
    for (final item in order.items) {
      batch.update(_productsCol().doc(item.productId),
          {'stock': FieldValue.increment(-item.quantity)});
    }

    // Mark tab closed (kept in history rather than deleted, so we can
    // trace the order timeline later).
    batch.update(_tableOrdersCol().doc(order.id), {
      'status': TableOrderStatus.closed.name,
      'closedAt': Timestamp.now(),
      'saleId': saleRef.id,
    });

    // Free the table.
    batch.update(_tablesCol().doc(order.tableId), {
      'status': TableStatus.available.name,
      'currentOrderId': FieldValue.delete(),
    });

    await batch.commit();
    return saleRef.id;
  }

  /// Void the tab without creating a Sale (mistakes, walkouts). Frees the
  /// table; does NOT touch stock.
  static Future<void> cancelOrder(TableOrder order) async {
    final batch = FirebaseFirestore.instance.batch();
    batch.update(_tableOrdersCol().doc(order.id), {
      'status': TableOrderStatus.cancelled.name,
      'closedAt': Timestamp.now(),
    });
    batch.update(_tablesCol().doc(order.tableId), {
      'status': TableStatus.available.name,
      'currentOrderId': FieldValue.delete(),
    });
    await batch.commit();
  }

  // ─────────────────── Helpers for the order screen ───────────────────

  /// Build a [TableOrderItem] from a [Product] — the picker passes Products
  /// in, this normalizes them onto the lighter line-item shape.
  static TableOrderItem itemFromProduct(Product product, {int quantity = 1}) {
    return TableOrderItem(
      productId: product.id,
      productName: product.name,
      price: product.price,
      costPrice: product.costPrice,
      quantity: quantity,
    );
  }
}
