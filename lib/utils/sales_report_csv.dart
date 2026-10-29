import 'package:intl/intl.dart';
import '../models/sale.dart';
import 'csv_export.dart';

int _minor(num value) => (value * 100).round();
int _cost(Sale s) => _minor(s.items
    .fold<double>(0, (sum, item) => sum + item.unitCost * item.quantity));
int _itemRevenue(Sale s) =>
    _minor(s.itemNetRevenue.fold<double>(0, (sum, value) => sum + value));

// Share the per-bill cent rounding with the on-screen and PDF report totals.
double reportSaleCost(Sale sale) => _cost(sale) / 100;
double reportItemRevenue(Sale sale) => _itemRevenue(sale) / 100;
double sumReportMoney(Iterable<num> values) =>
    values.fold<int>(0, (sum, value) => sum + _minor(value)) / 100;

String buildSalesReportCsv({
  required List<Sale> sales,
  required Map<String, String> shop,
  required String title,
  required DateTime from,
  required DateTime to,
  required DateTime generatedAt,
}) {
  final date = DateFormat('dd/MM/yyyy HH:mm:ss');
  final day = DateFormat('dd/MM/yyyy');
  final active = sales.where((s) => !s.isRefunded).toList();
  final gross = sales.fold<int>(0, (v, s) => v + _minor(s.total));
  final refunded = sales.where((s) => s.isRefunded).toList();
  final returns = refunded.fold<int>(0, (v, s) => v + _minor(s.total));
  final cost = active.fold<int>(0, (v, s) => v + _cost(s));
  final revenue = active.fold<int>(0, (v, s) => v + _itemRevenue(s));
  final costKnown = active.every((s) => s.items.every((i) => i.hasKnownCost));
  final out = StringBuffer();
  void row(List<Object?> cells) => out.writeln(csvRow(cells));
  CsvMoney money(int cents) => CsvMoney(cents / 100);
  row(['รายงานการขาย', shop['name']]);
  if ((shop['taxId'] ?? '').isNotEmpty) {
    row(['เลขประจำตัวผู้เสียภาษี', shop['taxId']]);
  }
  row(['ช่วงเวลา', title]);
  row(['ตั้งแต่', day.format(from)]);
  row(['ถึง', day.format(to)]);
  row(['ส่งออกเมื่อ', date.format(generatedAt)]);
  row([
    'เขตเวลาเครื่อง',
    generatedAt.timeZoneName,
    generatedAt.timeZoneOffset.toString()
  ]);
  row(['ฐานรายงาน', salesReportBasis]);
  row([
    'การรวมยอด',
    'รวมยอดสุทธิและต้นทุนสุทธิจากรายละเอียด ปัดเป็นสตางค์ต่อบิล'
  ]);
  row([]);
  row(['=== สรุปทางการเงิน ===']);
  row(['รายได้ก่อนหักคืน (หลังส่วนลด)', money(gross)]);
  row(['คืนเงิน', money(returns)]);
  row(['รายได้สุทธิ', money(gross - returns)]);
  row(['ต้นทุนสินค้าขาย (COGS)', costKnown ? money(cost) : 'ต้นทุนไม่ครบ']);
  row(['กำไรขั้นต้น', costKnown ? money(revenue - cost) : 'ต้นทุนไม่ครบ']);
  row([
    'อัตรากำไรขั้นต้น (%)',
    costKnown
        ? CsvMoney(revenue > 0 ? (revenue - cost) / revenue * 100 : 0)
        : 'ต้นทุนไม่ครบ'
  ]);
  row(['จำนวนบิลทั้งหมด', sales.length]);
  row(['บิลปกติ', active.length]);
  row(['บิลคืนเงิน', refunded.length]);
  row([]);
  row(['=== รายการขายทั้งหมด ===']);
  row([
    'ลำดับ',
    'เลขอ้างอิงบิล',
    'วันที่ขาย',
    'ลูกค้า',
    'วิธีชำระเงิน',
    'ช่องทางขาย',
    'ยอดเดิมหลังส่วนลด',
    'ยอดคืน',
    'ยอดสุทธิ',
    'ต้นทุนเดิม',
    'ต้นทุนที่กลับรายการ',
    'ต้นทุนสุทธิ',
    'กำไรขั้นต้นสุทธิ',
    'ส่วนลดเดิม',
    'สถานะ',
    'วันที่คืนเงิน',
    'เหตุผลคืนเงิน'
  ]);
  for (var i = 0; i < sales.length; i++) {
    final s = sales[i];
    final total = _minor(s.total);
    final c = _cost(s);
    final known = s.items.every((item) => item.hasKnownCost);
    row([
      i + 1,
      s.id,
      date.format(s.createdAt),
      s.customerName,
      s.isDebt ? 'เชื่อ' : s.paymentMethod.label,
      s.salesChannel.label,
      money(total),
      money(s.isRefunded ? total : 0),
      money(s.isRefunded ? 0 : total),
      known ? money(c) : 'ต้นทุนไม่ครบ',
      s.isRefunded && !known ? 'ต้นทุนไม่ครบ' : money(s.isRefunded ? c : 0),
      s.isRefunded
          ? money(0)
          : known
              ? money(c)
              : 'ต้นทุนไม่ครบ',
      s.isRefunded
          ? money(0)
          : known
              ? money(_itemRevenue(s) - c)
              : 'ต้นทุนไม่ครบ',
      money(_minor(s.discount)),
      s.isRefunded ? 'คืนเงิน' : 'ปกติ',
      s.refundedAt == null ? '' : date.format(s.refundedAt!),
      s.refundReason
    ]);
  }
  return out.toString();
}
