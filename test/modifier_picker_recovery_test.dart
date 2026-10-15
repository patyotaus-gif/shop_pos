import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/models/product.dart';
import 'package:shop_pos/models/modifier_group.dart';
import 'package:shop_pos/widgets/modifier_picker_sheet.dart';

void main() {
  testWidgets(
      'online preview uses promotion and decimals; offline uses prepared base price',
      (tester) async {
    const product = Product(
        id: 'tea',
        name: 'ชา',
        barcode: '',
        price: 25,
        salePrice: 19.5,
        stock: 5,
        modifierGroupIds: ['size']);
    final groups = [
      ModifierGroup(
          id: 'size',
          name: 'ขนาด',
          required: true,
          createdAt: DateTime(2026),
          options: const [
            ModifierOption(id: 'large', name: 'ใหญ่', priceAdjust: 10),
          ])
    ];
    for (final offline in [false, true]) {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: Builder(
        builder: (context) => TextButton(
            onPressed: () => showModifierPicker(context,
                product: product,
                offlineGroups: offline ? groups : null,
                loadGroups: (_) async => groups),
            child: const Text('เลือกสินค้า')),
      ))));
      await tester.tap(find.text('เลือกสินค้า'));
      await tester.pumpAndSettle();
      expect(find.text('ราคาเริ่มต้น ฿${offline ? '25.00' : '19.50'}'),
          findsOneWidget);
      await tester.tap(find.text('ใหญ่'));
      await tester.pumpAndSettle();
      expect(find.text(offline ? '฿35.00' : '฿29.50'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
    }
  });

  testWidgets(
      'failed load blocks addition and retry still enforces required choices',
      (tester) async {
    const product = Product(
        id: 'tea',
        name: 'ชา',
        barcode: '',
        price: 25,
        stock: 5,
        modifierGroupIds: ['size']);
    var attempts = 0;
    ModifierPick? chosen;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
      builder: (context) => TextButton(
          onPressed: () async {
            chosen = await showModifierPicker(context, product: product,
                loadGroups: (ids) async {
              expect(ids, ['size']);
              if (++attempts == 1) throw StateError('เครือข่ายขัดข้อง');
              return [
                ModifierGroup(
                    id: 'size',
                    name: 'ขนาด',
                    required: true,
                    createdAt: DateTime(2026),
                    options: const [
                      ModifierOption(
                          id: 'large', name: 'ใหญ่', priceAdjust: 10),
                    ])
              ];
            });
          },
          child: const Text('เลือกสินค้า')),
    ))));
    await tester.tap(find.text('เลือกสินค้า'));
    await tester.pumpAndSettle();
    expect(find.textContaining('โหลดตัวเลือกสินค้าไม่สำเร็จ'), findsOneWidget);
    expect(find.text('เพิ่มเข้าตะกร้า'), findsNothing);
    await tester.tap(find.text('โหลดใหม่'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'เพิ่มเข้าตะกร้า'))
            .onPressed,
        isNull);
    await tester.tap(find.text('ใหญ่'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('เพิ่มเข้าตะกร้า'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(chosen!.modifiers.single.priceAdjust, 10);
  });

  testWidgets('unresponsive choice load times out and can be cancelled',
      (tester) async {
    const product = Product(
        id: 'tea',
        name: 'ชา',
        barcode: '',
        price: 25,
        stock: 5,
        modifierGroupIds: ['size']);
    final pending = Completer<List<ModifierGroup>>();
    var closed = false;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
      builder: (context) => TextButton(
          onPressed: () async {
            final result = await showModifierPicker(context,
                product: product, loadGroups: (_) => pending.future);
            expect(result, isNull);
            closed = true;
          },
          child: const Text('เลือกสินค้า')),
    ))));
    await tester.tap(find.text('เลือกสินค้า'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 21));
    await tester.pumpAndSettle();
    expect(find.textContaining('โหลดตัวเลือกสินค้าไม่สำเร็จ'), findsOneWidget);
    expect(find.text('เพิ่มเข้าตะกร้า'), findsNothing);
    await tester.tap(find.text('ยกเลิก'));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    pending.complete([]);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('missing required group cannot silently become a plain product',
      (tester) async {
    const product = Product(
        id: 'tea',
        name: 'ชา',
        barcode: '',
        price: 25,
        stock: 5,
        modifierGroupIds: ['size']);
    ModifierPick? chosen;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Builder(
      builder: (context) => TextButton(
          onPressed: () async {
            chosen = await showModifierPicker(context,
                product: product, offlineGroups: const []);
          },
          child: const Text('เลือกสินค้า')),
    ))));
    await tester.tap(find.text('เลือกสินค้า'));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'ข้อมูลตัวเลือกสินค้าไม่ครบ กรุณาโหลดใหม่หรือตรวจการตั้งค่าสินค้า'),
        findsOneWidget);
    expect(find.text('เพิ่มเข้าตะกร้า'), findsNothing);
    expect(chosen, isNull);
  });
}
