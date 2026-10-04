import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/models/sale.dart';
import 'package:shop_pos/models/marketplace_order.dart';
import 'package:shop_pos/widgets/sales_insights.dart';
import 'package:shop_pos/widgets/unit_cost_calculator.dart';
import 'package:shop_pos/services/quantity_edit_queue.dart';

void main() {
  testWidgets(
      'rapid quantity taps coalesce and serialize changes during a write',
      (tester) async {
    final first = Completer<void>();
    final calls = <(int, int)>[];
    final queue = QuantityEditQueue(
        quantity: 1,
        save: (expected, target) {
          calls.add((expected, target));
          return calls.length == 1 ? first.future : Future.value();
        },
        onChanged: () {},
        onError: (e) => fail('$e'));
    queue.change(1);
    queue.change(1);
    queue.change(1);
    expect(queue.target, 4);
    await tester.pump(const Duration(milliseconds: 350));
    expect(calls, [(1, 4)]);
    queue.change(1);
    queue.change(1);
    first.complete();
    await tester.pump(const Duration(milliseconds: 350));
    expect(calls, [(1, 4), (4, 6)]);
    expect(queue.confirmed, 6);
    expect(queue.busy, false);
    queue.dispose();
  });
  test('unit cost includes yield and packaging and rejects invalid input', () {
    expect(unitCost(batchCost: 300, yieldCount: 20, packaging: 2), 17);
    expect(() => unitCost(batchCost: 300, yieldCount: 0, packaging: 2),
        throwsArgumentError);
    expect(() => unitCost(batchCost: double.nan, yieldCount: 20, packaging: 2),
        throwsArgumentError);
  });
  Sale sale({bool refunded = false}) => Sale(
      id: 's',
      items: const [
        SaleItem(
            productId: 'a',
            productName: 'Rice',
            price: 50,
            category: 'อาหาร',
            quantity: 2,
            subtotal: 100),
        SaleItem(
            productId: 'b',
            productName: 'Tea',
            price: 20,
            category: 'เครื่องดื่ม',
            quantity: 1,
            subtotal: 20),
      ],
      total: 110,
      discount: 10,
      paid: 110,
      change: 0,
      createdAt: DateTime(2026),
      salesChannel: SalesChannel.lineMan,
      isRefunded: refunded);
  test('best sellers filter categories and exclude refunds', () {
    final totals = productSalesTotals([sale(), sale(refunded: true)], 'อาหาร');
    expect(totals.keys, ['a']);
    expect(totals['a']!.quantity, 2);
    expect(totals['a']!.revenue,
        91.67); // 10 baht bill discount is allocated proportionally.
    final all = productSalesTotals([sale()], null);
    expect(
        all.values.fold<double>(0, (value, row) => value + row.revenue), 110);
  });
  test('channel survives saved sale round trip; legacy remains unspecified',
      () {
    expect(Sale.fromFirestore(sale().toFirestore(), 's').salesChannel,
        SalesChannel.lineMan);
    final legacy = sale().toFirestore()..remove('salesChannel');
    expect(
        Sale.fromFirestore(legacy, 's').salesChannel, SalesChannel.unspecified);
  });
  test('procurement keeps fractional quantities through reorder serialization',
      () {
    const item = MarketplaceOrderItem(
        productId: 'p', name: 'Pork', unit: 'kg', price: 150, quantity: 1.5);
    final saved = MarketplaceOrderItem.fromMap(item.toMap());
    expect(saved.quantity, 1.5);
    expect(saved.subtotal, 225);
    expect(
        MarketplaceOrderItem.fromMap({...item.toMap(), 'quantity': 2}).quantity,
        2);
  });
}
