import 'package:flutter/material.dart';
import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/models/table_order.dart';
import 'package:shop_pos/screens/kitchen_screen.dart';
import 'package:shop_pos/screens/sale_receipt_screen.dart';
import 'package:shop_pos/screens/table_detail_screen.dart';

void main() {
  testWidgets(
      'quantity previews immediately, blocks checkout and restores on failed save',
      (tester) async {
    final saving = Completer<void>();
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: TableOrderView(
      order: TableOrder(
          id: 'o',
          tableId: 't',
          tableName: 'F1',
          openedAt: DateTime.now(),
          items: const [
            TableOrderItem(
                id: 'rice',
                productId: 'rice',
                productName: 'ข้าว',
                price: 50,
                quantity: 1),
          ]),
      loadServiceCharge: () async => 0,
      changeQuantity: (orderId, itemId, target, expected) {
        expect(target, 2);
        expect(expected, 1);
        return saving.future;
      },
    ))));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.add_circle_outline));
    await tester.pump();
    expect(find.text('2'), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'ปิดบิล'))
            .onPressed,
        isNull);
    await tester.pump(const Duration(milliseconds: 350));
    saving.completeError(StateError('บันทึกไม่ได้'));
    await tester.pumpAndSettle();
    expect(find.text('1'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, 'ปิดบิล'))
            .onPressed,
        isNotNull);
  });
  testWidgets('kitchen read errors are not presented as an empty kitchen',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: KitchenScreen(
            orders: Stream.error(StateError('permission-denied')))));
    await tester.pumpAndSettle();
    expect(find.textContaining('โหลดออเดอร์ครัวไม่สำเร็จ'), findsOneWidget);
    expect(find.text('ยังไม่มีออเดอร์เข้าครัว'), findsNothing);
  });
  testWidgets('kitchen shows sent dishes and hides unsent dishes',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: KitchenScreen(
            orders: Stream.value([
      TableOrder(
          id: 'order',
          tableId: 't',
          tableName: 'F1',
          openedAt: DateTime.now(),
          items: const [
            TableOrderItem(
                id: 'a',
                productId: 'a',
                productName: 'ข้าวส่งครัวแล้ว',
                price: 50,
                quantity: 1,
                kitchenStatus: KitchenStatus.sent),
            TableOrderItem(
                id: 'b',
                productId: 'b',
                productName: 'ยังไม่ได้ส่ง',
                price: 50,
                quantity: 1),
          ])
    ]))));
    await tester.pumpAndSettle();
    expect(find.text('ข้าวส่งครัวแล้ว'), findsOneWidget);
    expect(find.text('ยังไม่ได้ส่ง'), findsNothing);
  });
  testWidgets(
      'receipt loading failure keeps payment success and retries only receipt',
      (tester) async {
    var attempts = 0;
    await tester
        .pumpWidget(MaterialApp(home: SaleReceiptScreen(loadSale: () async {
      attempts++;
      throw StateError('offline');
    })));
    await tester.pumpAndSettle();
    expect(find.text('บันทึกการขายสำเร็จ'), findsOneWidget);
    expect(find.textContaining('ไม่ต้องรับเงินซ้ำ'), findsOneWidget);
    await tester.tap(find.text('ลองโหลดใบเสร็จใหม่'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
  });
}
