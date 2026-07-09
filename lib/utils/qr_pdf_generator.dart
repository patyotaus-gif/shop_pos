import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

/// Printable QR sheets for QR ordering (takeaway poster + per-table cards).
/// One A5 page per entry; QR uses error-correction H so the center logo
/// (≤20% of the symbol) never breaks scanning.
class QrPdfGenerator {
  static Future<void> printQrSheets({
    required String shopName,
    required List<({String label, String url})> entries,
    Uint8List? logoBytes,
  }) async {
    final fontRegular = await PdfGoogleFonts.notoSansThaiRegular();
    final fontBold = await PdfGoogleFonts.notoSansThaiBold();
    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold),
    );
    final logo = logoBytes != null ? pw.MemoryImage(logoBytes) : null;

    for (final e in entries) {
      doc.addPage(
        pw.Page(
          pageFormat: PdfPageFormat.a5,
          build: (ctx) => pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Text(shopName,
                  style: pw.TextStyle(
                      fontSize: 20, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 4),
              pw.Text('สแกนสั่งอาหาร',
                  style: const pw.TextStyle(
                      fontSize: 13, color: PdfColors.grey700)),
              pw.SizedBox(height: 18),
              pw.Stack(
                alignment: pw.Alignment.center,
                children: [
                  pw.BarcodeWidget(
                    barcode: pw.Barcode.qrCode(
                      errorCorrectLevel: pw.BarcodeQRCorrectionLevel.high,
                    ),
                    data: e.url,
                    width: 240,
                    height: 240,
                    drawText: false,
                  ),
                  if (logo != null)
                    pw.Container(
                      width: 44,
                      height: 44,
                      padding: const pw.EdgeInsets.all(3),
                      decoration: pw.BoxDecoration(
                        color: PdfColors.white,
                        borderRadius: pw.BorderRadius.circular(6),
                      ),
                      child: pw.Image(logo, fit: pw.BoxFit.contain),
                    ),
                ],
              ),
              pw.SizedBox(height: 22),
              pw.Text(e.label,
                  style: pw.TextStyle(
                      fontSize: 30, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 12),
              pw.Text(e.url,
                  style: const pw.TextStyle(
                      fontSize: 8, color: PdfColors.grey600)),
            ],
          ),
        ),
      );
    }

    await Printing.layoutPdf(onLayout: (_) => doc.save());
  }
}
