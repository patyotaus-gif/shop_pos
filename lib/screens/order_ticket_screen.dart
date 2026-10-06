import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/order.dart';

/// Preparation ticket, deliberately separate from a paid sale receipt.
class OrderTicketScreen extends StatelessWidget {
  const OrderTicketScreen({super.key, required this.order});
  final ShopOrder order;

  Future<Uint8List> _build(PdfPageFormat _) async {
    final font = pw.Font.ttf(
        await rootBundle.load('assets/fonts/IBMPlexSansThai-Regular.ttf'));
    final bold = pw.Font.ttf(
        await rootBundle.load('assets/fonts/IBMPlexSansThai-Bold.ttf'));
    final pdf =
        pw.Document(theme: pw.ThemeData.withFont(base: font, bold: bold));
    pdf.addPage(pw.MultiPage(
        pageFormat: PdfPageFormat.a5,
        margin: const pw.EdgeInsets.all(20),
        build: (_) => [
              pw.Text(
                  'ใบงานออเดอร์ • ${order.tableName == null ? 'รับกลับบ้าน' : 'โต๊ะ ${order.tableName}'}',
                  style: pw.TextStyle(
                      fontWeight: pw.FontWeight.bold, fontSize: 18)),
              pw.Text('เลขออเดอร์ ${order.id}'),
              pw.Text('${order.customerName} • ${order.customerPhone}'),
              if (order.pickupDescription != null)
                pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(vertical: 10),
                    child: pw.Text(order.pickupDescription!,
                        style: pw.TextStyle(
                            fontWeight: pw.FontWeight.bold, fontSize: 16))),
              pw.Text('สถานะ: ${order.status.label}'),
              pw.Divider(),
              for (final item in order.items)
                pw.Padding(
                    padding: const pw.EdgeInsets.only(bottom: 8),
                    child: pw.Column(
                        crossAxisAlignment: pw.CrossAxisAlignment.start,
                        children: [
                          pw.Text('${item.productName} × ${item.quantity}',
                              style: const pw.TextStyle(fontSize: 14)),
                          if (item.preparationNote.isNotEmpty)
                            pw.Text(item.preparationNote),
                        ])),
              pw.Divider(),
              pw.Text('ใบงานเตรียมสินค้า ไม่ใช่ใบเสร็จรับเงิน'),
            ]));
    return pdf.save();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('ใบงานออเดอร์ / นัดรับ')),
        body: PdfPreview(
            build: _build,
            pdfFileName: 'order_${order.id}.pdf',
            canChangePageFormat: false,
            canChangeOrientation: false,
            allowPrinting: true,
            allowSharing: true),
      );
}
