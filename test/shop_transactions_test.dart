import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shop_pos/models/sale.dart';
import 'package:shop_pos/models/table_order.dart';
import 'package:shop_pos/models/restaurant_table.dart';
import 'package:shop_pos/services/sale_service.dart';
import 'package:shop_pos/services/table_service.dart';
import 'package:shop_pos/services/shop_database.dart';

void main() {
  late FakeFirebaseFirestore db;
  late DocumentReference<Map<String, dynamic>> shop;
  Sale sale({String id = 'sale-1', int quantity = 1, bool debt = false}) =>
      Sale(
          id: id,
          items: [
            SaleItem(
                productId: 'tea',
                productName: 'ชา',
                price: 20,
                quantity: quantity,
                subtotal: quantity * 20)
          ],
          total: quantity * 20,
          discount: 0,
          paid: debt ? 0 : quantity * 20,
          change: 0,
          createdAt: DateTime(2026, 9, 7),
          isDebt: debt,
          customerName: debt ? 'ลูกค้าทดสอบ' : null);
  Future<TableOrder> readOrder(String id) async {
    final snap = await shop.collection('tableOrders').doc(id).get();
    return TableOrder.fromFirestore(snap.data()!, id);
  }

  Future<String> open() async {
    final table = RestaurantTable(
        id: 'one', name: '1', capacity: 2, createdAt: DateTime(2026));
    await shop.collection('tables').doc('one').set(table.toFirestore());
    return TableService.openOrder(table);
  }

  const dish = TableOrderItem(
      productId: 'tea', productName: 'ชา', price: 20, quantity: 1);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    db = FakeFirebaseFirestore();
    shop = db.collection('shops').doc('test-shop');
    ShopDatabase.overrideShop = shop;
    await shop.set({'tier': 'restaurant'});
    await shop
        .collection('products')
        .doc('tea')
        .set({'name': 'ชา', 'stock': 5});
  });
  tearDown(() => ShopDatabase.overrideShop = null);

  test('new sale serializer includes explicit non-refunded state', () {
    expect(sale().toFirestore()['isRefunded'], isFalse);
    final legacy = sale().toFirestore()..remove('isRefunded');
    expect(
        Sale.fromFirestore(legacy, 'old').toFirestore()['isRefunded'], isFalse);
  });

  test(
      'uncommitted legacy pending bill recovers with original id and one stock deduction',
      () async {
    final draft = sale();
    final prefs = await SharedPreferences.getInstance();
    final stored = {
      ...draft.toFirestore(),
      'id': draft.id,
      'createdAt': draft.createdAt.millisecondsSinceEpoch,
    }..remove('isRefunded');
    await prefs.setString('pending-checkout-test-shop', jsonEncode(stored));
    final result = await SaleService.resumeCheckout();
    expect(result.id, draft.id);
    expect(await SaleService.pendingCheckout(), isNull);
    final saved = await shop.collection('sales').doc(draft.id).get();
    expect(saved.data()!['isRefunded'], isFalse);
    expect(saved.data()!['total'], 20);
    await SaleService.commitSale(shop, draft);
    expect(
        (await shop.collection('products').doc('tea').get()).data()!['stock'],
        4);
    expect((await shop.collection('sales').get()).docs.length, 1);
    expect((await shop.collection('moneyMovements').get()).docs.length, 1);
  });

  test('recipe checkout consumes ingredients once and protects online holds',
      () async {
    await shop.collection('products').doc('tea').set({
      'name': 'ชา',
      'stock': 0,
      'stockMode': 'recipe',
      'recipe': [
        {'ingredientId': 'milk', 'qty': 1}
      ]
    });
    await shop.collection('ingredients').doc('milk').set({'stock': 5});
    await shop.collection('inventoryControl').doc('online').set({
      'ingredients': {'milk': 4}
    });
    await expectLater(
        SaleService.commitSale(shop, sale(quantity: 2)), throwsStateError);
    await SaleService.commitSale(shop, sale());
    await SaleService.commitSale(shop, sale());
    expect(
        (await shop.collection('ingredients').doc('milk').get())
            .data()!['stock'],
        4);
    final recorded =
        (await shop.collection('sales').doc('sale-1').get()).data()!;
    expect(recorded['ingredientsDeducted'], true);
    expect(recorded['ingredientUsage'], {'milk': 1.0});
    await expectLater(
        SaleService.commitSale(shop, sale(id: 'second')), throwsStateError);
  });

  test('counter checkout preserves stock held by online customers', () async {
    await shop.collection('inventoryControl').doc('online').set({
      'products': {'tea': 5}
    });
    await expectLater(SaleService.commitSale(shop, sale()), throwsStateError);
    expect((await shop.collection('sales').get()).docs, isEmpty);
    expect(
        (await shop.collection('products').doc('tea').get()).data()!['stock'],
        5);
    await shop.collection('inventoryControl').doc('online').set({
      'products': {'tea': 4}
    });
    await SaleService.commitSale(shop, sale());
    expect(
        (await shop.collection('products').doc('tea').get()).data()!['stock'],
        4);
  });

  test('daily report includes the final fractional second, excludes next day',
      () async {
    final end = DateTime(2026, 10, 4, 23, 59, 59);
    for (final entry in {
      'last': end.add(const Duration(milliseconds: 999)),
      'next': DateTime(2026, 10, 5),
      'previous': DateTime(2026, 10, 3, 23, 59, 59),
    }.entries) {
      await shop.collection('sales').doc(entry.key).set({
        ...sale(id: entry.key).toFirestore(),
        'createdAt': Timestamp.fromDate(entry.value),
      });
    }
    final rows =
        await SaleService.watchByRange(DateTime(2026, 10, 4), end).first;
    expect(rows.map((s) => s.id), ['last']);
  });

  test('replaying checkout deducts once, allocates one receipt and one debt',
      () async {
    final draft = sale(debt: true);
    final first = await SaleService.commitSale(shop, draft);
    final second = await SaleService.commitSale(shop, draft);
    expect(first.id, second.id);
    expect(first.receiptNo, second.receiptNo);
    expect((await shop.collection('sales').get()).docs.length, 1);
    expect((await shop.collection('debts').get()).docs.length, 1);
    expect(
        (await shop.collection('products').doc('tea').get()).data()!['stock'],
        4);
    expect(
        (await shop.collection('counters').doc('receipt').get()).data()!['seq'],
        1);
  });
  test('stock is revalidated against server state before writing a sale',
      () async {
    await SaleService.commitSale(shop, sale(quantity: 5));
    await expectLater(
        SaleService.commitSale(shop, sale(id: 'second')), throwsStateError);
    expect((await shop.collection('sales').get()).docs.length, 1);
    expect(
        (await shop.collection('products').doc('tea').get()).data()!['stock'],
        0);
  });
  test('recipe checkout does not decrement a second counted product stock',
      () async {
    await shop
        .collection('products')
        .doc('tea')
        .update({'stockMode': 'recipe', 'stock': 0});
    await SaleService.commitSale(shop, sale());
    expect(
        (await shop.collection('products').doc('tea').get()).data()!['stock'],
        0);
    expect(
        (await shop.collection('sales').doc('sale-1').get())
            .data()!['stockDeducted'],
        isEmpty);
  });
  test('cancelling prepared food records waste once without inventing a sale',
      () async {
    final id = await open();
    await shop.collection('products').doc('tea').update({
      'stockMode': 'recipe',
      'recipe': [
        {'ingredientId': 'leaf', 'qty': 2}
      ]
    });
    await shop.collection('ingredients').doc('leaf').set({'stock': 10});
    await shop.collection('tableOrders').doc(id).update({
      'items': [dish.copyWith(kitchenStatus: KitchenStatus.sent).toMap()]
    });
    final order = await readOrder(id);
    await TableService.cancelOrder(order, reason: 'ลูกค้าไม่รับอาหาร');
    await TableService.cancelOrder(order, reason: 'ลูกค้าไม่รับอาหาร');
    expect(
        (await shop.collection('ingredients').doc('leaf').get())
            .data()!['stock'],
        8);
    expect((await shop.collection('inventoryWaste').get()).docs.length, 1);
    expect((await shop.collection('sales').get()).docs, isEmpty);
  });
  test('checkout records one immutable cash movement across retries', () async {
    await shop
        .collection('cashControl')
        .doc('current')
        .set({'sessionId': 'session'});
    await SaleService.commitSale(shop, sale());
    await SaleService.commitSale(shop, sale());
    final rows = await shop.collection('moneyMovements').get();
    expect(rows.docs.length, 1);
    expect(rows.docs.single.data()['amountMinor'], 2000);
    expect(rows.docs.single.data()['sessionId'], 'session');
  });
  test(
      'persisted unresolved checkout reuses a previously committed sale after restart',
      () async {
    final draft = sale();
    await SaleService.commitSale(shop, draft);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        'pending-checkout-test-shop',
        jsonEncode({
          ...draft.toFirestore(),
          'id': draft.id,
          'createdAt': draft.createdAt.millisecondsSinceEpoch
        }));
    expect((await SaleService.pendingCheckout())!.id, draft.id);
    final result = await SaleService.resumeCheckout();
    expect(result.id, draft.id);
    expect(await SaleService.pendingCheckout(), isNull);
    expect(
        (await shop.collection('products').doc('tea').get()).data()!['stock'],
        4);
  });
  test('loyalty points are credited once when retrying a sale', () async {
    await shop
        .collection('customers')
        .doc('customer')
        .set({'points': 0, 'totalSpent': 0});
    final draft = sale(quantity: 2);
    await SaleService.commitSale(shop, draft, loyaltyCustomerId: 'customer');
    await SaleService.commitSale(shop, draft, loyaltyCustomerId: 'customer');
    final customer =
        (await shop.collection('customers').doc('customer').get()).data()!;
    expect(customer['points'], 1);
    expect(customer['totalSpent'], 40);
  });
  test(
      'reordering a ready dish adds a new pending line without changing the ready line',
      () async {
    final id = await open();
    await TableService.addItem(id, dish);
    await TableService.sendToKitchen(id);
    final first = (await readOrder(id)).items.single;
    await TableService.markItemReady(id, first.id);
    await TableService.addItem(id, dish);
    final items = (await readOrder(id)).items;
    expect(items.length, 2);
    expect(items[0].id, first.id);
    expect(items[0].kitchenStatus, KitchenStatus.ready);
    expect(items[1].kitchenStatus, KitchenStatus.pending);
    expect(items[0].quantity, 1);
    expect(items[1].quantity, 1);
    await TableService.sendToKitchen(id);
    expect((await readOrder(id)).items[1].kitchenStatus, KitchenStatus.sent);
  });
  test('stable line IDs prevent stale edits targeting a different row',
      () async {
    final id = await open();
    await TableService.addItem(id, dish);
    await TableService.addItem(id, dish.copyWith(notes: 'หวานน้อย'));
    final initial = (await readOrder(id)).items;
    await TableService.setItemQuantity(id, initial[0].id, 0,
        expectedQuantity: 1);
    await expectLater(
        TableService.markItemReady(id, initial[0].id), throwsStateError);
    expect((await readOrder(id)).items.single.notes, 'หวานน้อย');
  });
  test(
      'closing the same table twice returns the same sale without double deduction',
      () async {
    final id = await open();
    await TableService.addItem(id, dish);
    final order = await readOrder(id);
    final first = await TableService.closeOrder(
        order: order, paid: 20, discount: 0, paymentMethod: PaymentMethod.cash);
    final second = await TableService.closeOrder(
        order: order, paid: 20, discount: 0, paymentMethod: PaymentMethod.cash);
    expect(first, second);
    expect((await shop.collection('sales').get()).docs.length, 1);
    expect(
        (await shop.collection('products').doc('tea').get()).data()!['stock'],
        4);
    await expectLater(TableService.addItem(id, dish), throwsStateError);
    await expectLater(TableService.cancelOrder(order), throwsStateError);
  });
  test('changed order cannot be closed with the old payment total', () async {
    final id = await open();
    await TableService.addItem(id, dish);
    final old = await readOrder(id);
    await TableService.addItem(id, dish);
    await expectLater(
        TableService.closeOrder(
            order: old,
            paid: 20,
            discount: 0,
            paymentMethod: PaymentMethod.cash),
        throwsStateError);
    expect((await shop.collection('sales').get()).docs, isEmpty);
  });
  test('legacy items get stable IDs which survive the first write', () async {
    final id = await open();
    await shop.collection('tableOrders').doc(id).update({
      'items': [dish.toMap(), dish.copyWith(notes: 'แยก').toMap()]
    });
    final initial = (await readOrder(id)).items;
    expect(initial[0].id, 'legacy-0');
    expect(initial[1].id, 'legacy-1');
    await TableService.setItemQuantity(id, initial[0].id, 0,
        expectedQuantity: 1);
    expect((await readOrder(id)).items.single.id, 'legacy-1');
  });
}
