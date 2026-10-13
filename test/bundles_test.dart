import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/models/product.dart';
import 'package:shop_pos/models/order.dart';
import 'package:shop_pos/models/sale.dart';
import 'package:shop_pos/screens/bundles_screen.dart';
import 'package:shop_pos/services/sale_service.dart';
import 'package:shop_pos/widgets/order_summary_card.dart';

void main() {
  const tea = Product(
      id: 'tea', name: 'ชา', barcode: '', price: 50, stock: 20, costPrice: 10);
  const cake = Product(
      id: 'cake', name: 'ขนม', barcode: '', price: 25, stock: 10, costPrice: 5);
  final until = Timestamp.fromDate(DateTime.now().add(const Duration(days: 5)));
  Map<String, dynamic> config() => {
        'id': 'set',
        'name': 'ชาคู่ขนม',
        'revision': 'r1',
        'priceMinor': 10000,
        'maxSets': 2,
        'active': true,
        'endsAt': until,
        'components': [
          {'productId': 'cake', 'quantity': 1},
          {'productId': 'tea', 'quantity': 2}
        ]
      };
  Map<String, dynamic> quote() => {
        'id': 'set',
        'name': 'ชาคู่ขนม',
        'revision': 'r1',
        'sets': 1,
        'priceMinor': 10000,
        'discountMinor': 2500,
        'components': [
          {'productId': 'cake', 'quantity': 1, 'unitPriceMinor': 2500},
          {'productId': 'tea', 'quantity': 2, 'unitPriceMinor': 5000}
        ]
      };
  for (final width in [320.0, 820.0]) {
    testWidgets(
        'bundle editor at $width saves quantities and satang, rejects expensive set',
        (tester) async {
      tester.view.physicalSize = Size(width, 1000);
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
                          builder: (_) => BundleEditor(
                              products: const [tea, cake],
                              initial: config(),
                              onSave: (data) async {
                                saved = data;
                              })),
                      child: const Text('open'))))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      final price = find.widgetWithText(TextFormField, 'ราคาชุด (บาท)');
      await tester.ensureVisible(price);
      await tester.enterText(price, '125');
      await tester.tap(find.text('บันทึกชุด'));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      await tester.ensureVisible(price);
      await tester.enterText(price, '99.50');
      await tester.tap(find.text('บันทึกชุด'));
      await tester.pumpAndSettle();
      expect(saved!['priceMinor'], 9950);
      expect(saved!['maxSets'], 2);
      expect(saved!['components'], [
        {'productId': 'cake', 'quantity': 1},
        {'productId': 'tea', 'quantity': 2}
      ]);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('order card separates bundle savings from coupon amount',
      (tester) async {
    final order = ShopOrder.fromFirestore({
      'customerName': 'ทดสอบ',
      'items': <Map<String, dynamic>>[],
      'total': 90,
      'finalAmount': 90.31,
      'discount': 35,
      'bundleDiscount': 25,
      'coupon': {'code': 'SAVE10'},
      'bundles': [quote()],
    }, 'order');
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: OrderSummaryCard(
      order: order,
      onTicket: () {},
      onSlip: () {},
    ))));
    expect(find.text('ชาคู่ขนม × 1 ชุด ลด ฿25.00'), findsOneWidget);
    expect(find.text('คูปอง SAVE10 ลด ฿10.00'), findsOneWidget);
    expect(find.text('฿90.31'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  Sale draft(String id) => Sale(
      id: id,
      items: [
        SaleItem(
            productId: 'tea',
            productName: 'ชา',
            price: 50,
            quantity: 2,
            subtotal: 100,
            costPrice: 10),
        SaleItem(
            productId: 'cake',
            productName: 'ขนม',
            price: 25,
            quantity: 1,
            subtotal: 25,
            costPrice: 5),
        SaleItem(
            productId: 'extra',
            productName: 'อื่นๆ',
            price: 100,
            quantity: 1,
            subtotal: 100,
            costPrice: 10),
      ],
      total: 190,
      discount: 35,
      bundleDiscount: 25,
      bundles: [quote()],
      paid: 200,
      change: 10,
      createdAt: DateTime.now());
  test(
      'owner bundle checkout preserves components, exact net revenue, ledger and idempotent replay',
      () async {
    final db = FakeFirebaseFirestore(),
        shop = db.collection('shops').doc('owner');
    await shop.collection('products').doc('tea').set(tea.toFirestore());
    await shop.collection('products').doc('cake').set(cake.toFirestore());
    await shop
        .collection('products')
        .doc('extra')
        .set({'name': 'อื่นๆ', 'price': 100, 'stock': 10});
    final ref = shop.collection('promotionSettings').doc('bundles');
    await ref.set({
      'bundles': [config()]
    });
    final saved = await SaleService.commitSale(shop, draft('sale'));
    expect(saved.itemsSubtotal, 225);
    expect(saved.bundleDiscount, 25);
    expect(saved.itemNetRevenue, [76, 19, 95]);
    expect(
        (await shop.collection('products').doc('tea').get()).data()!['stock'],
        18);
    expect((await shop.collection('moneyMovements').get()).size, 1);
    await ref.set({'bundles': []});
    await SaleService.commitSale(shop, draft('sale'));
    expect(
        (await shop.collection('products').doc('tea').get()).data()!['stock'],
        18);
    await expectLater(
        SaleService.commitSale(shop, draft('new')), throwsStateError);
    expect((await shop.collection('sales').get()).size, 1);
  });
  test(
      'owner stale price or missing bundle snapshot cannot silently change amount',
      () async {
    final db = FakeFirebaseFirestore(),
        shop = db.collection('shops').doc('owner');
    await shop
        .collection('products')
        .doc('tea')
        .set({...tea.toFirestore(), 'price': 60});
    await shop.collection('products').doc('cake').set(cake.toFirestore());
    await shop.collection('promotionSettings').doc('bundles').set({
      'bundles': [config()]
    });
    await expectLater(
        SaleService.commitSale(shop, draft('sale')), throwsStateError);
    expect((await shop.collection('sales').get()).size, 0);
    expect(
        (await shop.collection('products').doc('tea').get()).data()!['stock'],
        20);
  });
}
