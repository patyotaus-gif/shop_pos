import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/models/product.dart';
import 'package:shop_pos/models/sale.dart';
import 'package:shop_pos/screens/buy_get_screen.dart';
import 'package:shop_pos/services/buy_get_service.dart';
import 'package:shop_pos/services/sale_service.dart';

void main() {
  const product = Product(
      id: 'tea',
      name: 'ชาเขียว',
      barcode: '',
      price: 50,
      costPrice: 10,
      stock: 20);
  const gift = Product(
      id: 'cake', name: 'เค้ก', barcode: '', price: 20, costPrice: 5, stock: 2);
  for (final width in [320.0, 820.0]) {
    testWidgets(
        'buy/get editor validates limits and same/cross product at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 950);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Map<String, dynamic>? saved;
      await tester.pumpWidget(MaterialApp(
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(1.3)),
              child: child!),
          home: Scaffold(
              body: Builder(
                  builder: (context) => TextButton(
                      onPressed: () => showDialog(
                          context: context,
                          builder: (_) => BuyGetEditor(
                              product: product,
                              products: const [product, gift],
                              onSave: (data) async {
                                saved = data;
                              })),
                      child: const Text('open'))))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), '0');
      await tester.tap(find.text('บันทึก'));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      await tester.enterText(fields.at(0), '2');
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('เค้ก').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('บันทึก'));
      await tester.pumpAndSettle();
      expect(saved!['buyProductId'], 'tea');
      expect(saved!['giftProductId'], 'cake');
      expect(saved!['buyQuantity'], 2);
      expect(saved!['giftQuantity'], 1);
      expect(saved!['maxSets'], 1);
      expect(
          DateTime.fromMillisecondsSinceEpoch(saved!['endsAt'], isUtc: true)
              .add(const Duration(hours: 7))
              .hour,
          23);
      expect(tester.takeException(), isNull);
    });
  }
  test(
      'owner POS gift stock, replay, coupon allocation, cost and immutable receipt snapshot',
      () async {
    final db = FakeFirebaseFirestore();
    final ref = db.collection('shops').doc('s');
    await ref.collection('products').doc('tea').set(product.toFirestore());
    await ref.collection('products').doc('cake').set(gift.toFirestore());
    final promo = ref.collection('buyGetPromotions').doc('tea');
    await promo.set({
      'active': true,
      'revision': 'r1',
      'buyQuantity': 2,
      'giftQuantity': 1,
      'maxSets': 2,
      'giftProductId': 'cake',
      'endsAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: 1)))
    });
    const paid = SaleItem(
        productId: 'tea',
        productName: 'ชาเขียว',
        price: 50,
        costPrice: 10,
        quantity: 2,
        subtotal: 100);
    final quote =
        await db.runTransaction((tx) => BuyGetService.quote(tx, ref, [paid]));
    expect(quote.single['quantity'], 1);
    final sale = Sale(
        id: 's1',
        items: [
          paid,
          const SaleItem(
              productId: 'cake',
              productName: 'ของแถม: เค้ก',
              price: 0,
              costPrice: 5,
              quantity: 1,
              subtotal: 0,
              isGift: true)
        ],
        buyGet: quote,
        total: 90,
        discount: 10,
        paid: 100,
        change: 10,
        createdAt: DateTime.now());
    final saved = await SaleService.commitSale(ref, sale);
    expect(saved.items.last.isGift, true);
    expect(saved.items.last.profit, -5);
    expect(saved.itemNetRevenue, [90, 0]);
    expect(saved.itemsSubtotal, 100);
    expect(
        (await ref.collection('products').doc('cake').get()).data()!['stock'],
        1);
    await promo.update({'active': false});
    await SaleService.commitSale(ref, sale);
    expect(
        (await ref.collection('products').doc('cake').get()).data()!['stock'],
        1);
    final changed = Sale.fromFirestore({...sale.toFirestore()}, 's2');
    await expectLater(SaleService.commitSale(ref, changed), throwsStateError);
    expect((await ref.collection('sales').get()).size, 1);
  });
  test(
      'same product gift cannot bypass reserved inventory and recipe gift cannot overdraw ingredients',
      () async {
    final db = FakeFirebaseFirestore();
    final shop = db.collection('shops').doc('s');
    await shop
        .collection('products')
        .doc('tea')
        .set({...product.toFirestore(), 'stock': 2});
    await shop.collection('buyGetPromotions').doc('tea').set({
      'active': true,
      'revision': 'r',
      'buyQuantity': 2,
      'giftQuantity': 1,
      'maxSets': 1,
      'giftProductId': 'tea',
      'endsAt': Timestamp.fromDate(DateTime.now().add(const Duration(days: 1)))
    });
    const paid = SaleItem(
        productId: 'tea',
        productName: 'ชา',
        price: 50,
        quantity: 2,
        subtotal: 100);
    final quote =
        await db.runTransaction((tx) => BuyGetService.quote(tx, shop, [paid]));
    final sale = Sale(
        id: 's1',
        items: [
          paid,
          const SaleItem(
              productId: 'tea',
              productName: 'ของแถม: ชา',
              price: 0,
              quantity: 1,
              subtotal: 0,
              isGift: true)
        ],
        buyGet: quote,
        total: 100,
        discount: 0,
        paid: 100,
        change: 0,
        createdAt: DateTime.now());
    await expectLater(SaleService.commitSale(shop, sale), throwsStateError);
    expect((await shop.collection('sales').get()).size, 0);
    await shop.collection('products').doc('tea').update({
      'stockMode': 'recipe',
      'recipe': [
        {'ingredientId': 'leaf', 'qty': 1}
      ]
    });
    await shop.collection('ingredients').doc('leaf').set({'stock': 2});
    await expectLater(SaleService.commitSale(shop, sale), throwsStateError);
    expect(
        (await shop.collection('ingredients').doc('leaf').get())
            .data()!['stock'],
        2);
  });
}
