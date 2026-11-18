import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/models/sale.dart';
import 'package:shop_pos/widgets/report_sales_trend.dart';

Sale sale(String id, DateTime date, double total,
        {bool refunded = false, bool debt = false}) =>
    Sale(
        id: id,
        items: const [],
        total: total,
        discount: 0,
        paid: total,
        change: 0,
        createdAt: date,
        receiptNo: id,
        isRefunded: refunded,
        isDebt: debt);

void main() {
  test('previous period has the same number of calendar dates across New Year',
      () {
    final previous = precedingSalesRange(DateTimeRange(
        start: DateTime(2026, 1, 1), end: DateTime(2026, 1, 7, 23, 59)));
    expect(previous.start, DateTime(2025, 12, 25));
    expect(previous.end, DateTime(2025, 12, 31));
  });

  testWidgets(
      'trend opens source bills, handles refunds, and compares the scoped period on demand',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 840);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final day = DateTime(2026, 11, 1, 12, 3);
    final data = [
      sale('paid', day, 100),
      sale('returned', day, 60, refunded: true),
      sale('debt', day, 20, debt: true)
    ];
    var calls = 0;
    final previous = StreamController<List<Sale>>.broadcast();
    addTearDown(previous.close);
    String? opened;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ListView(children: [
      ReportSalesTrend(
          sales: data,
          range: DateTimeRange(
              start: DateTime(2026, 11, 1), end: DateTime(2026, 11, 7)),
          previousSales: (r) {
            expect(r.start, DateTime(2026, 10, 25));
            calls++;
            return previous.stream;
          },
          onOpenBill: (s) => opened = s.id),
    ]))));
    expect(calls, 0);
    expect(find.text('ยอดสูงสุด ฿120.00'), findsOneWidget);
    await tester.tap(find.text('1/11'));
    await tester.pumpAndSettle();
    expect(find.text('ยอดขายสุทธิ ฿120.00'), findsOneWidget);
    expect(find.textContaining('คืนเงินแล้ว'), findsOneWidget);
    await tester.tap(find.text('paid'));
    await tester.pumpAndSettle();
    expect(opened, 'paid');
    await tester.tap(find.text('เปรียบเทียบกับช่วงก่อนหน้า'));
    await tester.pump();
    expect(previous.hasListener, isTrue);
    previous.add([sale('prev', DateTime(2026, 10, 25), 80)]);
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.text('ยอดขายเพิ่มขึ้น ฿40.00 (50.0%)'), findsOneWidget);
    previous.add([sale('prev', DateTime(2026, 10, 25), 80, refunded: true)]);
    await tester.pumpAndSettle();
    expect(find.text('ยอดขายเพิ่มขึ้น ฿120.00'), findsOneWidget);
    await tester.tap(find.text('ปิดการเปรียบเทียบ'));
    await tester.pumpAndSettle();
    expect(previous.hasListener, isFalse);
    await tester.tap(find.text('ตามชั่วโมง'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('12'));
    await tester.pumpAndSettle();
    expect(find.text('12:00 – 12:59'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
