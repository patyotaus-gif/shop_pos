import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';

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
    final name = info['name'] ?? 'ร้าน';
    final fontRegular = await PdfGoogleFonts.notoSansThaiRegular();
    final fontBold = await PdfGoogleFonts.notoSansThaiBold();
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold),
    );

    final overShort = summary.overShort(countedCash);

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
            pw.Text('เปิดรอบ: ${_dt.format(session.openedAt)}',
                style: const pw.TextStyle(fontSize: 8)),
            pw.Text('ปิดรอบ: ${_dt.format(DateTime.now())}',
                style: const pw.TextStyle(fontSize: 8)),
            pw.Divider(),
            _row('จำนวนบิล', '${summary.billCount}'),
            _row('ยอดขายรวม', _baht.format(summary.grossTotal), bold: true),
            pw.SizedBox(height: 4),
            pw.Text('แยกตามวิธีจ่าย',
                style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
            for (final m in PaymentMethod.values)
              if ((summary.byMethod[m.name] ?? 0) > 0)
                _row('  ${m.label}', _baht.format(summary.byMethod[m.name]!)),
            if (summary.debtTotal > 0)
              _row('  เชื่อ (ยังไม่ได้เงิน)', _baht.format(summary.debtTotal)),
            if (summary.refundTotal > 0)
              _row('  คืนเงิน', '-${_baht.format(summary.refundTotal)}'),
            pw.Divider(),
            pw.Text('เงินสดในลิ้นชัก',
                style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
            _row('  เงินทอนเริ่มต้น', _baht.format(summary.openingFloat)),
            _row('  ขายเงินสด', _baht.format(summary.cashSales)),
            _row('  ควรมี', _baht.format(summary.expectedCash), bold: true),
            _row('  นับได้จริง', _baht.format(countedCash), bold: true),
            _row(
              overShort >= 0 ? '  เกิน' : '  ขาด',
              _baht.format(overShort.abs()),
              bold: true,
            ),
            pw.SizedBox(height: 8),
            pw.Center(
                child: pw.Text('— จบรายงาน —',
                    style: const pw.TextStyle(fontSize: 8))),
          ],
        ),
      ),
    );

    await Printing.sharePdf(
        bytes: await doc.save(), filename: 'zreport_${session.id}.pdf');
  }

  static pw.Row _row(String label, String value, {bool bold = false}) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label,
              style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          pw.Text(value,
              style: pw.TextStyle(
                  fontSize: 10,
                  fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        ],
      );
}
