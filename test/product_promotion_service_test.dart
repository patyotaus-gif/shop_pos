import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/models/product.dart';
import 'package:shop_pos/models/shop.dart';
import 'package:shop_pos/screens/sales_tools_screen.dart';
import 'package:shop_pos/services/product_service.dart';
import 'package:shop_pos/services/shop_database.dart';

const item =
    Product(id: 'tea', name: 'ชาเขียว', barcode: '', price: 50, stock: 12);

void main() {
  late FakeFirebaseFirestore db;
  setUp(() async {
    db = FakeFirebaseFirestore();
    ShopDatabase.overrideShop = db.collection('shops').doc('one');
    await ShopDatabase.shop
        .collection('products')
        .doc(item.id)
        .set(item.toFirestore());
    await db
        .collection('shops')
        .doc('two')
        .collection('products')
        .doc(item.id)
        .set(item.toFirestore());
  });
  tearDown(() => ShopDatabase.overrideShop = null);

  test('promotion updates only own shop price fields; details preserve it',
      () async {
    final ref = ShopDatabase.shop.collection('products').doc(item.id);
    await ref.update({'stock': 9});
    await ProductService.setPromotion(item,
        salePrice: 40, saleUntil: DateTime.now().add(const Duration(days: 1)));
    await ProductService.update(item.copyWith(name: 'ชื่อใหม่', stock: 9));
    var saved = (await ref.get()).data()!;
    expect(saved['salePrice'], 40);
    expect(saved['saleUntil'], isNotNull);
    expect(saved['stock'], 9);
    expect(
        (await db
                .collection('shops')
                .doc('two')
                .collection('products')
                .doc(item.id)
                .get())
            .data()!['salePrice'],
        isNull);
    await ProductService.setPinned(item.id, true);
    expect((await ref.get()).data()!['salePrice'], 40);
    await ProductService.setPromotion(item, salePrice: null);
    saved = (await ref.get()).data()!;
    expect(saved['salePrice'], isNull);
    expect(saved['saleUntil'], isNull);
    expect(saved['isPinned'], isTrue);
  });

  test('stale base price, missing product and invalid promotions reject writes',
      () async {
    final ref = ShopDatabase.shop.collection('products').doc(item.id);
    for (final price in [0.0, -1.0, 50.0, double.nan]) {
      await expectLater(ProductService.setPromotion(item, salePrice: price),
          throwsStateError);
    }
    await expectLater(
        ProductService.setPromotion(item,
            salePrice: 40, saleUntil: DateTime(2020)),
        throwsStateError);
    await ref.update({'price': 60});
    await expectLater(
        ProductService.setPromotion(item, salePrice: 40), throwsStateError);
    expect((await ref.get()).data()!['salePrice'], isNull);
    await ref.delete();
    await expectLater(
        ProductService.setPromotion(item, salePrice: 40), throwsStateError);
  });

  testWidgets(
      'tools opens products and can save a promotion through the service',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: SalesToolsScreen(shopType: ShopType.retail)));
    await tester.tap(find.text('โปรโมชั่นส่วนลด'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ตั้งโปรโมชั่น'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '35');
    await tester.tap(find.text('บันทึกโปรโมชั่น'));
    await tester.pumpAndSettle();
    expect(find.text('กำลังใช้โปรโมชั่น'), findsOneWidget);
    expect(
        (await ShopDatabase.shop.collection('products').doc(item.id).get())
            .data()!['salePrice'],
        35);
    expect(tester.takeException(), isNull);
  });
}
