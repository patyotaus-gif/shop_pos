import 'package:shop_pos/theme/pokpok_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/models/cart_item.dart';
import 'package:shop_pos/models/product.dart';
import 'package:shop_pos/widgets/cart_item_tile.dart';

void main() {
  const name = 'ข้าวกะเพราหมูสับไข่ดาวพิเศษ';
  const product = Product(
      id: 'p',
      name: name,
      barcode: '',
      price: 65,
      stock: 100,
      imagePath: '/missing-test-image.jpg');
  for (final width in [296.0, 356.0]) {
    testWidgets('cart name retains usable width at $width with large text',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
          theme: PokpokTheme.light(),
          home: Scaffold(
              body: MediaQuery(
                  data:
                      const MediaQueryData(textScaler: TextScaler.linear(1.5)),
                  child: Align(
                      alignment: Alignment.topLeft,
                      child: SizedBox(
                          width: width,
                          child: CartItemTile(
                              item: const CartItem(product: product),
                              onRemove: () {},
                              onQtyChanged: (_) {})))))));
      await tester.pumpAndSettle();
      expect(tester.getSize(find.text(name)).width, greaterThan(200));
      expect(tester.getTopLeft(find.byTooltip('เพิ่มจำนวน')).dy,
          greaterThan(tester.getBottomLeft(find.text(name)).dy));
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('quantity controls, validation and delete still work',
      (tester) async {
    int? quantity;
    var removed = false;
    await tester.pumpWidget(MaterialApp(
        theme: PokpokTheme.light(),
        home: Scaffold(
            body: CartItemTile(
                item: const CartItem(product: product, quantity: 2),
                onRemove: () => removed = true,
                onQtyChanged: (value) => quantity = value))));
    await tester.tap(find.byTooltip('เพิ่มจำนวน'));
    expect(quantity, 3);
    await tester.tap(find.byTooltip('ลดจำนวน'));
    expect(quantity, 1);
    await tester.tap(find.text('2'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '0');
    await tester.tap(find.text('ตกลง'));
    await tester.pumpAndSettle();
    expect(find.text('กรอกจำนวนเต็มตั้งแต่ 1 ขึ้นไป'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '8');
    await tester.tap(find.text('ตกลง'));
    await tester.pumpAndSettle();
    expect(quantity, 8);
    await tester.tap(find.byTooltip('ลบรายการ'));
    expect(removed, isTrue);
  });
}
