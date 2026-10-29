import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/models/sale.dart';
import 'package:shop_pos/utils/csv_export.dart';
import 'package:shop_pos/utils/sales_report_csv.dart';
import 'package:shop_pos/utils/movement_report_csv.dart';

// Strict reader used to exercise interoperability, rather than comparing the
// serializer to itself. Handles quoted newlines and rejects broken quoting.
List<List<String>> readCsv(String input) {
  final rows = <List<String>>[];
  var row = <String>[];
  var cell = StringBuffer();
  var quoted = false;
  var closed = false;
  void endCell() {
    row.add(cell.toString());
    cell = StringBuffer();
    closed = false;
  }

  for (var i = 0; i < input.length; i++) {
    final c = input[i];
    if (quoted) {
      if (c == '"') {
        if (i + 1 < input.length && input[i + 1] == '"') {
          cell.write('"');
          i++;
        } else {
          quoted = false;
          closed = true;
        }
      } else {
        cell.write(c);
      }
    } else if (c == ',') {
      endCell();
    } else if (c == '\n') {
      endCell();
      rows.add(row);
      row = [];
    } else if (c == '"' && cell.isEmpty && !closed) {
      quoted = true;
    } else {
      if (closed || c == '"') throw FormatException('Invalid CSV quote');
      cell.write(c);
    }
  }
  if (quoted) throw FormatException('Unclosed CSV quote');
  if (row.isNotEmpty || cell.isNotEmpty || closed) {
    endCell();
    rows.add(row);
  }
  return rows;
}

Sale sale(
        {String id = 's1',
        bool refunded = false,
        bool known = true,
        String customer = 'ACME "Branch", East\nชั้น 2',
        double quantity = 1}) =>
    Sale(
        id: id,
        total: 100,
        discount: 5,
        paid: 100,
        change: 0,
        createdAt: DateTime(2026, 10, 29, 10),
        isRefunded: refunded,
        refundedAt: refunded ? DateTime(2026, 10, 30, 11) : null,
        refundReason: refunded ? 'เสียหาย, "คืน"\nตรวจแล้ว' : null,
        customerName: customer,
        items: [
          SaleItem(
              productId: 'p1',
              productName: 'สินค้า',
              price: 105,
              costPrice: 40.01,
              costKnown: known,
              quantity: quantity,
              subtotal: 105)
        ]);

List<List<String>> exportSales(List<Sale> sales) => readCsv(buildSalesReportCsv(
    sales: sales,
    shop: {'name': 'ร้าน, "ทดสอบ"\nสาขา 1', 'taxId': '0012345678901'},
    title: 'ทดสอบ',
    from: DateTime(2026, 10, 29),
    to: DateTime(2026, 10, 29),
    generatedAt: DateTime(2026, 10, 30)));

void main() {
  test('CSV round-trips Thai, quotes, commas, CR/LF and empty fields', () {
    final fields = ['ร้าน, "หนึ่ง"', 'สอง\r\nสาม', '', '0012345678901'];
    expect(readCsv('${csvRow(fields)}\n').single, fields);
  });
  test('untrusted formula prefixes are text; signed money remains numeric', () {
    for (final value in [
      '=1+1',
      '+SUM(1,2)',
      '-1+2',
      '@SUM(1)',
      ' \t=1+1',
      '\ufeff=1',
      '\r=1',
      '\tname'
    ]) {
      expect(readCsv(csvRow([value])).single.single, "'$value");
    }
    expect(
        readCsv(csvRow([const CsvMoney(-20.72), const CsvMoney(-0.001), -5]))
            .single,
        ['-20.72', '0.00', '-5']);
    expect(() => csvRow([double.nan]), throwsArgumentError);
  });
  test(
      'sales export safely imports shop/customer/reason text into fixed columns',
      () {
    final rows = exportSales([sale(refunded: true)]);
    expect(rows.first, ['รายงานการขาย', 'ร้าน, "ทดสอบ"\nสาขา 1']);
    expect(rows.firstWhere((r) => r.first == 'เลขประจำตัวผู้เสียภาษี')[1],
        '0012345678901');
    final detail = rows.last;
    expect(detail.length, 17);
    expect(detail[3], 'ACME "Branch", East\nชั้น 2');
    expect(detail[16], 'เสียหาย, "คืน"\nตรวจแล้ว');
    expect(detail[15], '30/10/2026 11:00:00');
  });
  test(
      'net detail revenue/cost/profit reconcile with summary including refunds and fractional quantities',
      () {
    final rows = exportSales([
      sale(id: 'a', quantity: 0.5),
      sale(id: 'b', quantity: 0.5),
      sale(id: 'r', refunded: true)
    ]);
    final header = rows.indexWhere((r) => r.first == 'ลำดับ');
    final details = rows.skip(header + 1);
    double sum(int col) =>
        details.fold(0, (v, row) => v + double.parse(row[col]));
    double summary(String name) =>
        double.parse(rows.firstWhere((r) => r.first == name)[1]);
    expect(sum(8), summary('รายได้สุทธิ'));
    expect(
        sumReportMoney(
            [sale(quantity: 0.5), sale(quantity: 0.5)].map(reportSaleCost)),
        summary('ต้นทุนสินค้าขาย (COGS)'));
    expect(sum(11), closeTo(summary('ต้นทุนสินค้าขาย (COGS)'), 0.000001));
    expect(sum(12), closeTo(summary('กำไรขั้นต้น'), 0.000001));
    expect(rows.last.sublist(6, 13),
        ['100.00', '100.00', '0.00', '40.01', '40.01', '0.00', '0.00']);
  });
  test('unknown cost is explicit, not a misleading zero profit', () {
    final rows = exportSales([sale(known: false)]);
    expect(rows.firstWhere((r) => r.first == 'กำไรขั้นต้น')[1], 'ต้นทุนไม่ครบ');
    expect(rows.last[11], 'ต้นทุนไม่ครบ');
    expect(rows.last[12], 'ต้นทุนไม่ครบ');
  });
  test(
      'sales export states original-day refund basis and zero for empty periods',
      () {
    final rows = exportSales([]);
    expect(rows.firstWhere((r) => r.first == 'ฐานรายงาน')[1], salesReportBasis);
    expect(rows.firstWhere((r) => r.first == 'รายได้สุทธิ')[1], '0.00');
  });
  test(
      'movement export bridges a next-day refund, debt collection and manual cash',
      () {
    final day = DateTime(2026, 10, 30);
    final rows =
        readCsv(buildMovementReportCsv(day: day, generatedAt: day, sales: {
      's1': {'createdAt': DateTime(2026, 10, 29, 10)}
    }, rows: [
      {
        'id': 'r',
        'saleId': 's1',
        'kind': 'refund',
        'method': 'cash',
        'recordedAt': day,
        'occurredAt': day,
        'amountMinor': -10000,
        'salesMinor': -10000,
        'debtMinor': 0,
        'reason': '=1+1'
      },
      {
        'id': 'd',
        'saleId': 'missing',
        'kind': 'debtPayment',
        'method': 'cash',
        'recordedAt': day,
        'amountMinor': 2500,
        'salesMinor': 0,
        'debtMinor': -2500
      },
      {
        'id': 'i',
        'kind': 'cashIn',
        'method': 'cash',
        'recordedAt': day,
        'amountMinor': 500,
        'needsReconciliation': true
      },
    ]));
    expect(rows.firstWhere((r) => r.first.startsWith('รับชำระสุทธิ'))[1],
        '-75.00');
    expect(
        rows.firstWhere((r) => r.first.startsWith('เงินสดเพิ่ม'))[1], '-70.00');
    expect(
        rows.firstWhere((r) => r.first == 'ยอดขายเพิ่ม / ลดตามรายการเงิน')[1],
        '-100.00');
    final refund = rows.firstWhere((r) => r.first == 'r');
    expect(refund[1], '30/10/2026 00:00:00');
    expect(refund[6], '29/10/2026 10:00:00');
    expect(refund[8], '-100.00');
    expect(refund[13], "'=1+1");
    expect(rows.firstWhere((r) => r.first == 'd')[7], 'ไม่พบข้อมูลบิลเดิม');
    expect(rows.firstWhere((r) => r.first == 'i')[12], 'รอจัดเข้ารอบ');
  });
}
