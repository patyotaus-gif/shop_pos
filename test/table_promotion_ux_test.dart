import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shop_pos/models/table_order.dart';
import 'package:shop_pos/screens/table_detail_screen.dart';
import 'package:shop_pos/services/table_promotion_controller.dart';
import 'package:shop_pos/widgets/table_promotion_dialog.dart';

TableOrder tab(int quantity, {bool quoted = false, bool sent = false}) {
  final item = TableOrderItem(
      id: 'rice',
      productId: 'rice',
      productName: 'ข้าว',
      price: 50,
      quantity: quantity,
      kitchenStatus: sent ? KitchenStatus.sent : KitchenStatus.pending);
  return TableOrder(
      id: 'o',
      tableId: 't',
      tableName: 'F1',
      openedAt: DateTime(2026),
      items: [item],
      promotion: quoted
          ? {
              'lines': [
                {
                  'id': item.id,
                  'productId': item.productId,
                  'quantity': quantity,
                  'unitPrice': 50
                }
              ],
              'subtotalMinor': quantity * 5000,
              'discountMinor': 1000,
              'serviceChargePercent': 0,
              'serviceMinor': 0,
              'totalMinor': quantity * 5000 - 1000,
              'revision': '$quantity',
            }
          : null);
}

void main() {
  testWidgets(
      'rapid edits coalesce into one automatic calculation without sending kitchen',
      (tester) async {
    await tester.pump();
    final calls = <int>[];
    final controller = TablePromotionController(tab(1), (order,
        {bool send = false,
        bool keepPreparedGifts = false,
        String reason = ''}) async {
      expectSync(send, false);
      calls.add(order.items.single.quantity.toInt());
      return tab(order.items.single.quantity.toInt(), quoted: true);
    });
    addTearDown(controller.dispose);
    await tester.pump(const Duration(milliseconds: 200));
    controller.update(tab(2));
    await tester.pump(const Duration(milliseconds: 200));
    controller.update(tab(3));
    await tester.pump(const Duration(milliseconds: 450));
    expect(controller.error, isNull);
    expect(calls, [3]);
    expect(controller.order.promotion!['totalMinor'], 14000);
    await tester.pump(const Duration(seconds: 2));
    expect(calls, [3]);
  });

  testWidgets('late response cannot overwrite a newer quantity',
      (tester) async {
    final old = Completer<TableOrder>();
    final calls = <int>[];
    final controller = TablePromotionController(tab(1), (order,
        {bool send = false,
        bool keepPreparedGifts = false,
        String reason = ''}) async {
      calls.add(order.items.single.quantity.toInt());
      if (calls.length == 1) return old.future;
      return tab(2, quoted: true);
    });
    addTearDown(controller.dispose);
    await tester.pump(const Duration(milliseconds: 450));
    controller.update(tab(2));
    old.complete(tab(1, quoted: true));
    await tester.pump();
    expect(controller.order.items.single.quantity, 2);
    expect(controller.order.promotion, isNull);
    await tester.pump(const Duration(milliseconds: 450));
    expect(calls, [1, 2]);
    expect(controller.order.promotion!['totalMinor'], 9000);
  });

  testWidgets(
      'failure stays visible without a retry loop; explicit retry recovers',
      (tester) async {
    var calls = 0;
    final controller = TablePromotionController(tab(1), (order,
        {bool send = false,
        bool keepPreparedGifts = false,
        String reason = ''}) async {
      if (++calls == 1) throw StateError('อินเทอร์เน็ตขัดข้อง');
      return tab(1, quoted: true);
    });
    addTearDown(controller.dispose);
    await tester.pump(const Duration(milliseconds: 450));
    expect(controller.error, isStateError);
    await tester.pump(const Duration(seconds: 5));
    expect(calls, 1);
    await controller.ensure();
    expect(controller.error, isNull);
    expect(controller.order.promotionCurrent, true);
  });

  for (final width in [320.0, 820.0]) {
    testWidgets(
        'one payment tap sends pending dishes and opens payment summary at $width',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final sends = <bool>[];
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: TableOrderView(
        order: tab(2),
        loadServiceCharge: () async => 0,
        syncPromotions: (order,
            {bool send = false,
            bool keepPreparedGifts = false,
            String reason = ''}) async {
          sends.add(send);
          return tab(2, quoted: true, sent: send);
        },
      ))));
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      expect(find.byType(TablePromotionDialog), findsNothing);
      expect(sends, [false]);
      await tester.ensureVisible(find.byKey(const ValueKey('table-payment')));
      await tester.tap(find.byKey(const ValueKey('table-payment')));
      await tester.pumpAndSettle();
      expect(sends, [false, false, true]);
      expect(find.text('ยอดสุทธิ'), findsOneWidget);
      expect(find.textContaining('ค่าสินค้า ฿100.00'), findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(BottomSheet),
              matching: find.textContaining('ส่วนลด ฿10.00')),
          findsOneWidget);
      expect(find.byType(TablePromotionDialog), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('coupon validity failure before checkout does not open payment',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: TableOrderView(
      order: tab(1, quoted: true, sent: true),
      loadServiceCharge: () async => 0,
      syncPromotions: (order,
          {bool send = false,
          bool keepPreparedGifts = false,
          String reason = ''}) async {
        throw StateError('คูปอง: สิทธิ์ครบแล้ว');
      },
    ))));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('table-payment')));
    await tester.tap(find.byKey(const ValueKey('table-payment')));
    await tester.pumpAndSettle();
    expect(find.text('ยอดสุทธิ'), findsNothing);
    expect(find.text('คูปอง: สิทธิ์ครบแล้ว'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
