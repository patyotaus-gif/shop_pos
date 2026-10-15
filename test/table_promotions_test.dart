import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/models/table_order.dart';
import 'package:shop_pos/services/shop_database.dart';
import 'package:shop_pos/services/table_service.dart';
import 'package:shop_pos/widgets/table_promotion_dialog.dart';

Map<String, dynamic> quote() => {
      'revision': 'r',
      'subtotalMinor': 12500,
      'totalMinor': 9900,
      'serviceMinor': 900,
      'discountMinor': 3500,
      'bundles': [
        {'name': 'ชุดชาเค้ก', 'sets': 1, 'discountMinor': 2500}
      ],
      'buyGet': [
        {'productName': 'เค้ก', 'quantity': 1}
      ],
      'coupon': {'code': 'SAVE10', 'discountMinor': 1000},
    };

void main() {
  for (final width in [320.0, 820.0]) {
    testWidgets('table promotions review, code changes and apply at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      var loads = 0;
      var applies = 0;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Builder(
                  builder: (context) => TextButton(
                      onPressed: () => showDialog<bool>(
                          context: context,
                          builder: (_) => TablePromotionDialog(
                              initialCode: 'SAVE10',
                              load: (code) async {
                                loads++;
                                return quote();
                              },
                              apply: (code, revision) async {
                                expect(code, 'SAVE10');
                                expect(revision, 'r');
                                applies++;
                              })),
                      child: const Text('open'))))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('ยอดชำระ ฿99.00'), findsOneWidget);
      expect(find.textContaining('ของแถม: เค้ก'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'save10');
      await tester.pump();
      expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
          isNull);
      await tester.tap(find.text('ตรวจโปรโมชั่น'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('ยืนยันยอดและของแถม'));
      await tester.pumpAndSettle();
      expect(applies, 1);
      expect(loads, 2);
      expect(find.byType(AlertDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('stale apply is visible and requires a new quote',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: TablePromotionDialog(
      load: (_) async => quote(),
      apply: (_, __) async => throw StateError('รายการเปลี่ยน กรุณาตรวจใหม่'),
    ))));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ยืนยันยอดและของแถม'));
    await tester.pumpAndSettle();
    expect(find.textContaining('รายการเปลี่ยน'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
        isNull);
    expect(tester.takeException(), isNull);
  });
  test(
      'gift survives kitchen edits, cannot be manually incremented, cancellation records its waste',
      () async {
    final db = FakeFirebaseFirestore();
    final shop = db.collection('shops').doc('s');
    ShopDatabase.overrideShop = shop;
    addTearDown(() => ShopDatabase.overrideShop = null);
    await shop
        .collection('products')
        .doc('cake')
        .set({'name': 'เค้ก', 'stock': 10, 'price': 25});
    await shop
        .collection('tables')
        .doc('t')
        .set({'currentOrderId': 'o', 'status': 'occupied'});
    final order = TableOrder(
        id: 'o',
        tableId: 't',
        tableName: 'T1',
        openedAt: DateTime.now(),
        promotion: {
          'lines': [],
          ...quote()
        },
        items: const [
          TableOrderItem(
              id: 'gift',
              productId: 'cake',
              productName: 'ของแถม: เค้ก',
              price: 0,
              quantity: 1,
              isGift: true,
              promotionId: 'tea')
        ]);
    final ref = shop.collection('tableOrders').doc('o');
    await ref.set(order.toFirestore());
    await expectLater(
        TableService.setItemQuantity('o', 'gift', 2, expectedQuantity: 1),
        throwsStateError);
    await TableService.sendToKitchen('o');
    var current = TableOrder.fromFirestore((await ref.get()).data()!, 'o');
    expect(current.items.single.isGift, true);
    expect(current.items.single.promotionId, 'tea');
    expect(current.items.single.kitchenStatus, KitchenStatus.sent);
    await TableService.markItemReady('o', 'gift');
    current = TableOrder.fromFirestore((await ref.get()).data()!, 'o');
    await TableService.cancelOrder(current,
        reason: 'ลูกค้ายกเลิก', consumePrepared: true);
    expect(
        (await shop.collection('products').doc('cake').get()).data()!['stock'],
        9);
    final waste =
        (await shop.collection('inventoryWaste').doc('table-o').get()).data()!;
    expect((waste['items'] as List).single['isGift'], true);
  });
  test(
      'changed quantity invalidates displayed promotion, gift does not merge into paid zero-price line',
      () {
    const paid = TableOrderItem(
        id: 'p', productId: 'cake', productName: 'Cake', price: 0, quantity: 1);
    const gift = TableOrderItem(
        id: 'g',
        productId: 'cake',
        productName: 'Cake',
        price: 0,
        quantity: 1,
        isGift: true,
        promotionId: 'tea');
    final lines = TableService.appendPending([paid], gift);
    expect(lines.length, 2);
    final data = {
      'tableId': 't',
      'tableName': 'T1',
      'openedAt': Timestamp.now(),
      'items': lines.map((i) => i.toMap()).toList(),
      'tablePromotion': {
        'lines': [
          {'id': 'p', 'productId': 'cake', 'quantity': 1, 'unitPrice': 0}
        ]
      }
    };
    expect(TableOrder.fromFirestore(data, 'o').promotionCurrent, true);
    (data['items'] as List).first['quantity'] = 2;
    expect(TableOrder.fromFirestore(data, 'o').promotionCurrent, false);
  });
}
