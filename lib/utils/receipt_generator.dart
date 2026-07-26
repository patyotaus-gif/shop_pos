import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../models/sale.dart';
import '../services/settings_service.dart';

class ReceiptGenerator {
  static final _baht = NumberFormat('#,##0.00', 'th_TH');
  static final _date = DateFormat('dd/MM/yyyy HH:mm', 'th_TH');

  /// Print/share a 58mm receipt. Shop name, address, tax id and logo are
  /// pulled from settings here so callers only pass the sale.
  static Future<void> printReceipt(Sale sale, {String? shopName}) async {
    final info = await SettingsService.getShopInfo();
    final name = shopName ?? info['name'] ?? 'ร้านของชำ';
    final address = (info['address'] ?? '').trim();
    final taxId = (info['taxId'] ?? '').trim();
    final logo = await _loadLogo();

    final fontRegular = await PdfGoogleFonts.notoSansThaiRegular();
    final fontBold = await PdfGoogleFonts.notoSansThaiBold();

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold),
    );

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(58 * PdfPageFormat.mm, double.infinity,
            marginAll: 4 * PdfPageFormat.mm),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            if (logo != null)
              pw.Center(
                child: pw.Container(
                  height: 40,
                  margin: const pw.EdgeInsets.only(bottom: 4),
                  child: pw.Image(pw.MemoryImage(logo), fit: pw.BoxFit.contain),
                ),
              ),
            pw.Center(
              child: pw.Text(name,
                  style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold)),
            ),
            if (address.isNotEmpty)
              pw.Center(
                child: pw.Text(address,
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(fontSize: 8)),
              ),
            if (taxId.isNotEmpty)
              pw.Center(
                child: pw.Text('เลขผู้เสียภาษี $taxId',
                    style: const pw.TextStyle(fontSize: 8)),
              ),
            pw.SizedBox(height: 2),
            pw.Center(child: pw.Text(_date.format(sale.createdAt), style: const pw.TextStyle(fontSize: 9))),
            if (sale.receiptNo != null)
              pw.Center(
                child: pw.Text('เลขที่ ${sale.receiptNo}',
                    style: pw.TextStyle(
                        fontSize: 9, fontWeight: pw.FontWeight.bold)),
              ),
            if (sale.tableName != null)
              pw.Center(
                child: pw.Text('โต๊ะ ${sale.tableName}',
                    style: const pw.TextStyle(fontSize: 9)),
              ),
            pw.Divider(),
            ...sale.items.map(
              (item) => pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Expanded(
                        child: pw.Text(
                            '${item.productName} x${item.quantity}',
                            style: const pw.TextStyle(fontSize: 9)),
                      ),
                      pw.Text(_baht.format(item.subtotal),
                          style: const pw.TextStyle(fontSize: 9)),
                    ],
                  ),
                  if (item.modifiers.isNotEmpty)
                    pw.Padding(
                      padding: const pw.EdgeInsets.only(left: 8, top: 1),
                      child: pw.Text(
                        '• ${item.modifiers.map((m) => m.priceAdjust == 0 ? m.optionName : '${m.optionName} (${m.priceAdjust > 0 ? '+' : ''}${m.priceAdjust.toStringAsFixed(0)})').join(', ')}',
                        style: const pw.TextStyle(fontSize: 8),
                      ),
                    ),
                ],
              ),
            ),
            pw.Divider(),
            if (sale.serviceCharge > 0) ...[
              _row('ค่าสินค้า', _baht.format(sale.itemsSubtotal)),
              _row('Service charge', _baht.format(sale.serviceCharge)),
            ],
            if (sale.discount > 0)
              _row('ส่วนลด', '-${_baht.format(sale.discount)}'),
            _row('รวม', _baht.format(sale.total), bold: true),
            if (sale.splitCount > 1)
              _row(
                'แยก ${sale.splitCount} คน',
                '${_baht.format(sale.total / sale.splitCount)} / คน',
              ),
            if (!sale.isDebt) ...[
              _row('รับเงิน', _baht.format(sale.paid)),
              _row('เงินทอน', _baht.format(sale.change)),
            ],
            if (sale.isDebt)
              pw.Center(
                child: pw.Text('** เชื่อ: ${sale.customerName} **',
                    style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold)),
              ),
            if (sale.staffName != null)
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 4),
                child: pw.Text('พนักงาน: ${sale.staffName}',
                    style: const pw.TextStyle(fontSize: 8)),
              ),
            pw.SizedBox(height: 8),
            pw.Center(child: pw.Text('ขอบคุณที่ใช้บริการ', style: const pw.TextStyle(fontSize: 9))),
          ],
        ),
      ),
    );

    final fileTag = sale.receiptNo ?? sale.id;
    await Printing.sharePdf(bytes: await pdf.save(), filename: 'receipt_$fileTag.pdf');
  }

  /// Fetch the shop logo bytes (settings.logoUrl) for the receipt header.
  /// Best-effort — null on any failure so the receipt still prints.
  static Future<Uint8List?> _loadLogo() async {
    try {
      final settings = await SettingsService.getSettings();
      final url = (settings['logoUrl'] as String?) ?? '';
      if (url.isEmpty) return null;
      final res = await http.get(Uri.parse(url));
      return res.statusCode == 200 ? res.bodyBytes : null;
    } catch (_) {
      return null;
    }
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
