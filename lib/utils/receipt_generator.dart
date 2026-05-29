import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../models/sale.dart';

class ReceiptGenerator {
  static final _baht = NumberFormat('#,##0.00', 'th_TH');
  static final _date = DateFormat('dd/MM/yyyy HH:mm', 'th_TH');

  static Future<void> printReceipt(Sale sale, {String shopName = 'ร้านของชำ'}) async {
    // Load NotoSansThai so Thai characters don't render as tofu boxes
    // (Helvetica — pdf package's default — has no Thai glyphs at all).
    final fontRegular = await PdfGoogleFonts.notoSansThaiRegular();
    final fontBold = await PdfGoogleFonts.notoSansThaiBold();

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(
        base: fontRegular,
        bold: fontBold,
      ),
    );

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(58 * PdfPageFormat.mm, double.infinity,
            marginAll: 4 * PdfPageFormat.mm),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Center(
              child: pw.Text(shopName,
                  style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            ),
            pw.Center(child: pw.Text(_date.format(sale.createdAt), style: const pw.TextStyle(fontSize: 9))),
            pw.Divider(),
            ...sale.items.map(
              (item) => pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Expanded(
                    child: pw.Text('${item.productName} x${item.quantity}',
                        style: const pw.TextStyle(fontSize: 9)),
                  ),
                  pw.Text(_baht.format(item.subtotal),
                      style: const pw.TextStyle(fontSize: 9)),
                ],
              ),
            ),
            pw.Divider(),
            if (sale.discount > 0)
              _row('ส่วนลด', '-${_baht.format(sale.discount)}'),
            _row('รวม', _baht.format(sale.total), bold: true),
            if (!sale.isDebt) ...[
              _row('รับเงิน', _baht.format(sale.paid)),
              _row('เงินทอน', _baht.format(sale.change)),
            ],
            if (sale.isDebt)
              pw.Center(
                child: pw.Text('** เชื่อ: ${sale.customerName} **',
                    style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
              ),
            pw.SizedBox(height: 8),
            pw.Center(child: pw.Text('ขอบคุณที่ใช้บริการ', style: const pw.TextStyle(fontSize: 9))),
          ],
        ),
      ),
    );

    await Printing.sharePdf(bytes: await pdf.save(), filename: 'receipt_${sale.id}.pdf');
  }

  static pw.Row _row(String label, String value, {bool bold = false}) => pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(label,
              style: pw.TextStyle(
                  fontSize: 10, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
          pw.Text(value,
              style: pw.TextStyle(
                  fontSize: 10, fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        ],
      );
}
