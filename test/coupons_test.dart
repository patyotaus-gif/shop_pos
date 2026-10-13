import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/models/order.dart';
import 'package:shop_pos/models/sale.dart';
import 'package:shop_pos/screens/coupons_screen.dart';

void main() {
  test(
      'coupon sale and order retain discount and identifying satang separately',
      () {
    final data = <String, dynamic>{
      'total': 80.35,
      'discount': 20.0,
      'paymentAdjustment': .35,
      'paid': 80.35,
      'change': 0.0,
      'coupon': {'code': 'SAVE20'},
      'items': [
        {
          'productId': 'tea',
          'productName': 'Tea',
          'price': 50.0,
          'quantity': 2,
          'subtotal': 100.0
        }
      ],
    };
    final sale = Sale.fromFirestore(data, 's');
    expect(sale.itemsSubtotal, closeTo(100, .001));
    expect(sale.itemNetRevenue.single, 80);
    expect(Sale.fromFirestore(sale.toFirestore(), 's').paymentAdjustment, .35);
    final order = ShopOrder.fromFirestore(
        {...data, 'total': 80.0, 'finalAmount': 80.35}, 'o');
    expect(order.couponCode, 'SAVE20');
    expect(order.discount, 20);
    expect(order.finalAmount, 80.35);
  });
  for (final width in [320.0, 820.0]) {
    testWidgets(
        'coupon editor validates and saves server-owned config at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      Map<String, dynamic>? saved;
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(1.3)),
            child: child!),
        home: Scaffold(
            body: Builder(
                builder: (context) => TextButton(
                    onPressed: () => showDialog(
                        context: context,
                        builder: (_) => CouponEditor(onSave: (data) async {
                              saved = data;
                            })),
                    child: const Text('open')))),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('สร้างโค้ด'));
      await tester.pumpAndSettle();
      expect(saved, isNull);
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), ' welcome10 ');
      await tester.enterText(fields.at(1), '10');
      await tester.tap(find.text('สร้างโค้ด'));
      await tester.pumpAndSettle();
      expect(saved!['code'], 'WELCOME10');
      expect(saved!['kind'], 'percent');
      expect(saved!['value'], 10);
      expect(saved!['maxUses'], 100);
      expect(saved!['minSubtotalMinor'], 0);
      final end =
          DateTime.fromMillisecondsSinceEpoch(saved!['endsAt'], isUtc: true)
              .add(const Duration(hours: 7));
      expect(end.hour, 23);
      expect(end.minute, 59);
      expect(saved!.containsKey('claimed'), isFalse);
      expect(tester.takeException(), isNull);
    });
  }
}
