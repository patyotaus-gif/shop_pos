import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/utils/bank_notification_parser.dart';
import 'package:shop_pos/utils/bank_payment_match.dart';

void main() {
  final observed = DateTime.utc(2026, 10, 29, 4);
  bool candidate(double amount, DateTime created, DateTime? transferred) =>
      bankPaymentCandidate(
          expected: amount,
          received: 20,
          createdAt: created,
          observedAt: observed,
          transferredAt: transferred);
  test('same amount and same time retains both candidates for review', () {
    final created = observed.subtract(const Duration(minutes: 10));
    expect([created, created].where((t) => candidate(20, t, observed)),
        hasLength(2));
    expect(candidate(20.01, created, observed), isFalse);
    expect(candidate(20.72, created, observed), isFalse);
  });
  test('delayed notification uses explicit transfer time, not arrival time',
      () {
    final transfer = observed.subtract(const Duration(minutes: 40));
    expect(
        candidate(20, transfer.subtract(const Duration(minutes: 10)), transfer),
        isTrue);
    expect(
        candidate(20, observed.subtract(const Duration(minutes: 5)), transfer),
        isFalse);
    expect(candidate(20, observed.subtract(const Duration(days: 3)), null),
        isTrue);
    expect(candidate(20, observed, observed.subtract(const Duration(days: 5))),
        isTrue);
  });
  test('bank time needs a valid complete date and uses Thailand time', () {
    expect(BankNotificationParser.transferTime('29/10/2569 เวลา 10:15:30'),
        DateTime.utc(2026, 10, 29, 3, 15, 30));
    expect(BankNotificationParser.transferTime('29/10/2026 10:15'),
        DateTime.utc(2026, 10, 29, 3, 15));
    expect(BankNotificationParser.transferTime('เวลา 10:15'), isNull);
    expect(BankNotificationParser.transferTime('31/02/2026 10:15'), isNull);
    expect(BankNotificationParser.transferTime('29/10/2026 24:15'), isNull);
  });
}
