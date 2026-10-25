import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';

import '../models/cash_session.dart';
import '../models/sale.dart';
import '../services/settings_service.dart';

/// Z-report — the end-of-day summary printed/shared when a cash session
/// closes. 58mm like the receipt.
class ZReportGenerator {
  static final _baht = NumberFormat('#,##0.00', 'th_TH');
  static final _dt = DateFormat('dd/MM/yyyy HH:mm', 'th_TH');

  static Future<void> print({
    required CashSession session,
    required SessionSummary summary,
    required double countedCash,
  }) async {
    final info = await SettingsService.getShopInfo();
    await Printing.sharePdf(
        bytes: await build(
            session: session,
            summary: summary,
            countedCash: countedCash,
            info: info),
        filename: 'zreport_${session.id}.pdf');
  }

  static Future<Uint8List> build(
      {required CashSession session,
      required SessionSummary summary,
      required double countedCash,
      required Map<String, String> info}) async {
    final name = info['name'] ?? 'ร้าน';
    final fontRegular = pw.Font.ttf(
        await rootBundle.load('assets/fonts/IBMPlexSansThai-Regular.ttf'));
    final fontBold = pw.Font.ttf(
        await rootBundle.load('assets/fonts/IBMPlexSansThai-Bold.ttf'));
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold),
    );

    final overShort = summary.overShort(countedCash);
    final report = summary.report;

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(58 * PdfPageFormat.mm, double.infinity,
            marginAll: 4 * PdfPageFormat.mm),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Center(
                child: pw.Text(name,
                    style: pw.TextStyle(
                        fontSize: 14, fontWeight: pw.FontWeight.bold))),
            pw.Center(
                child: pw.Text('สรุปยอดปิดรอบ (Z)',
                    style: pw.TextStyle(
                        fontSize: 11, fontWeight: pw.FontWeight.bold))),
            pw.SizedBox(height: 4),
            pw.Text('เลขอ้างอิงรอบ: ${session.id}',
                style: const pw.TextStyle(fontSize: 8)),
            if ((info['taxId'] ?? '').isNotEmpty)
              pw.Text('เลขประจำตัวผู้เสียภาษีอากร: ${info['taxId']}',
                  style: const pw.TextStyle(fontSize: 8)),
            pw.Text('เปิดรอบ: ${_dt.format(session.openedAt)}',
                style: const pw.TextStyle(fontSize: 8)),
            pw.Text(
                'ปิดรอบ: ${session.closedAt == null ? 'ยังไม่ปิดรอบ' : _dt.format(session.closedAt!)}',
                style: const pw.TextStyle(fontSize: 8)),
            pw.Divider(),
            pw.Text('ผู้เปิด: ${session.openedByName ?? 'ไม่บันทึกชื่อ'}',
                style: const pw.TextStyle(fontSize: 8)),
            pw.Text('รหัสบัญชี: ${session.openedBy ?? 'ไม่บันทึก'}',
                style: const pw.TextStyle(fontSize: 8)),
            pw.Text('ผู้ปิด: ${session.closedByName ?? 'ไม่บันทึกชื่อ'}',
                style: const pw.TextStyle(fontSize: 8)),
            pw.Text('รหัสบัญชี: ${session.closedBy ?? 'ไม่บันทึก'}',
                style: const pw.TextStyle(fontSize: 8)),
            if (report != null)
              for (final cashier in (report['cashiers'] as List? ?? []))
                pw.Text(
                    'แคชเชียร์: ${cashier['name']} · รหัส ${cashier['id'] ?? 'ไม่บันทึก'}',
                    style: const pw.TextStyle(fontSize: 8)),
            pw.Divider(),
            pw.Text('สรุปยอดขาย',
                style:
                    pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
            _row('จำนวนบิล', '${summary.billCount}'),
            if (report?['complete'] == true) ...[
              _row('ยอดก่อนส่วนลด',
                  _baht.format(report!['salesBeforeDiscount'])),
              _row('ส่วนลดรวม',
                  _minus((report['discountTotal'] as num).toDouble())),
              if (report['serviceCharge'] != 0)
                _row('ค่าบริการ', _baht.format(report['serviceCharge'])),
              if (report['paymentAdjustment'] != 0)
                _row('ยอดปรับการชำระ',
                    _baht.format(report['paymentAdjustment'])),
              _row('ยอดขายที่คืน',
                  _minus((report['returnedSales'] as num).toDouble())),
            ] else
              pw.Text('ไม่มีรายละเอียดส่วนลดครบถ้วนสำหรับรอบนี้',
                  style: const pw.TextStyle(fontSize: 8)),
            _row(session.accountingVersion == 1 ? 'ยอดขายสุทธิ' : 'ยอดขายรวม',
                _baht.format(summary.grossTotal),
                bold: true),
            _row('รับชำระหนี้', _baht.format(summary.debtCollections)),
            if (summary.futureOrderCount > 0) ...[
              _row('นัดรับวันถัดไป', '${summary.futureOrderCount} ออเดอร์'),
              pw.Text(
                  'เงินที่รับแล้วรวมตามรอบที่รับเงิน ออเดอร์ยังเก็บไว้ทำต่อ',
                  style: const pw.TextStyle(fontSize: 9)),
            ],
            if (summary.pendingOrderCount > 0 ||
                summary.openTableCount > 0) ...[
              pw.Text('ยังไม่รวมในยอดขายรอบนี้',
                  style: const pw.TextStyle(fontSize: 9)),
              _row('  ออเดอร์รอชำระ', '${summary.pendingOrderCount}'),
              _row('  บิลโต๊ะที่ยังเปิด', '${summary.openTableCount}'),
            ],
            pw.SizedBox(height: 4),
            pw.Text('รับเงินหักคืน แยกวิธีจ่าย',
                style:
                    pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
            for (final m in PaymentMethod.values)
              _row('  ${m.label}', _baht.format(summary.byMethod[m.name] ?? 0)),
            for (final entry in summary.byMethod.entries.where(
                (e) => !PaymentMethod.values.any((m) => m.name == e.key)))
              _row(entry.key, _baht.format(entry.value)),
            pw.Text('ยอดออนไลน์อาจรวมบัตร/วอลเล็ต หากไม่ได้บันทึกแยกประเภท',
                style: const pw.TextStyle(fontSize: 8)),
            if (report != null) ...[
              pw.Divider(),
              pw.Text('ช่องทางขาย (ก่อนหักคืน)',
                  style: pw.TextStyle(
                      fontSize: 9, fontWeight: pw.FontWeight.bold)),
              for (final channel in SalesChannel.values)
                if ((report['byChannel'] as Map?)?.containsKey(channel.name) ==
                    true)
                  _row(channel.label,
                      _baht.format(report['byChannel'][channel.name])),
              pw.Text('รายการพิเศษ',
                  style: pw.TextStyle(
                      fontSize: 9, fontWeight: pw.FontWeight.bold)),
              pw.Text('ยกเลิกก่อนขาย: ไม่มีข้อมูลจำนวนในรายงานรอบนี้',
                  style: const pw.TextStyle(fontSize: 8)),
              _row('บิลคืนสินค้า',
                  '${report['refundBillCount']}${report['complete'] == true ? '' : ' (ข้อมูลไม่ครบ)'}'),
              for (final item in (report['returnedItems'] as List? ?? []))
                _row(item['name'] as String,
                    '${item['quantity']} ${item['unit']}'),
              if (report['returnedItemsTruncated'] == true)
                pw.Text(
                    'แสดงสินค้า 100 รายการแรก ตรวจรายละเอียดเพิ่มเติมในประวัติคืนสินค้า',
                    style: const pw.TextStyle(fontSize: 8)),
            ],
            if (summary.debtTotal != 0)
              _row(
                  session.accountingVersion == 1
                      ? '  หนี้เพิ่ม/ลดในรอบ'
                      : '  ขายเชื่อ',
                  _baht.format(summary.debtTotal)),
            if (summary.refundTotal > 0)
              _row('  คืนเงิน', '-${_baht.format(summary.refundTotal)}'),
            pw.Divider(),
            pw.Text('สรุปเงินสดในลิ้นชัก',
                style:
                    pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
            _row('  เงินทอนเริ่มต้นกะ', _baht.format(summary.openingFloat)),
            _row('  ยอดขายเงินสด', _baht.format(summary.cashSales)),
            if (summary.cashDebtCollections != null)
              _row('  รับหนี้เป็นเงินสด',
                  _baht.format(summary.cashDebtCollections)),
            if (summary.cashRefunds != null)
              _row('  คืนเงินสด', _minus(summary.cashRefunds!)),
            if (summary.cashDebtCollections == null ||
                summary.cashRefunds == null)
              pw.Text(
                  'รอบเก่าไม่แยกเงินสดรับหนี้/คืนเงิน คงเหลือตามระบบใช้ยอดที่บันทึกตอนปิดรอบ',
                  style: const pw.TextStyle(fontSize: 8)),
            _row('  รับเข้า', _baht.format(summary.cashIn)),
            _row('  จ่ายออก', _minus(summary.cashOut)),
            _row('  คงเหลือตามระบบ', _baht.format(summary.expectedCash),
                bold: true),
            if (summary.reconciledCount > 0)
              _row('  ตรวจแล้วนำเข้ารอบ', '${summary.reconciledCount} รายการ'),
            if (summary.openingCashIncluded != 0)
              _row('  รวมในเงินตั้งต้นแล้ว',
                  _baht.format(summary.openingCashIncluded)),
            _row('  นับได้จริง', _baht.format(countedCash), bold: true),
            _row(
              '  ผลต่าง',
              _baht.format(overShort),
              bold: true,
            ),
            pw.Text('สถานะ: ${summary.cashStatus(countedCash)}',
                style:
                    pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
            pw.SizedBox(height: 8),
            pw.Center(
                child: pw.Text('— จบรายงาน —',
                    style: const pw.TextStyle(fontSize: 8))),
          ],
        ),
      ),
    );

    return doc.save();
  }

  static String _minus(double value) =>
      value == 0 ? '0.00' : '-${_baht.format(value)}';

  static pw.Row _row(String label, String value, {bool bold = false}) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
              child: pw.Text(label,
                  style: pw.TextStyle(
                      fontSize: 10,
                      fontWeight:
                          bold ? pw.FontWeight.bold : pw.FontWeight.normal))),
          pw.SizedBox(width: 4),
          pw.Text(value,
              style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight:
                      bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        ],
      );
}
