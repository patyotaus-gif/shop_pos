import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/models/product.dart';
import 'package:shop_pos/services/product_service.dart';
import 'package:shop_pos/widgets/product_category_field.dart';

void main() {
  Future<void> openAddCategory(WidgetTester tester) async {
    expect(find.widgetWithText(TextButton, 'เพิ่มหมวดหมู่'), findsNothing);
    await tester.tap(find.byType(DropdownButtonFormField<Object>));
    await tester.pumpAndSettle();
    final action =
        find.byKey(const ValueKey('add-category-menu')).hitTestable();
    expect(action, findsOneWidget);
    await tester.tap(action);
    await tester.pumpAndSettle();
  }

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
    await openAddCategory(tester);
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
    await tester.tap(find.byType(DropdownButtonFormField<Object>));
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
    await openAddCategory(tester);
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
    expect(find.text('ยังไม่มีหมวดหมู่ แตะช่องด้านบนแล้วเลือกเพิ่มหมวดหมู่'),
        findsOneWidget);
    await tester.tap(find.byType(DropdownButtonFormField<Object>));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('add-category-menu')).hitTestable());
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
    await openAddCategory(tester);
    await tester.enterText(find.byType(TextFormField), 'cancelled');
    await tester.tap(find.text('ยกเลิก'));
    await tester.pumpAndSettle();
    expect(selected, isNull);
    await openAddCategory(tester);
    await tester.enterText(find.byType(TextFormField), ' coffee ');
    await tester.tap(find.text('เพิ่มและเลือก'));
    await tester.pumpAndSettle();
    expect(selected, 'Coffee');
    final field = tester.widget<DropdownButtonFormField<Object>>(
        find.byType(DropdownButtonFormField<Object>));
    expect(field.initialValue, 'Coffee');
    expect(tester.takeException(), isNull);
  });

  for (final initial in ['', 'ขนม']) {
    testWidgets('phone dropdown can add and cancel with initial "$initial"',
        (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = const FakeViewPadding(bottom: 48);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewInsets);
      final form = GlobalKey<FormState>();
      final changes = <String>[];
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 220, 16, 16),
                child: Form(
                  key: form,
                  child: ProductCategoryField(
                    initialValue: initial,
                    categories: const ['ขนม', 'อาหาร'],
                    onChanged: changes.add,
                  ),
                ),
              ),
            ),
          ),
        ),
      ));
      Future<void> openAdd() async {
        await tester.tap(find.byType(DropdownButtonFormField<Object>));
        await tester.pumpAndSettle();
        final action =
            find.byKey(const ValueKey('add-category-menu')).hitTestable();
        expect(action, findsOneWidget);
        expect(tester.getTopLeft(action).dy,
            greaterThan(tester.getBottomLeft(find.text('อาหาร').last).dy));
        await tester.tap(action);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        expect(changes, isEmpty);
      }

      await openAdd();
      await tester.tap(find.text('ยกเลิก'));
      await tester.pumpAndSettle();
      expect(changes, isEmpty);
      expect(form.currentState!.validate(), initial.isNotEmpty);
      await tester.pumpAndSettle();
      await openAdd();
      tester.view.viewInsets = const FakeViewPadding(bottom: 240);
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), 'เครื่องดื่ม');
      await tester.ensureVisible(find.text('เพิ่มและเลือก'));
      await tester.tap(find.text('เพิ่มและเลือก'));
      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      expect(changes, ['เครื่องดื่ม']);
      expect(form.currentState!.validate(), isTrue);
      expect(tester.takeException(), isNull);
    });
  }
}
