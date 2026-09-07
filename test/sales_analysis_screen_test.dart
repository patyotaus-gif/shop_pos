import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/screens/sales_analysis_screen.dart';
import 'package:shop_pos/models/sale.dart';
import 'package:shop_pos/models/table_order.dart';
import 'package:shop_pos/models/order_modifier.dart';

Map<String, dynamic> period({List<Map<String, dynamic>> sources = const []}) =>
    {
      'from': '2026-08-31',
      'through': '2026-09-06',
      'net': 100.0,
      'count': 1,
      'units': 2,
      'average': 100.0,
      'gross': 110.0,
      'discount': 10.0,
      'refunds': 0.0,
      'service': 0.0,
      'adjustment': 0.0,
      'grossProfit': null,
      'costCoverage': 50.0,
      'knownUnits': 1,
      'partialProfit': 30.0,
      'invalid': 0,
      'unknownCategory': 0,
      'estimatedPaidAt': 0,
      'products': [],
      'categories': [],
      'hours': [],
      'daily': [],
      'sources': sources,
    };
Map<String, dynamic> fixture() => {
      'days': 7,
      'generatedAt': '2026-09-07T06:00:00Z',
      'timeZone': 'Asia/Bangkok',
      'current': period(sources: [
        {
          'id': 'bill-1',
          'receipt': '260903-001',
          'source': 'sales',
          'day': '2026-09-03',
          'time': '15:00',
          'total': 100.0,
          'refunded': false,
          'items': [
            {
              'name': 'ข้าวไข่เจียว',
              'quantity': 2,
              'subtotal': 110.0,
              'cost': null
            }
          ]
        }
      ]),
      'previous': period(),
      'today': period(),
      'change': 0.0,
      'changePercent': 0.0,
      'productChanges': [],
      'events': [],
      'notes': ['รายงานไม่นับวันนี้ในการเปรียบเทียบ'],
      'settings': {
        'timeZone': 'Asia/Bangkok',
        'openWeekdays': [1, 2, 3]
      },
    };
void main() {
  testWidgets(
      'report snapshot displays incomplete cost honestly on a narrow screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester
        .pumpWidget(MaterialApp(home: SalesAnalysisScreen(initial: fixture())));
    await tester.pumpAndSettle();
    expect(find.textContaining('ช่วงปัจจุบัน 2026-08-31'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('กำไรขั้นต้นสินค้า'), 250,
        scrollable: find
            .descendant(
                of: find.byType(ListView).first,
                matching: find.byType(Scrollable))
            .first);
    expect(find.text('ข้อมูลไม่ครบ'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
  testWidgets('source tab exposes exact bill snapshot and its line items',
      (tester) async {
    await tester
        .pumpWidget(MaterialApp(home: SalesAnalysisScreen(initial: fixture())));
    await tester.tap(find.text('บิลต้นทาง'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('260903-001'));
    await tester.pumpAndSettle();
    expect(find.text('ข้าวไข่เจียว × 2'), findsOneWidget);
    expect(find.textContaining('sales/bill-1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  test('cost/category/add-on snapshots survive table and sale serialization',
      () {
    const modifier = OrderModifier(
        groupId: 'g',
        groupName: 'extra',
        optionId: 'egg',
        optionName: 'ไข่',
        priceAdjust: 10,
        costAdjust: 3);
    const table = TableOrderItem(
        id: 'line',
        productId: 'p',
        productName: 'ข้าว',
        price: 50,
        costPrice: 20,
        costKnown: true,
        category: 'อาหาร',
        quantity: 2,
        modifiers: [modifier]);
    final copy = TableOrderItem.fromMap(table.copyWith(quantity: 3).toMap());
    expect(copy.category, 'อาหาร');
    expect(copy.costKnown, true);
    expect(copy.modifiers.single.costAdjust, 3);
    final sale = SaleItem.fromMap(SaleItem(
            productId: copy.productId,
            productName: copy.productName,
            price: copy.price,
            costPrice: copy.costPrice,
            costKnown: copy.costKnown,
            category: copy.category,
            quantity: copy.quantity,
            subtotal: copy.subtotal,
            modifiers: copy.modifiers)
        .toMap());
    expect(sale.subtotal, 180);
    expect(sale.costPrice, 20);
    expect(sale.modifiers.single.costAdjust, 3);
  });
}
