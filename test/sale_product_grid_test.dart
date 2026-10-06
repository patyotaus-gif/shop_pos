import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/models/product.dart';
import 'package:shop_pos/widgets/sale_product_grid.dart';

const product = Product(
    id: 'rice',
    name: 'ข้าวกะเพราหมูสับไข่ดาวพิเศษ',
    barcode: '',
    price: 70,
    salePrice: 55,
    stock: 10);

void main() {
  testWidgets(
      'phone and tablet catalogs stay compact with large text and remain tappable',
      (tester) async {
    var selected = 0;
    addTearDown(() => tester.view.resetPhysicalSize());
    addTearDown(() => tester.view.resetDevicePixelRatio());
    tester.view.devicePixelRatio = 1;
    for (final width in [320.0, 390.0, 600.0, 800.0, 1280.0]) {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.physicalSize = Size(width, 800);
      await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
        data: MediaQueryData(
            size: Size(width, 800), textScaler: const TextScaler.linear(2)),
        child: Scaffold(
            body: SaleProductGrid(
                itemCount: 30,
                itemBuilder: (_, i) => SaleProductCard(
                    product: product, onTap: () => selected++))),
      )));
      await tester.pump();
      expect(tester.takeException(), isNull);
      final cards = find.byType(SaleProductCard);
      expect(tester.getSize(cards.first).width, lessThanOrEqualTo(200));
      expect(
          tester.getTopLeft(cards.at(1)).dy, tester.getTopLeft(cards.first).dy);
      final before = selected;
      await tester.tap(cards.first);
      expect(selected, before + 1);
      await tester.drag(find.byType(GridView), const Offset(0, -320));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('offline cards keep prepared price and disabled cards cannot add',
      (tester) async {
    var selected = 0;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SaleProductGrid(
      itemCount: 2,
      itemBuilder: (_, i) => SaleProductCard(
          product: product,
          showPromotion: false,
          onTap: i == 0 ? () => selected++ : null),
    ))));
    expect(find.text('฿70.00'), findsNWidgets(2));
    expect(find.text('฿55.00'), findsNothing);
    await tester.tap(find.byType(SaleProductCard).at(1));
    expect(selected, 0);
    await tester.tap(find.byType(SaleProductCard).first);
    expect(selected, 1);
  });
}
