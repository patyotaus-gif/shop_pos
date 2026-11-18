import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/models/sale.dart';
import 'package:shop_pos/utils/sales_breakdown.dart';
import 'package:shop_pos/widgets/report_breakdowns.dart';

Sale _sale(String id, Map<String, dynamic> fields) =>
    Sale.fromFirestore(fields, id);

void main() {
  final sales = [
    _sale('paid', {
      'total': 95.05,
      'paymentMethod': 'cash',
      'discount': 10,
      'serviceCharge': 5,
      'paymentAdjustment': 0.05,
      'salesChannel': 'dineIn',
      'loyaltyCustomerId': 'member-1',
      'staffName': ' A ',
      'bundles': [
        {'name': 'set'}
      ],
      'bundleDiscount': 2,
    }),
    _sale('credit', {
      'total': 20,
      'isDebt': true,
      'loyaltyCustomerId': 'member-1',
      'customerName': 'Debit account',
      'staffName': 'A'
    }),
    _sale('returned', {
      'total': 40,
      'discount': 10,
      'isRefunded': true,
      'loyaltyCustomerId': 'member-2',
      'staffName': 'B',
    }),
    _sale('legacy', {'total': 2, 'customerName': 'Credit name only'}),
  ];

  test(
      'sales reconciliation includes refunds once and keeps debt out of tender',
      () {
    final report = SalesBreakdown(sales);
    expect(report.beforeDiscountMinor, 17200);
    expect(report.discountMinor, 2000);
    expect(report.serviceMinor, 500);
    expect(report.adjustmentMinor, 5);
    expect(report.refunds.amountMinor, 4000);
    expect(report.netSalesMinor, 11705);
    expect(report.paidAtSaleMinor, 9705);
    expect(report.debt.amountMinor, 2000);
    expect(report.payments[PaymentMethod.cash]!.count, 1);
    expect(report.payments[null]!.amountMinor, 200);
    expect(report.channels[SalesChannel.unspecified]!.amountMinor, 2200);
    expect(report.cashiers['A']!.amountMinor, 11505);
    expect(report.cashiers[null]!.amountMinor, 200);
    expect(report.members.count, 2);
    expect(report.memberIds, {'member-1'});
    expect(report.members.amountMinor, 11505);
    expect(report.setsSoldBills, 1);
    expect(report.bundleDiscountMinor, 200);
  });

  test('missing and future methods remain distinct from cash after round trip',
      () {
    final legacy = _sale('legacy', {'total': 2});
    final future = _sale('future', {'total': 3, 'paymentMethod': 'new-tender'});
    final cash = _sale('cash', {'total': 5, 'paymentMethod': 'cash'});
    expect(legacy.paymentMethod, PaymentMethod.cash);
    expect(future.paymentMethod, PaymentMethod.cash);
    expect(legacy.reportPaymentLabel, 'ไม่ระบุวิธีชำระ');
    expect(future.reportPaymentLabel, 'ไม่ระบุวิธีชำระ');
    expect(cash.reportPaymentLabel, PaymentMethod.cash.label);
    expect(legacy.toFirestore().containsKey('paymentMethod'), isFalse);
    expect(future.toFirestore()['paymentMethod'], 'new-tender');
    expect(cash.toFirestore()['paymentMethod'], 'cash');
    final roundTripped = [legacy, future, cash]
        .map((sale) => _sale(sale.id, sale.toFirestore()));
    final breakdown = SalesBreakdown(roundTripped);
    expect(breakdown.payments[null]!.count, 2);
    expect(breakdown.payments[null]!.amountMinor, 500);
    expect(breakdown.payments[PaymentMethod.cash]!.amountMinor, 500);
  });

  test('split checks count each non-refunded named bill rounded to satang', () {
    final report = SalesBreakdown([
      _sale('split-1', {'tableName': ' A1 ', 'total': 15.006}),
      _sale('split-2', {'tableName': 'A1', 'total': 25.006}),
      _sale('table-2', {'tableName': 'A2', 'total': 12}),
      _sale('blank-table', {'tableName': ' ', 'total': 150}),
      _sale('takeaway', {'total': 99}),
      _sale('refund', {'tableName': 'A1', 'total': 100, 'isRefunded': true}),
    ]);
    expect(report.tables.keys, unorderedEquals(['A1', 'A2']));
    expect(report.tables['A1']!.count, 2);
    expect(report.tables['A1']!.amountMinor, 4002);
    expect(report.tables['A2']!.amountMinor, 1200);
  });

  testWidgets(
      'staff, member and promotion insights respect advanced report entitlement',
      (tester) async {
    Future<void> show({bool advanced = false}) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
        body: SingleChildScrollView(
            child: ReportBreakdowns(
          sales: sales,
          advanced: advanced,
        )),
      )));
    }

    await show();
    expect(find.text('ไม่ระบุวิธีชำระ'), findsOneWidget);
    expect(find.text('ยอดขายตามโต๊ะ'), findsNothing);
    expect(find.text('ยอดขายตามผู้ปิดบิล'), findsNothing);
    expect(find.text('ยอดซื้อของสมาชิก'), findsNothing);
    expect(find.text('การใช้โปรโมชัน'), findsNothing);
    await show(advanced: true);
    expect(find.text('ยอดขายตามโต๊ะ'), findsOneWidget);
    expect(find.text('ยอดซื้อของสมาชิก'), findsOneWidget);
    expect(find.text('ยอดขายตามผู้ปิดบิล'), findsOneWidget);
    expect(find.text('การใช้โปรโมชัน'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
