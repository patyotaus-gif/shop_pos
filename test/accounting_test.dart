import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/models/sale.dart';
import 'package:shop_pos/models/debt.dart';
import 'package:shop_pos/models/order_modifier.dart';
import 'package:shop_pos/models/cash_session.dart';

void main() {
  test('closing snapshot preserves unpaid carry-forward counts', () {
    final summary = SessionSummary.fromMap({
      'pendingOrderCount': 2,
      'openTableCount': 3,
      'expectedCash': 500.01,
      'byMethod': {'cash': 0.01},
    });
    final restored = SessionSummary.fromMap(summary.toMap());
    expect(restored.pendingOrderCount, 2);
    expect(restored.openTableCount, 3);
    expect(restored.expectedCash, 500.01);
    expect(SessionSummary.fromMap({}).openTableCount, 0);
  });
  Sale sale({bool refunded = false, bool debt = false}) => Sale(
      id: 's',
      items: const [],
      total: 100,
      discount: 0,
      paid: 100,
      change: 0,
      createdAt: DateTime(2026),
      isRefunded: refunded,
      isDebt: debt);
  test('same-period cash refund neither removes opening float nor leaves debt',
      () {
    expect(summarizeSession([sale(refunded: true)], 500).expectedCash, 500);
    expect(
        summarizeSession([sale(refunded: true, debt: true)], 500).debtTotal, 0);
  });
  test('cancelled debt retains original payment but is not outstanding', () {
    final debt = Debt(
        id: 'd',
        customerName: 'test',
        amount: 100,
        paidAmount: 40,
        createdAt: DateTime(2026),
        saleId: 's',
        cancelled: true);
    expect(debt.remaining, 0);
    expect(debt.paidAmount, 40);
  });
  test('modifier cost and actual charged subtotal drive margin', () {
    const item = SaleItem(
        productId: 'rice',
        productName: 'rice',
        price: 50,
        costPrice: 20,
        costKnown: true,
        quantity: 2,
        subtotal: 120,
        modifiers: [
          OrderModifier(
              groupId: 'g',
              groupName: 'extra',
              optionId: 'egg',
              optionName: 'egg',
              priceAdjust: 10,
              costAdjust: 3)
        ]);
    expect(item.unitCost, 23);
    expect(item.profit, 74);
    expect(item.hasKnownCost, true);
  });
  test('bill discount allocation conserves satang and excludes service charge',
      () {
    final bill = Sale(
        id: 's',
        items: List.generate(
            3,
            (i) => SaleItem(
                productId: '$i',
                productName: 'i',
                price: 1,
                quantity: 1,
                subtotal: 1)),
        total: 3.29,
        discount: .01,
        paid: 3.29,
        change: 0,
        createdAt: DateTime(2026),
        serviceCharge: .30);
    expect(bill.itemNetRevenue, [.99, 1, 1]);
    expect(bill.itemNetRevenue.fold<double>(0, (v, r) => v + r), 2.99);
  });
}
