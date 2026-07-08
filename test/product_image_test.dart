import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/models/product.dart';
import 'package:shop_pos/widgets/product_image.dart';

Product _p({String? imagePath, String? imageUrl}) => Product(
      id: 'p1',
      name: 'มาม่า',
      barcode: '885',
      price: 10,
      stock: 5,
      imagePath: imagePath,
      imageUrl: imageUrl,
    );

void main() {
  Future<void> pump(WidgetTester tester, Product p) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: ProductImage(product: p, width: 44, height: 44)),
    ));
  }

  testWidgets('stale local path falls back to network imageUrl',
      (tester) async {
    // imagePath from another device — file does not exist here. The cloud
    // imageUrl must be tried instead of giving up with the placeholder.
    await tester.runAsync(() async {
      await pump(
        tester,
        _p(
          imagePath: '/nonexistent/definitely_missing.jpg',
          imageUrl: 'https://example.com/p.jpg',
        ),
      );
      // Let the file read fail and errorBuilder swap in the network image.
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(
      find.byWidgetPredicate((w) => w is Image && w.image is NetworkImage),
      findsOneWidget,
    );
  });

  testWidgets('no image data shows placeholder icon', (tester) async {
    await pump(tester, _p());
    expect(find.byIcon(Icons.inventory_2_outlined), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('stale local path and no url shows placeholder',
      (tester) async {
    await tester.runAsync(() async {
      await pump(tester, _p(imagePath: '/nonexistent/x.jpg'));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(find.byIcon(Icons.inventory_2_outlined), findsOneWidget);
  });
}
