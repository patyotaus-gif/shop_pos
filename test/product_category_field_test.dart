import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/models/product.dart';
import 'package:shop_pos/services/product_service.dart';
import 'package:shop_pos/widgets/product_category_field.dart';

void main() {
  testWidgets('new category is trimmed and can be reused after product save',
      (tester) async {
    var selected = '';
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
    expect(find.text('กดเพื่อเลือกหมวดหมู่'), findsOneWidget);
    expect(find.byType(TextFormField), findsNothing);
    expect(form.currentState!.validate(), isFalse);
    await tester.tap(find.text('เพิ่มหมวดหมู่'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '  ขนมอบ  ');
    await tester.tap(find.text('เพิ่มและเลือก'));
    await tester.pumpAndSettle();
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
    await tester.tap(find.byType(DropdownButtonFormField<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('กาแฟ').last);
    await tester.pumpAndSettle();
    expect(selected, 'กาแฟ');
    expect(find.text('กาแฟ'), findsWidgets);
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
    expect(find.text('หมวดเดิมที่ไม่มีในรายการ'), findsWidgets);
    await tester.tap(find.text('เพิ่มหมวดหมู่'));
    await tester.pumpAndSettle();
    for (final name in ['   ', 'ทั้งหมด']) {
      await tester.enterText(find.byType(TextFormField), name);
      await tester.tap(find.text('เพิ่มและเลือก'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
    }
    await tester.tap(find.text('ยกเลิก'));
    await tester.pumpAndSettle();
    expect(form.currentState!.validate(), isTrue);
    expect(find.text('หมวดเดิมที่ไม่มีในรายการ'), findsWidgets);
  });

  testWidgets('empty shop can add a category on a small phone', (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    String? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: ProductCategoryField(
        initialValue: '',
        categories: const [],
        onChanged: (value) => selected = value,
      )),
    ));
    expect(find.text('ยังไม่มีหมวดหมู่ กดเพิ่มหมวดหมู่เพื่อเริ่มต้น'),
        findsOneWidget);
    await tester.tap(find.text('เพิ่มหมวดหมู่'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'เครื่องดื่ม');
    await tester.tap(find.text('เพิ่มและเลือก'));
    await tester.pumpAndSettle();
    expect(selected, 'เครื่องดื่ม');
    expect(find.text('เครื่องดื่ม'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'duplicate name selects existing category; cancellation does nothing',
      (tester) async {
    String? selected;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: ProductCategoryField(
        initialValue: '',
        categories: const ['Coffee', 'Coffee'],
        onChanged: (value) => selected = value,
      )),
    ));
    await tester.tap(find.text('เพิ่มหมวดหมู่'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), 'cancelled');
    await tester.tap(find.text('ยกเลิก'));
    await tester.pumpAndSettle();
    expect(selected, isNull);
    await tester.tap(find.text('เพิ่มหมวดหมู่'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), ' coffee ');
    await tester.tap(find.text('เพิ่มและเลือก'));
    await tester.pumpAndSettle();
    expect(selected, 'Coffee');
    final field = tester.widget<DropdownButtonFormField<String>>(
        find.byType(DropdownButtonFormField<String>));
    expect(field.initialValue, 'Coffee');
    expect(tester.takeException(), isNull);
  });
}
