import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shop_pos/models/product.dart';
import 'package:shop_pos/theme/pokpok_theme.dart';
import 'package:shop_pos/widgets/product_catalog.dart';
import 'package:shop_pos/widgets/product_image.dart';
import 'package:shop_pos/widgets/sale_product_grid.dart';

const products = [
  Product(
      id: 'tea',
      name: 'ชาเขียวขวดใหญ่ สูตรไม่เติมน้ำตาล',
      barcode: '12345',
      price: 30,
      salePrice: 25,
      stock: 3,
      category: 'เครื่องดื่ม'),
  Product(
      id: 'snack',
      name: 'ขนมอบกรอบ',
      barcode: '67890',
      price: 10,
      stock: 20,
      category: 'ขนม'),
];

Widget catalog(
        {ValueChanged<Product>? onEdit,
        ValueChanged<Product>? onStock,
        String preferenceKey = 'catalog:shop',
        bool inventory = true,
        double scale = 1}) =>
    MaterialApp(
      theme: PokpokTheme.light(),
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(scale)),
          child: child!),
      home: Scaffold(
          body: ProductCatalog(
        products: products,
        categories: const ['เครื่องดื่ม', 'ขนม'],
        preferenceKey: preferenceKey,
        showInventory: inventory,
        onEdit: onEdit ?? (_) {},
        onReceiveStock: onStock ?? (_) {},
      )),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'switch preserves search/category and edit/stock actions, restoring saved layout per shop',
      (tester) async {
    final edits = <String>[], stocks = <String>[];
    await tester.pumpWidget(catalog(
        onEdit: (p) => edits.add(p.id), onStock: (p) => stocks.add(p.id)));
    await tester.pumpAndSettle();
    expect(find.byType(SaleProductGrid), findsNothing);
    expect(find.byType(ProductImage), findsNWidgets(2));
    await tester.enterText(find.byType(TextField), '12345');
    await tester.tap(find.widgetWithText(ChoiceChip, 'เครื่องดื่ม'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('รูปภาพ'));
    await tester.pumpAndSettle();
    expect(find.byType(SaleProductCard), findsOneWidget);
    expect(find.text('ขนมอบกรอบ'), findsNothing);
    expect(find.text('฿25.00'), findsOneWidget);
    expect(find.text('สต็อก 3'), findsOneWidget);
    await tester.tap(find.byTooltip('รับสินค้าเข้า'));
    expect(stocks, ['tea']);
    expect(edits, isEmpty);
    await tester.tap(find.text(products.first.name));
    expect(edits, ['tea']);
    await tester.tap(find.text('รายการ'));
    await tester.pumpAndSettle();
    expect(find.byType(SaleProductGrid), findsNothing);
    expect(find.text('ขนมอบกรอบ'), findsNothing);
    expect(tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '12345');
    await tester.tap(find.text('รูปภาพ'));
    await tester.pumpAndSettle();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(catalog());
    await tester.pumpAndSettle();
    expect(find.byType(SaleProductGrid), findsOneWidget);
    await tester.pumpWidget(catalog(preferenceKey: 'catalog:other-shop'));
    await tester.pumpAndSettle();
    expect(find.byType(SaleProductGrid), findsNothing);
    await tester.pumpWidget(catalog());
    await tester.pumpAndSettle();
    expect(find.byType(SaleProductGrid), findsOneWidget);
  });

  testWidgets(
      'phone/tablet views support large text and cards remain compact; Solo hides stock actions',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final size in [
      const Size(320, 640),
      const Size(568, 320),
      const Size(1280, 800)
    ]) {
      await tester.pumpWidget(const SizedBox.shrink());
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = size;
      await tester.pumpWidget(catalog(scale: 2, inventory: false));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('รับสินค้าเข้า'), findsNothing);
      await tester.tap(find.text('รูปภาพ'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byTooltip('รับสินค้าเข้า'), findsNothing);
      expect(tester.getSize(find.byType(SaleProductCard).first).width,
          lessThanOrEqualTo(200));
      expect(tester.getTopLeft(find.byType(SaleProductCard).at(1)).dy,
          tester.getTopLeft(find.byType(SaleProductCard).first).dy);
    }
  });
}
