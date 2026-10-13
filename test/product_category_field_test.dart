import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/models/product.dart';
import 'package:shop_pos/services/product_service.dart';
import 'package:shop_pos/widgets/product_category_field.dart';

void main() {
  testWidgets('new category is trimmed and can be reused after product save',
      (tester) async {
    var selected = 'ทั่วไป';
    final form = GlobalKey<FormState>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Form(
          key: form,
          child: ProductCategoryField(
            initialValue: selected,
            categories: const ['กาแฟ'],
            onChanged: (value) => selected = value,
          ),
        ),
      ),
    ));
    await tester.enterText(find.byType(TextFormField), '  ขนมอบ  ');
    expect(form.currentState!.validate(), isTrue);
    expect(selected, 'ขนมอบ');
    final product = Product(
        id: 'p',
        name: 'ครัวซองต์',
        barcode: '',
        price: 50,
        stock: 10,
        category: selected);
    final saved = Product.fromFirestore(product.toFirestore(), product.id);
    expect(ProductService.categoriesFor([saved, saved]), ['ขนมอบ']);
    await tester.enterText(find.byType(TextFormField), 'กา');
    await tester.pumpAndSettle();
    await tester.tap(find.text('กาแฟ'));
    await tester.pumpAndSettle();
    expect(selected, 'กาแฟ');
    expect(find.text('กาแฟ'), findsOneWidget);
  });

  testWidgets('rejects blank and reserved filter names; preserves old category',
      (tester) async {
    final form = GlobalKey<FormState>();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Form(
          key: form,
          child: ProductCategoryField(
            initialValue: 'หมวดเดิมที่ไม่มีในรายการ',
            categories: const [],
            onChanged: (_) {},
          ),
        ),
      ),
    ));
    expect(form.currentState!.validate(), isTrue);
    expect(find.text('หมวดเดิมที่ไม่มีในรายการ'), findsOneWidget);
    for (final name in ['   ', 'ทั้งหมด']) {
      await tester.enterText(find.byType(TextFormField), name);
      expect(form.currentState!.validate(), isFalse);
    }
  });
}
