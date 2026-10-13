import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/models/product.dart';
import 'package:shop_pos/services/product_service.dart';
import 'package:shop_pos/widgets/promotion_editor.dart';

const product = Product(
    id: 'tea',
    name: 'ชาเขียว',
    barcode: '',
    price: 50,
    stock: 12,
    salePrice: 40);

Future<void> openEditor(
  WidgetTester tester, {
  Product item = product,
  required Future<void> Function(double?, DateTime?) save,
  double width = 390,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(MaterialApp(
    builder: (context, child) => MediaQuery(
        data:
            MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(1.3)),
        child: child!),
    home: Scaffold(
        body: Builder(
            builder: (context) => TextButton(
                onPressed: () => showDialog<bool>(
                    context: context,
                    builder: (_) =>
                        PromotionEditor(product: item, onSave: save)),
                child: const Text('open')))),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  test('discounts round to satang and reject invalid or zero prices', () {
    expect(promotionalPrice(35, '15', percent: true), 29.75);
    expect(promotionalPrice(35, '29.756', percent: false), 29.76);
    for (final input in ['', 'NaN', 'Infinity', '-5', '0', '100']) {
      expect(promotionalPrice(35, input, percent: true), isNull);
    }
    expect(promotionalPrice(35, '35', percent: false), isNull);
    expect(promotionalPrice(.01, '50', percent: true), isNull);
  });

  test('editing product details leaves current promotion untouched', () {
    final current = product.toFirestore();
    current['salePrice'] = 30.0; // another device changed the promotion
    current
        .addAll(ProductService.detailsUpdate(product.copyWith(name: 'ชาใหม่')));
    expect(current['salePrice'], 30);
    expect(current['name'], 'ชาใหม่');
    expect(ProductService.detailsUpdate(product).containsKey('saleUntil'),
        isFalse);
  });

  for (final width in [320.0, 820.0]) {
    testWidgets('percentage preview and save work at width $width',
        (tester) async {
      double? saved;
      await openEditor(tester,
          width: width, save: (price, until) async => saved = price);
      await tester.tap(find.text('ลดเป็นเปอร์เซ็นต์'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextFormField), '20');
      await tester.pumpAndSettle();
      expect(find.textContaining('ลูกค้าจ่าย'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('บันทึกโปรโมชั่น'));
      await tester.pumpAndSettle();
      expect(saved, 40);
      expect(find.byType(PromotionEditor), findsNothing);
    });
  }

  testWidgets(
      'failed save stays open and cancelling promotion clears both fields',
      (tester) async {
    var fail = true;
    final saves = <List<Object?>>[];
    await openEditor(tester, save: (price, until) async {
      if (fail) throw StateError('ราคาสินค้าเปลี่ยนแล้ว');
      saves.add([price, until]);
    });
    await tester.tap(find.text('บันทึกโปรโมชั่น'));
    await tester.pumpAndSettle();
    expect(find.text('ราคาสินค้าเปลี่ยนแล้ว'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('ยกเลิกโปรโมชั่น'));
    await tester.pumpAndSettle();
    expect(saves, [
      [null, null]
    ]);
  });

  testWidgets('expired promotion cannot be saved until its date is changed',
      (tester) async {
    var calls = 0;
    await openEditor(tester, item: product.copyWith(saleUntil: DateTime(2020)),
        save: (price, until) async {
      calls++;
    });
    await tester.tap(find.text('บันทึกโปรโมชั่น'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    expect(find.textContaining('โปรโมชั่นเดิมหมดอายุแล้ว'), findsOneWidget);
    await tester.ensureVisible(find.text('ไม่กำหนดวันสิ้นสุด'));
    await tester.tap(find.text('ไม่กำหนดวันสิ้นสุด'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('บันทึกโปรโมชั่น'));
    await tester.pumpAndSettle();
    expect(calls, 1);
  });
}
