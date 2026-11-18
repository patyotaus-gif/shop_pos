import '../models/sale.dart';

class BillGroup {
  int count = 0;
  int amountMinor = 0;

  void add(int amount) {
    count++;
    amountMinor += amount;
  }
}

/// All amounts are rounded once per bill in satang, as in the CSV report.
class SalesBreakdown {
  final payments = <PaymentMethod?, BillGroup>{};
  final channels = <SalesChannel, BillGroup>{};
  final tables = <String, BillGroup>{};
  final cashiers = <String?, BillGroup>{};
  final debt = BillGroup();
  final members = BillGroup();
  final memberIds = <String>{};
  final refunds = BillGroup();
  int netSalesMinor = 0;
  int beforeDiscountMinor = 0;
  int discountMinor = 0;
  int serviceMinor = 0;
  int adjustmentMinor = 0;
  int setsSoldBills = 0;
  int giftBills = 0;
  int bundleDiscountMinor = 0;

  int get paidAtSaleMinor => netSalesMinor - debt.amountMinor;

  SalesBreakdown(Iterable<Sale> sales) {
    for (final sale in sales) {
      final amount = (sale.total * 100).round();
      final discount = (sale.discount * 100).round();
      final service = (sale.serviceCharge * 100).round();
      final adjustment = (sale.paymentAdjustment * 100).round();
      beforeDiscountMinor += amount + discount - service - adjustment;
      discountMinor += discount;
      serviceMinor += service;
      adjustmentMinor += adjustment;
      if (sale.isRefunded) {
        refunds.add(amount);
        continue;
      }
      netSalesMinor += amount;
      if (sale.isDebt) {
        debt.add(amount);
      } else {
        payments
            .putIfAbsent(sale.recordedPaymentMethod, BillGroup.new)
            .add(amount);
      }
      channels.putIfAbsent(sale.salesChannel, BillGroup.new).add(amount);
      final table = sale.tableName?.trim();
      if (table != null && table.isNotEmpty) {
        tables.putIfAbsent(table, BillGroup.new).add(amount);
      }
      final name = sale.staffName?.trim();
      cashiers
          .putIfAbsent(
              name == null || name.isEmpty ? null : name, BillGroup.new)
          .add(amount);
      final memberId = sale.loyaltyCustomerId?.trim();
      if (memberId != null && memberId.isNotEmpty) {
        memberIds.add(memberId);
        members.add(amount);
      }
      if (sale.bundles.isNotEmpty) setsSoldBills++;
      if (sale.buyGet.isNotEmpty || sale.items.any((item) => item.isGift)) {
        giftBills++;
      }
      bundleDiscountMinor += (sale.bundleDiscount * 100).round();
    }
  }
}
