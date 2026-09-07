import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../models/order_modifier.dart';
import '../models/product.dart';
import '../models/restaurant_table.dart';
import '../models/sale.dart';
import '../models/table_order.dart';
import '../utils/receipt_number.dart';
import 'shop_database.dart';
import 'sale_service.dart';

/// Tables + their open tabs.
///
/// Tabs live in a separate `tableOrders` collection rather than overloading
/// `sales` with an `open` status — keeps Sale's "completed transaction"
/// semantics intact (reports, refunds, dashboards) and lets restaurant-only
/// fields (modifiers, kitchen status) grow on TableOrder without bloating
/// the retail Sale doc.
class TableService {
  static DocumentReference<Map<String, dynamic>> _shopDoc() =>
      ShopDatabase.shop;

  static CollectionReference<Map<String, dynamic>> _tablesCol() =>
      _shopDoc().collection('tables');

  static CollectionReference<Map<String, dynamic>> _tableOrdersCol() =>
      _shopDoc().collection('tableOrders');

  static CollectionReference<Map<String, dynamic>> _salesCol() =>
      _shopDoc().collection('sales');

  static CollectionReference<Map<String, dynamic>> _productsCol() =>
      _shopDoc().collection('products');

  // ───────────────────────── Tables CRUD ─────────────────────────

  static Stream<List<RestaurantTable>> watchTables() =>
      _tablesCol().orderBy('createdAt').snapshots().map((s) => s.docs
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

  /// Watch every open tab across all tables — used by the kitchen
  /// display to show all in-progress tickets in one place.
  static Stream<List<TableOrder>> watchOpenOrders() => _tableOrdersCol()
      .where('status', isEqualTo: 'open')
      .orderBy('openedAt')
      .snapshots()
      .map((s) =>
          s.docs.map((d) => TableOrder.fromFirestore(d.data(), d.id)).toList());

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
    final tableRef = _tablesCol().doc(table.id);
    final orderRef = _tableOrdersCol().doc();
    return _shopDoc().firestore.runTransaction<String>((tx) async {
      final current = await tx.get(tableRef);
      if (!current.exists) throw StateError('ไม่พบโต๊ะนี้');
      final openId = current.data()?['currentOrderId'] as String?;
      if (openId != null) return openId;
      final order = TableOrder(
          id: orderRef.id,
          tableId: table.id,
          tableName: table.name,
          items: const [],
          openedAt: DateTime.now());
      tx.set(orderRef, order.toFirestore());
      tx.update(tableRef,
          {'status': TableStatus.occupied.name, 'currentOrderId': orderRef.id});
      return orderRef.id;
    });
  }

  static Future<void> _edit(String orderId,
      List<TableOrderItem> Function(List<TableOrderItem>) edit) async {
    final ref = _tableOrdersCol().doc(orderId);
    await ref.firestore.runTransaction((tx) async {
      final snap = await tx.get(ref);
      if (!snap.exists) throw StateError('ไม่พบออเดอร์');
      final order = TableOrder.fromFirestore(snap.data()!, snap.id);
      if (order.status != TableOrderStatus.open) {
        throw StateError('บิลนี้ปิดหรือยกเลิกแล้ว กรุณาเปิดหน้าโต๊ะใหม่');
      }
      final next = edit(order.items);
      tx.update(ref, {'items': next.map((i) => i.toMap()).toList()});
    });
  }

  static List<TableOrderItem> appendPending(
      List<TableOrderItem> items, TableOrderItem item) {
    if (item.quantity <= 0) throw StateError('จำนวนต้องมากกว่าศูนย์');
    final index = items.indexWhere((i) =>
        i.kitchenStatus == KitchenStatus.pending &&
        i.productId == item.productId &&
        i.price == item.price &&
        i.notes == item.notes &&
        modifiersEqual(i.modifiers, item.modifiers));
    final next = [...items];
    if (index < 0) {
      next.add(item.copyWith(
          id: item.id.isEmpty ? const Uuid().v4() : item.id,
          kitchenStatus: KitchenStatus.pending));
    } else {
      next[index] =
          next[index].copyWith(quantity: next[index].quantity + item.quantity);
    }
    return next;
  }

  static Future<void> addItem(String orderId, TableOrderItem item) {
    final pending = item.copyWith(
        id: const Uuid().v4(), kitchenStatus: KitchenStatus.pending);
    return _edit(orderId, (items) => appendPending(items, pending));
  }

  static Future<void> setItemQuantity(
          String orderId, String itemId, int quantity,
          {required int expectedQuantity}) =>
      _edit(orderId, (items) {
        final index = items.indexWhere((i) => i.id == itemId);
        if (index < 0) {
          throw StateError('รายการนี้เปลี่ยนไปแล้ว กรุณาตรวจสอบออเดอร์');
        }
        final current = items[index];
        if (current.quantity != expectedQuantity) {
          throw StateError('จำนวนถูกเปลี่ยนจากอีกเครื่องแล้ว กรุณาตรวจสอบใหม่');
        }
        if (current.kitchenStatus != KitchenStatus.pending) {
          if (quantity > current.quantity) {
            return appendPending(
                items,
                current.copyWith(
                    id: const Uuid().v4(),
                    quantity: quantity - current.quantity,
                    kitchenStatus: KitchenStatus.pending));
          }
          throw StateError(
              'รายการส่งครัวแล้ว กรุณาประสานครัวก่อนยกเลิกหรือปรับลด');
        }
        final next = [...items];
        if (quantity <= 0) {
          next.removeAt(index);
        } else {
          next[index] = current.copyWith(quantity: quantity);
        }
        return next;
      });

  static Future<void> sendToKitchen(String orderId) => _edit(orderId, (items) {
        final now = DateTime.now();
        return items
            .map((i) => i.kitchenStatus == KitchenStatus.pending
                ? i.copyWith(
                    kitchenStatus: KitchenStatus.sent, sentToKitchenAt: now)
                : i)
            .toList();
      });

  static Future<void> markItemReady(String orderId, String itemId) =>
      _edit(orderId, (items) {
        final index = items.indexWhere((i) => i.id == itemId);
        if (index < 0) {
          throw StateError('รายการนี้เปลี่ยนไปแล้ว กรุณาตรวจสอบใหม่');
        }
        if (items[index].kitchenStatus == KitchenStatus.pending) {
          throw StateError('รายการนี้ยังไม่ได้ส่งครัว');
        }
        final next = [...items];
        next[index] = next[index].copyWith(
            kitchenStatus: KitchenStatus.ready, readyAt: DateTime.now());
        return next;
      });

  static String billingSignature(TableOrder order) => jsonEncode(order.items
      .map((i) => {
            'id': i.id,
            'productId': i.productId,
            'quantity': i.quantity,
            'price': i.price,
            'modifiers': i.modifiers.map((m) => m.toMap()).toList(),
          })
      .toList());

  /// Close the tab: create a matching Sale, deduct stock, free the table.
  /// Returns the new Sale id. Throws if the tab is empty.
  ///
  /// [serviceChargePercent] adds X% on top of the items subtotal. Read
  /// from settings by the caller — defaults to 0 when not configured.
  /// [splitCount] > 1 means the bill was split N ways at close; we record
  /// it on the Sale so the receipt can show the per-person figure but the
  /// full order stays as a single Sale doc (keeps reports honest).
  static Future<String> closeOrder({
    required TableOrder order,
    required double paid,
    required double discount,
    required PaymentMethod paymentMethod,
    double serviceChargePercent = 0,
    int splitCount = 1,
  }) async {
    final expected = order;
    final orderRef = _tableOrdersCol().doc(expected.id);
    final saleRef = _salesCol().doc('table-${expected.id}');
    final counterRef = _shopDoc().collection('counters').doc('receipt');
    return _shopDoc().firestore.runTransaction<String>((tx) async {
      final snap = await tx.get(orderRef);
      if (!snap.exists) throw StateError('ไม่พบออเดอร์');
      final order = TableOrder.fromFirestore(snap.data()!, snap.id);
      if (order.status == TableOrderStatus.closed && order.saleId != null) {
        return order.saleId!;
      }
      if (order.status != TableOrderStatus.open) {
        throw StateError('ออเดอร์นี้ยกเลิกแล้ว');
      }
      if (order.items.isEmpty) throw StateError('ไม่มีรายการในออเดอร์');
      if (billingSignature(order) != billingSignature(expected)) {
        throw StateError(
            'รายการเปลี่ยนระหว่างคิดเงิน กรุณาตรวจยอดและเงินที่รับก่อนยืนยันใหม่');
      }
      final tableRef = _tablesCol().doc(order.tableId);
      final table = await tx.get(tableRef);
      if (table.data()?['currentOrderId'] != order.id) {
        throw StateError('โต๊ะเปลี่ยนบิลแล้ว กรุณาเปิดหน้าโต๊ะใหม่');
      }
      final counterSnap = await tx.get(counterRef);
      final itemsSubtotal =
          order.items.fold<double>(0, (s, i) => s + i.subtotal);
      final serviceCharge = serviceChargePercent <= 0
          ? 0.0
          : (itemsSubtotal - discount) * (serviceChargePercent / 100);
      final total = itemsSubtotal - discount + serviceCharge;
      final change = paymentMethod == PaymentMethod.cash ? (paid - total) : 0.0;

      final saleItems = order.items
          .map((i) => SaleItem(
                productId: i.productId,
                productName: i.productName,
                price: i.price,
                costPrice: i.costPrice,
                quantity: i.quantity,
                subtotal: i.subtotal,
                modifiers: i.modifiers,
              ))
          .toList();

      final now = DateTime.now();
      final sale = Sale(
        id: '',
        items: saleItems,
        total: total,
        discount: discount,
        paid: paid,
        change: change,
        createdAt: now,
        paymentMethod: paymentMethod,
        customerName: 'โต๊ะ ${order.tableName}',
        serviceCharge: serviceCharge,
        splitCount: splitCount,
        tableName: order.tableName,
      );

      SaleService.validateSale(sale);
      if (!serviceChargePercent.isFinite ||
          serviceChargePercent < 0 ||
          splitCount < 1) {
        throw StateError('ค่าบริการหรือจำนวนคนไม่ถูกต้อง');
      }
      final todayKey = receiptDay(now);
      final data = counterSnap.data();
      final next = nextReceiptSeq(
          data?['day'] as String?, todayKey, (data?['seq'] ?? 0) as int);

      tx.set(saleRef, {
        ...sale.toFirestore(),
        'receiptNo': formatReceiptNo(next.day, next.seq),
      });
      for (final item in order.items) {
        tx.update(_productsCol().doc(item.productId),
            {'stock': FieldValue.increment(-item.quantity)});
      }
      tx.update(_tableOrdersCol().doc(order.id), {
        'status': TableOrderStatus.closed.name,
        'closedAt': Timestamp.now(),
        'saleId': saleRef.id,
      });
      tx.update(_tablesCol().doc(order.tableId), {
        'status': TableStatus.available.name,
        'currentOrderId': FieldValue.delete(),
      });
      tx.set(counterRef, {'day': next.day, 'seq': next.seq});
      return saleRef.id;
    });
  }

  /// Void the tab without creating a Sale (mistakes, walkouts). Frees the
  /// table; does NOT touch stock.
  static Future<void> cancelOrder(TableOrder order) async {
    final ref = _tableOrdersCol().doc(order.id);
    final tableRef = _tablesCol().doc(order.tableId);
    await ref.firestore.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final table = await tx.get(tableRef);
      if (!snap.exists) throw StateError('ไม่พบออเดอร์');
      final current = TableOrder.fromFirestore(snap.data()!, snap.id);
      if (current.status == TableOrderStatus.cancelled) return;
      if (current.status != TableOrderStatus.open) {
        throw StateError('บิลนี้ชำระแล้ว ไม่สามารถยกเลิกได้');
      }
      if (table.data()?['currentOrderId'] != order.id) {
        throw StateError('โต๊ะเปลี่ยนบิลแล้ว');
      }
      tx.update(ref, {
        'status': TableOrderStatus.cancelled.name,
        'closedAt': Timestamp.now()
      });
      tx.update(tableRef, {
        'status': TableStatus.available.name,
        'currentOrderId': FieldValue.delete()
      });
    });
  }

  // ─────────────────── Helpers for the order screen ───────────────────

  /// Build a [TableOrderItem] from a [Product] — the picker passes Products
  /// in, this normalizes them onto the lighter line-item shape.
  static TableOrderItem itemFromProduct(
    Product product, {
    int quantity = 1,
    List<OrderModifier> modifiers = const [],
    String? notes,
  }) {
    return TableOrderItem(
      id: const Uuid().v4(),
      productId: product.id,
      productName: product.name,
      price: product.effectivePrice,
      costPrice: product.costPrice,
      quantity: quantity,
      modifiers: modifiers,
      notes: notes,
    );
  }
}
