import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/models/customer.dart';
import 'package:shop_pos/models/table_order.dart';
import 'package:shop_pos/screens/table_detail_screen.dart';
import 'package:shop_pos/theme/pokpok_theme.dart';

void main() {
  // A priced, current bill: two teas at ฿50 with no other discounts.
  TableOrder order({Map<String, dynamic>? loyalty}) => TableOrder(
          id: 'o',
          tableId: 't',
          tableName: '1B',
          openedAt: DateTime(2026, 11, 9),
          items: const [
            TableOrderItem(
                id: 'a',
                productId: 'tea',
                productName: 'ชา',
                price: 50,
                quantity: 2,
                kitchenStatus: KitchenStatus.sent),
          ],
          promotion: {
            'lines': [
              {'id': 'a', 'productId': 'tea', 'quantity': 2, 'unitPrice': 50}
            ],
            'subtotalMinor': 10000,
            'discountMinor': loyalty?['discountMinor'] ?? 0,
            'serviceMinor': 0,
            'totalMinor': 10000 - (loyalty?['discountMinor'] as int? ?? 0),
            'revision': 'r',
            if (loyalty != null) 'loyalty': loyalty,
          });

  Future<List<(String?, int)>> pump(WidgetTester tester, TableOrder value,
      {Customer? picked}) async {
    final calls = <(String?, int)>[];
    await tester.pumpWidget(MaterialApp(
        theme: PokpokTheme.light(),
        home: Scaffold(
            body: TableOrderView(
          order: value,
          loadServiceCharge: () async => 0,
          loyaltyEnabled: true,
          pickLoyaltyCustomer: (_) async => picked,
          loadCustomerPoints: (_) async => 120,
          setLoyalty: (orderId, {customerId, redeemBaht = 0}) async {
            expect(orderId, 'o');
            calls.add((customerId, redeemBaht));
          },
        ))));
    await tester.pumpAndSettle();
    return calls;
  }

  testWidgets('a bill without a customer can attach one', (tester) async {
    final calls = await pump(tester, order(),
        picked: Customer(
            id: 'c1',
            name: 'คุณเอ',
            phone: '0811111111',
            points: 120,
            createdAt: DateTime(2026)));
    await tester.ensureVisible(
        find.byKey(const ValueKey('table-loyalty-attach')));
    await tester.tap(find.byKey(const ValueKey('table-loyalty-attach')));
    await tester.pumpAndSettle();
    expect(calls, [('c1', 0)]);
  });

  testWidgets('points redeem whole baht within balance and can be removed',
      (tester) async {
    final calls = await pump(
        tester,
        order(loyalty: {
          'customerId': 'c1',
          'customerName': 'คุณเอ',
          'pointsPerBaht': 10,
          'redeemBaht': 0,
          'pointsRedeemed': 0,
          'discountMinor': 0,
        }));
    expect(find.text('คุณเอ'), findsOneWidget);
    await tester.ensureVisible(
        find.byKey(const ValueKey('table-loyalty-redeem')));
    await tester.tap(find.byKey(const ValueKey('table-loyalty-redeem')));
    await tester.pumpAndSettle();
    expect(find.textContaining('ใช้ได้สูงสุด ฿12'), findsOneWidget,
        reason: '120 points at 10 per baht');
    await tester.enterText(find.byKey(const ValueKey('redeem-baht')), '13');
    await tester.tap(find.byKey(const ValueKey('redeem-confirm')));
    await tester.pumpAndSettle();
    expect(calls, isEmpty, reason: 'over the balance is not accepted');
    await tester.enterText(find.byKey(const ValueKey('redeem-baht')), '7');
    await tester.tap(find.byKey(const ValueKey('redeem-confirm')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('table-loyalty-remove')));
    await tester.pumpAndSettle();
    expect(calls, [('c1', 7), (null, 0)]);
  });

  testWidgets('a redeemed bill shows the points used and the lower total',
      (tester) async {
    await pump(
        tester,
        order(loyalty: {
          'customerId': 'c1',
          'customerName': 'คุณเอ',
          'pointsPerBaht': 10,
          'redeemBaht': 7,
          'pointsRedeemed': 70,
          'discountMinor': 700,
        }));
    expect(find.text('คุณเอ · ใช้ 70 แต้ม -฿7'), findsOneWidget);
    expect(find.text('฿93.00'), findsOneWidget);
  });
}
