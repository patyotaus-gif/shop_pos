import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/models/sale.dart';
import 'package:shop_pos/models/cash_session.dart';
import 'package:shop_pos/utils/receipt_number.dart';

Sale _sale({
  double total = 100,
  PaymentMethod method = PaymentMethod.cash,
  bool isDebt = false,
  bool isRefunded = false,
}) =>
    Sale(
      id: 'x',
      items: const [],
      total: total,
      discount: 0,
      paid: total,
      change: 0,
      createdAt: DateTime(2026, 7, 26),
      paymentMethod: method,
      isDebt: isDebt,
      isRefunded: isRefunded,
    );

void main() {
  group('receipt numbering', () {
    test('receiptDay uses 2-digit Buddhist year', () {
      // 2026-07-26 CE = 2569 BE → "69" + "07" + "26"
      expect(receiptDay(DateTime(2026, 7, 26)), '690726');
      expect(receiptDay(DateTime(2026, 1, 5)), '690105');
    });

    test('formatReceiptNo pads sequence to 3', () {
      expect(formatReceiptNo('690726', 1), '690726-001');
      expect(formatReceiptNo('690726', 42), '690726-042');
      expect(formatReceiptNo('690726', 128), '690726-128');
    });

    test('nextReceiptSeq increments within the same day', () {
      expect(nextReceiptSeq('690726', '690726', 5), (day: '690726', seq: 6));
    });

    test('nextReceiptSeq resets on a new day', () {
      expect(nextReceiptSeq('690725', '690726', 88), (day: '690726', seq: 1));
    });

    test('nextReceiptSeq starts at 1 when counter is missing', () {
      expect(nextReceiptSeq(null, '690726', 0), (day: '690726', seq: 1));
    });
  });

  group('summarizeSession', () {
    test('breaks down by payment method, excludes debt from cash', () {
      final s = summarizeSession([
        _sale(total: 100, method: PaymentMethod.cash),
        _sale(total: 50, method: PaymentMethod.cash),
        _sale(total: 200, method: PaymentMethod.qr),
        _sale(total: 80, method: PaymentMethod.transfer),
        _sale(total: 30, isDebt: true), // เชื่อ — not counted as cash/method
      ], 500);

      expect(s.billCount, 5);
      expect(s.grossTotal, 460);
      expect(s.byMethod['cash'], 150);
      expect(s.byMethod['qr'], 200);
      expect(s.byMethod['transfer'], 80);
      expect(s.debtTotal, 30);
      expect(s.cashSales, 150);
      // expected = float 500 + cash 150
      expect(s.expectedCash, 650);
    });

    test('cash refunds reduce expected cash', () {
      final s = summarizeSession([
        _sale(total: 100, method: PaymentMethod.cash),
        _sale(total: 40, method: PaymentMethod.cash, isRefunded: true),
      ], 0);
      expect(s.cashSales, 100);
      expect(s.refundTotal, 40);
      expect(s.expectedCash, 60); // 0 + 100 − 40
    });

    test('overShort sign: positive = เกิน, negative = ขาด', () {
      final s = summarizeSession(
          [_sale(total: 100, method: PaymentMethod.cash)], 200);
      expect(s.expectedCash, 300);
      expect(s.overShort(305), 5); // เกิน 5
      expect(s.overShort(290), -10); // ขาด 10
    });
  });
}
