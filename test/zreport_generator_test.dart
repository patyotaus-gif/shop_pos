import 'dart:io';
import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/models/cash_session.dart';
import 'package:shop_pos/utils/zreport_generator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() => initializeDateFormatting('th_TH'));
  const summary = SessionSummary(
      billCount: 1,
      grossTotal: 3500,
      byMethod: {'cash': 3500},
      debtTotal: 0,
      refundTotal: 0,
      cashSales: 3500,
      expectedCash: 4500,
      openingFloat: 1000,
      cashDebtCollections: 0,
      cashRefunds: 0);
  test('cash status compares counted cash with full expected drawer in satang',
      () {
    expect(summary.overShort(4500), 0);
    expect(summary.cashStatus(4500), 'เงินสดตรงยอด');
    expect(summary.cashStatus(4499.99), 'เงินสดขาด');
    expect(summary.cashStatus(4500.01), 'เงินสดเกิน');
    expect(summary.cashStatus(4500.00000001), 'เงินสดตรงยอด');
    expect(SessionSummary.fromMap(summary.toMap()).cashRefunds, 0);
  });
  test('58mm report builds offline with Thai font and legacy data', () async {
    final bytes = await ZReportGenerator.build(
        session: CashSession(
            id: 'test-round',
            openedAt: DateTime(2026, 10, 25, 10, 31),
            closedAt: DateTime(2026, 10, 25, 22, 31),
            closed: true,
            openedBy: 'owner-1',
            closedBy: 'owner-1',
            openedByName: 'เจ้าของร้าน',
            closedByName: 'เจ้าของร้าน',
            accountingVersion: 1),
        summary: summary,
        countedCash: 4500,
        info: {'name': 'ร้านทดสอบ', 'taxId': '1234567890123'});
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    await Directory('.remember/tmp').create(recursive: true);
    await File('.remember/tmp/zreport-preview.pdf').writeAsBytes(bytes);
    final detailed = SessionSummary.fromMap({
      ...summary.toMap(),
      'report': {
        'complete': true,
        'salesBeforeDiscount': 4000,
        'discountTotal': 500,
        'serviceCharge': 0,
        'paymentAdjustment': 0,
        'returnedSales': 0,
        'refundBillCount': 0,
        'returnedItems': [],
        'byChannel': {'dineIn': 3500},
        'cashiers': [
          {'name': 'แคชเชียร์ ทดสอบ', 'id': 'A01'}
        ],
      }
    });
    final detailBytes = await ZReportGenerator.build(
        session: CashSession(
            id: 'round-20261025-001',
            openedAt: DateTime(2026, 10, 25, 10, 31),
            closedAt: DateTime(2026, 10, 25, 22, 31),
            closed: true,
            accountingVersion: 1,
            openedBy: 'owner-1',
            closedBy: 'owner-1',
            openedByName: 'เจ้าของร้าน',
            closedByName: 'เจ้าของร้าน'),
        summary: detailed,
        countedCash: 4500,
        info: {'name': 'ร้านทดสอบ'});
    expect(String.fromCharCodes(detailBytes.take(4)), '%PDF');
    await File('.remember/tmp/zreport-detailed-preview.pdf')
        .writeAsBytes(detailBytes);
  });
}
