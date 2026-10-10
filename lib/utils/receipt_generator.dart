import 'package:flutter/services.dart';

import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../models/sale.dart';
import '../models/receipt_profile.dart';
import '../services/settings_service.dart';

class ReceiptGenerator {
  static final _baht = NumberFormat('#,##0.00', 'th_TH');
  static String saleDate(DateTime date) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(date.day)}/${two(date.month)}/${date.year + 543} '
        '${two(date.hour)}:${two(date.minute)}:${two(date.second)}';
  }

  static String documentNumber(Sale sale) =>
      sale.receiptNo?.trim().isNotEmpty == true ? sale.receiptNo! : sale.id;

  /// Print/share a 58mm receipt. Shop name, address, tax id and logo are
  /// pulled from settings here so callers only pass the sale.
  static Future<void> printReceipt(Sale sale, {String? shopName}) async {
    await Printing.sharePdf(
        bytes: await buildReceipt(sale, shopName: shopName),
        filename: 'receipt_${sale.receiptNo ?? sale.id}.pdf');
  }

  static Future<Uint8List> buildReceipt(Sale sale, {String? shopName}) async {
    // Never retroactively declare VAT for legacy sales without a tax snapshot.
    final profile = sale.receiptProfile ??
        ReceiptProfile.fromSettings({
          ...await SettingsService.getSettings(),
          if (shopName != null) 'name': shopName,
        }, allowVat: false);
    return buildDocument(sale,
        profile: profile, logo: await _loadLogo(profile.logoUrl));
  }

  /// The preview, printed receipt, shared PDF and saved file use this layout.
  static Future<Uint8List> buildDocument(Sale sale,
      {required ReceiptProfile profile,
      Uint8List? logo,
      double paperWidthMm = 58}) async {
    if (paperWidthMm != 58 && paperWidthMm != 80) {
      throw ArgumentError.value(
          paperWidthMm, 'paperWidthMm', 'Use 58 or 80 mm');
    }
    final vat = profile.includedVat(sale.total);

    final fontRegular = pw.Font.ttf(
        await rootBundle.load('assets/fonts/IBMPlexSansThai-Regular.ttf'));
    final fontBold = pw.Font.ttf(
        await rootBundle.load('assets/fonts/IBMPlexSansThai-Bold.ttf'));

    final pdf = pw.Document(
      theme: pw.ThemeData.withFont(base: fontRegular, bold: fontBold),
    );

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat(
            paperWidthMm * PdfPageFormat.mm, double.infinity,
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
              child: pw.Text(profile.name,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(
                      fontSize: 14, fontWeight: pw.FontWeight.bold)),
            ),
            if (profile.address.isNotEmpty)
              pw.Center(
                child: pw.Text(profile.address,
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(fontSize: 8)),
              ),
            if (profile.taxId.isNotEmpty)
              pw.Center(
                child: pw.Text('เลขประจำตัวผู้เสียภาษี ${profile.taxId}',
                    textAlign: pw.TextAlign.center,
                    style: const pw.TextStyle(fontSize: 8)),
              ),
            for (final text in [
              profile.branch,
              if (profile.phone.isNotEmpty) 'โทร. ${profile.phone}',
              profile.website
            ])
              if (text.isNotEmpty)
                pw.Center(
                    child: pw.Text(text,
                        textAlign: pw.TextAlign.center,
                        style: const pw.TextStyle(fontSize: 8))),
            pw.SizedBox(height: 8),
            pw.Center(
                child: pw.Text(
                    sale.isDebt ? 'ใบแจ้งยอดขายเชื่อ' : 'ใบเสร็จรับเงิน',
                    style: pw.TextStyle(
                        fontSize: 11, fontWeight: pw.FontWeight.bold))),
            if (profile.vatEnabled)
              pw.Center(
                child: pw.Text('ใบกำกับภาษีอย่างย่อ',
                    style: pw.TextStyle(
                        fontSize: 11, fontWeight: pw.FontWeight.bold)),
              ),
            if (sale.isRefunded)
              pw.Center(
                  child: pw.Text('บิลนี้คืนเงินแล้ว',
                      style: pw.TextStyle(
                          fontSize: 10, fontWeight: pw.FontWeight.bold))),
            pw.SizedBox(height: 8),
            pw.Text('เลขที่เอกสาร: ${documentNumber(sale)}',
                style: const pw.TextStyle(fontSize: 8)),
            pw.Text('วันที่ขาย: ${saleDate(sale.createdAt)}',
                style: const pw.TextStyle(fontSize: 8)),
            if (sale.staffName?.trim().isNotEmpty == true)
              pw.Text('พนักงานขาย: ${sale.staffName}',
                  style: const pw.TextStyle(fontSize: 8)),
            if (sale.tableName != null)
              pw.Center(
                child: pw.Text('โต๊ะ ${sale.tableName}',
                    style: const pw.TextStyle(fontSize: 9)),
              ),
            pw.Divider(),
            _row('รายการ / จำนวน × ราคาต่อหน่วย', 'รวมเงิน', fontSize: 7),
            pw.SizedBox(height: 4),
            ...sale.items.map(
              (item) => pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(item.productName,
                      style: pw.TextStyle(
                          fontSize: 9, fontWeight: pw.FontWeight.bold)),
                  pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Expanded(
                        child: pw.Text(
                            '${item.quantity} × ${_baht.format(item.quantity > 0 ? item.subtotal / item.quantity : item.price)}',
                            style: const pw.TextStyle(fontSize: 8)),
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
                  if (item.notes != null && item.notes!.isNotEmpty)
                    pw.Text(item.notes!,
                        style: const pw.TextStyle(fontSize: 8)),
                  pw.SizedBox(height: 5),
                ],
              ),
            ),
            pw.Divider(),
            pw.Text(
                'รายการ: ${sale.items.length}   จำนวนชิ้น: ${sale.items.fold<int>(0, (n, i) => n + i.quantity)}',
                style: const pw.TextStyle(fontSize: 8)),
            pw.SizedBox(height: 4),
            _row('รวมค่าสินค้า', _baht.format(sale.itemsSubtotal)),
            if (sale.discount > 0)
              _row('ส่วนลด', '-${_baht.format(sale.discount)}'),
            if (sale.serviceCharge > 0)
              _row('ค่าบริการ', _baht.format(sale.serviceCharge)),
            _row('รวมทั้งสิ้น', _baht.format(sale.total), bold: true),
            if (profile.vatEnabled) ...[
              pw.Divider(),
              _row('มูลค่าก่อนภาษี', _baht.format(vat.netMinor / 100),
                  fontSize: 9),
              _row('ภาษีมูลค่าเพิ่ม ${_baht.format(profile.vatRate)}%',
                  _baht.format(vat.vatMinor / 100),
                  fontSize: 9),
              pw.Text('ราคานี้รวมภาษีมูลค่าเพิ่มแล้ว',
                  style: const pw.TextStyle(fontSize: 8)),
            ],
            pw.Divider(),
            if (sale.splitCount > 1)
              _row(
                'แยก ${sale.splitCount} คน',
                '${_baht.format(sale.total / sale.splitCount)} / คน',
              ),
            if (!sale.isDebt) ...[
              _row(sale.paymentMethod.label, _baht.format(sale.paid)),
              if (sale.paymentMethod == PaymentMethod.cash)
                _row('เงินทอน', _baht.format(sale.change)),
            ],
            if (sale.isDebt)
              pw.Center(
                child: pw.Text('** เชื่อ: ${sale.customerName} **',
                    style: pw.TextStyle(
                        fontSize: 10, fontWeight: pw.FontWeight.bold)),
              ),
            pw.SizedBox(height: 8),
            pw.Center(
                child: pw.Text('ขอบคุณที่ใช้บริการ',
                    style: const pw.TextStyle(fontSize: 9))),
          ],
        ),
      ),
    );

    return pdf.save();
  }

  /// Fetch the shop logo bytes (settings.logoUrl) for the receipt header.
  /// Best-effort — null on any failure so the receipt still prints.
  static Future<Uint8List?> _loadLogo(String url) async {
    try {
      if (url.isEmpty) return null;
      final res =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 5));
      return res.statusCode == 200 ? res.bodyBytes : null;
    } catch (_) {
      return null;
    }
  }

  static pw.Row _row(String label, String value,
          {bool bold = false, double fontSize = 10}) =>
      pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Expanded(
              child: pw.Text(label,
                  style: pw.TextStyle(
                      fontSize: fontSize,
                      fontWeight:
                          bold ? pw.FontWeight.bold : pw.FontWeight.normal))),
          pw.SizedBox(width: 4),
          pw.Text(value,
              style: pw.TextStyle(
                  fontSize: fontSize,
                  fontWeight:
                      bold ? pw.FontWeight.bold : pw.FontWeight.normal)),
        ],
      );
}
