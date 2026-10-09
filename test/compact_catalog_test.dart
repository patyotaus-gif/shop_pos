import 'package:shop_pos/theme/pokpok_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/widgets/compact_catalog_button.dart';
import 'package:shop_pos/widgets/sale_product_grid.dart';
import 'package:shop_pos/models/product.dart';

void main() {
  testWidgets(
      'short portrait and landscape can open products, add and return to cart',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    for (final size in [const Size(320, 568), const Size(568, 320)]) {
      var selected = 0;
      tester.view.physicalSize = size;
      await tester.pumpWidget(MaterialApp(
          theme: PokpokTheme.light(),
          home: Scaffold(
              body: CompactCatalogButton(
                  catalog: (_) => SaleProductGrid(
                      itemCount: 20,
                      itemBuilder: (_, i) => SaleProductCard(
                          product: Product(
                              id: '$i',
                              name: 'สินค้า $i',
                              barcode: '',
                              price: 20,
                              stock: 5),
                          onTap: () => selected++))))));
      await tester.tap(find.text('เลือกสินค้า'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('สินค้า 0'));
      await tester.pump();
      expect(selected, 1);
      await tester.tap(find.text('ดูตะกร้า'));
      await tester.pumpAndSettle();
      expect(find.text('ดูตะกร้า'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
