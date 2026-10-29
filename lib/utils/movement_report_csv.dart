import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'csv_export.dart';

String movementKindLabel(Object? kind) => switch (kind) {
      'sale' => 'ขายสินค้า',
      'debtPayment' => 'รับชำระหนี้',
      'refund' => 'คืนเงิน',
      'cashIn' => 'เงินสดเข้า',
      'cashOut' => 'เงินสดออก',
      _ => 'รายการเงิน',
    };
String movementMethodLabel(Object? method) => switch (method) {
      'cash' => 'เงินสด',
      'transfer' => 'โอนเงิน',
      'qr' => 'QR Code',
      'credit' => 'ขายเชื่อ',
      'online' => 'ออนไลน์',
      _ => 'ไม่ระบุ',
    };

String buildMovementReportCsv({
  required List<Map<String, dynamic>> rows,
  required Map<String, Map<String, dynamic>> sales,
  required DateTime day,
  required DateTime generatedAt,
}) {
  final date = DateFormat('dd/MM/yyyy HH:mm:ss');
  String stamp(Object? value) => value is Timestamp
      ? date.format(value.toDate())
      : value is DateTime
          ? date.format(value)
          : '';
  int cents(Map row, String key) => (row[key] as num? ?? 0).toInt();
  int total(String key) => rows.fold<int>(0, (v, row) => v + cents(row, key));
  final received = rows
      .where((r) => !['cashIn', 'cashOut'].contains(r['kind']))
      .fold<int>(0, (v, r) => v + cents(r, 'amountMinor'));
  final cash = rows
      .where((r) => r['method'] == 'cash')
      .fold<int>(0, (v, r) => v + cents(r, 'amountMinor'));
  final out = StringBuffer();
  void row(List<Object?> cells) => out.writeln(csvRow(cells));
  CsvMoney money(int value) => CsvMoney(value / 100);
  row(['รายงานเงินเข้า–ออก', DateFormat('dd/MM/yyyy').format(day)]);
  row(['ฐานรายงาน', movementReportBasis]);
  row(['ส่งออกเมื่อ', date.format(generatedAt)]);
  row([
    'เขตเวลาเครื่อง',
    generatedAt.timeZoneName,
    generatedAt.timeZoneOffset.toString()
  ]);
  row(['รับชำระสุทธิ (ไม่รวมเงินเข้า–ออกที่บันทึกเอง)', money(received)]);
  row(['เงินสดเพิ่ม / ลด (ไม่รวมเงินทอนเริ่มต้น)', money(cash)]);
  row(['ยอดขายเพิ่ม / ลดตามรายการเงิน', money(total('salesMinor'))]);
  row(['ลูกหนี้เพิ่ม / ลด', money(total('debtMinor'))]);
  row([
    'รายการรอจัดเข้ารอบ',
    rows.where((r) => r['needsReconciliation'] == true).length
  ]);
  row([
    'หมายเหตุ',
    'ยอดเงินสดเพิ่ม/ลดไม่ใช่ยอดเงินในลิ้นชัก ดูยอดจริงและรายการยกมาที่ใบปิดรอบ'
  ]);
  row([]);
  row([
    'เลขรายการเงิน',
    'วันที่บันทึก',
    'วันที่เกิดรายการ',
    'ประเภท',
    'วิธีชำระ',
    'เลขอ้างอิงบิล',
    'วันที่ขายเดิม',
    'สถานะข้อมูลบิล',
    'เงินรับ / จ่าย',
    'ยอดขายเพิ่ม / ลด',
    'ลูกหนี้เพิ่ม / ลด',
    'รหัสรอบ',
    'การจัดเข้ารอบ',
    'เหตุผล',
    'รวมอยู่ในเงินทอนเริ่มต้นแล้ว'
  ]);
  for (final r in rows) {
    final saleId = r['saleId'] as String?;
    final sale = sales[saleId];
    row([
      r['id'],
      stamp(r['recordedAt']),
      stamp(r['occurredAt']),
      movementKindLabel(r['kind']),
      movementMethodLabel(r['method']),
      saleId,
      stamp(sale?['createdAt']),
      saleId == null
          ? 'ไม่มีบิลอ้างอิง'
          : sale == null
              ? 'ไม่พบข้อมูลบิลเดิม'
              : 'พบข้อมูล',
      money(cents(r, 'amountMinor')),
      money(cents(r, 'salesMinor')),
      money(cents(r, 'debtMinor')),
      r['sessionId'],
      r['needsReconciliation'] == true ? 'รอจัดเข้ารอบ' : 'บันทึกแล้ว',
      r['reason'],
      r['reconciliation'] is Map &&
              r['reconciliation']['cashTreatment'] == 'includedInOpeningFloat'
          ? 'ใช่'
          : 'ไม่ใช่'
    ]);
  }
  return out.toString();
}
