import 'package:flutter/services.dart';
import 'dart:math' as math;

import 'package:http/http.dart' as http;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../models/sale.dart';
import 'receipt_text_renderer.dart';
import '../models/receipt_profile.dart';
import '../services/settings_service.dart';

class ReceiptGenerator {
  static const slip58 = PdfPageFormat(58 * PdfPageFormat.mm, double.infinity,
      marginAll: 4 * PdfPageFormat.mm);
  static const slip80 = PdfPageFormat(80 * PdfPageFormat.mm, double.infinity,
      marginAll: 4 * PdfPageFormat.mm);
  static const paperFormats = <String, PdfPageFormat>{
    'สลิป 58 มม.': slip58,
    'สลิป 80 มม.': slip80,
    'A4': PdfPageFormat.a4,
  };

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

  static Future<Uint8List> buildReceipt(Sale sale,
      {String? shopName, PdfPageFormat? format}) async {
    // Never retroactively declare VAT for legacy sales without a tax snapshot.
    final profile = sale.receiptProfile ??
        ReceiptProfile.fromSettings({
          ...await SettingsService.getSettings(),
          if (shopName != null) 'name': shopName,
        }, allowVat: false);
    return buildDocument(sale,
        profile: profile,
        logo: await _loadLogo(profile.logoUrl),
        format: format);
  }

  /// The preview, printed receipt, shared PDF and saved file use this layout.
  static Future<Uint8List> buildDocument(Sale sale,
      {required ReceiptProfile profile,
      Uint8List? logo,
      double paperWidthMm = 58,
      PdfPageFormat? format}) async {
    if (paperWidthMm != 58 && paperWidthMm != 80) {
      throw ArgumentError.value(
          paperWidthMm, 'paperWidthMm', 'Use 58 or 80 mm');
    }
    final vat = profile.includedVat(sale.total);
    final requested = format ?? (paperWidthMm == 80 ? slip80 : slip58);
    if (!requested.width.isFinite ||
        requested.width < 32 * PdfPageFormat.mm ||
        requested.height.isNaN ||
        requested.height < 32 * PdfPageFormat.mm) {
      throw ArgumentError.value(format, 'format', 'Invalid receipt paper size');
    }
    final wide = requested.width > 100 * PdfPageFormat.mm;
    final margin = (wide ? 12 : 4) * PdfPageFormat.mm;
    final pageFormat = requested.copyWith(
      marginLeft: math.max(margin, requested.marginLeft),
      marginRight: math.max(margin, requested.marginRight),
      marginTop: math.max(margin, requested.marginTop),
      marginBottom: math.max(margin, requested.marginBottom),
    );
    final fontScale = wide ? 1.2 : 1.0;
    final renderer = ReceiptTextRenderer();
    final contentWidth = pageFormat.availableWidth;
    Future<pw.SizedBox> text(String value,
            {pw.TextStyle? style,
            pw.TextAlign textAlign = pw.TextAlign.left,
            double? maxWidth}) =>
        renderer.text(value,
            maxWidth: maxWidth ?? contentWidth,
            style: style,
            textAlign: textAlign);
    Future<pw.Widget> row(String label, String value,
        {bool bold = false, double fontSize = 10}) async {
      final style = pw.TextStyle(
          fontSize: fontSize * fontScale,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal);
      final amount =
          await text(value, maxWidth: contentWidth * .40, style: style);
      return pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            await text(label,
                maxWidth: contentWidth - amount.width! - 4, style: style),
            pw.SizedBox(width: 4),
            amount,
          ]);
    }

    final fontRegular = pw.Font.ttf(
        await rootBundle.load('assets/fonts/IBMPlexSansThai-Regular.ttf'));
    final fontBold = pw.Font.ttf(
        await rootBundle.load('assets/fonts/IBMPlexSansThai-Bold.ttf'));

    final theme = pw.ThemeData.withFont(base: fontRegular, bold: fontBold);
    final pdf = pw.Document(
        theme: theme.copyWith(
            defaultTextStyle:
                theme.defaultTextStyle.copyWith(height: 1.3, lineSpacing: 1)));

    final content = <pw.Widget>[
      if (logo != null)
        pw.Center(
          child: pw.Container(
            height: 40,
            margin: const pw.EdgeInsets.only(bottom: 4),
            child: pw.Image(pw.MemoryImage(logo), fit: pw.BoxFit.contain),
          ),
        ),
      pw.Center(
        child: await text(profile.name,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(
                fontSize: 14 * fontScale, fontWeight: pw.FontWeight.bold)),
      ),
      if (profile.address.isNotEmpty)
        pw.Center(
          child: await text(profile.address,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 8 * fontScale)),
        ),
      if (profile.taxId.isNotEmpty)
        pw.Center(
          child: await text('เลขประจำตัวผู้เสียภาษี\n${profile.taxId}',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(fontSize: 8 * fontScale)),
        ),
      for (final detail in [
        profile.branch,
        if (profile.phone.isNotEmpty) 'โทร. ${profile.phone}',
        profile.website
      ])
        if (detail.isNotEmpty)
          pw.Center(
              child: await text(detail,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(fontSize: 8 * fontScale))),
      pw.SizedBox(height: 8),
      pw.Center(
          child: await text(
              sale.isDebt ? 'ใบแจ้งยอดขายเชื่อ' : 'ใบเสร็จรับเงิน',
              style: pw.TextStyle(
                  fontSize: 11 * fontScale, fontWeight: pw.FontWeight.bold))),
      if (profile.vatEnabled)
        pw.Center(
          child: await text('ใบกำกับภาษีอย่างย่อ',
              style: pw.TextStyle(
                  fontSize: 11 * fontScale, fontWeight: pw.FontWeight.bold)),
        ),
      if (sale.isRefunded)
        pw.Center(
            child: await text('บิลนี้คืนเงินแล้ว',
                style: pw.TextStyle(
                    fontSize: 10 * fontScale, fontWeight: pw.FontWeight.bold))),
      pw.SizedBox(height: 8),
      await text('เลขที่เอกสาร: ${documentNumber(sale)}',
          style: pw.TextStyle(fontSize: 8 * fontScale)),
      await text('วันที่ขาย: ${saleDate(sale.createdAt)}',
          style: pw.TextStyle(fontSize: 8 * fontScale)),
      if (sale.staffName?.trim().isNotEmpty == true)
        await text('พนักงานขาย: ${sale.staffName}',
            style: pw.TextStyle(fontSize: 8 * fontScale)),
      if (sale.tableName != null)
        pw.Center(
          child: await text('โต๊ะ ${sale.tableName}',
              style: pw.TextStyle(fontSize: 9 * fontScale)),
        ),
      pw.Divider(),
      await row('รายการ / จำนวน × ราคาต่อหน่วย', 'รวมเงิน', fontSize: 7),
      pw.SizedBox(height: 4),
      for (final item in sale.items)
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            await text(item.productName,
                style: pw.TextStyle(
                    fontSize: 9 * fontScale, fontWeight: pw.FontWeight.bold)),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(
                  child: await text(
                      '${item.quantity} × ${_baht.format(item.quantity > 0 ? item.subtotal / item.quantity : item.price)}',
                      maxWidth: contentWidth * .60 - 4,
                      style: pw.TextStyle(fontSize: 8 * fontScale)),
                ),
                await text(_baht.format(item.subtotal),
                    maxWidth: contentWidth * .40,
                    style: pw.TextStyle(fontSize: 9 * fontScale)),
              ],
            ),
            if (item.modifiers.isNotEmpty)
              pw.Padding(
                padding: const pw.EdgeInsets.only(left: 8, top: 1),
                child: await text(
                  '• ${item.modifiers.map((m) => m.priceAdjust == 0 ? m.optionName : '${m.optionName} (${m.priceAdjust > 0 ? '+' : ''}${m.priceAdjust.toStringAsFixed(0)})').join(', ')}',
                  maxWidth: contentWidth - 8,
                  style: pw.TextStyle(fontSize: 8 * fontScale),
                ),
              ),
            if (item.notes != null && item.notes!.isNotEmpty)
              await text(item.notes!,
                  style: pw.TextStyle(fontSize: 8 * fontScale)),
            pw.SizedBox(height: 5),
          ],
        ),
      pw.Divider(),
      await text(
          'รายการ: ${sale.items.length}   จำนวนชิ้น: ${sale.items.fold<int>(0, (n, i) => n + i.quantity)}',
          style: pw.TextStyle(fontSize: 8 * fontScale)),
      pw.SizedBox(height: 4),
      await row('รวมค่าสินค้า', _baht.format(sale.itemsSubtotal)),
      if (sale.discount > 0)
        await row('ส่วนลด', '-${_baht.format(sale.discount)}'),
      if (sale.serviceCharge > 0)
        await row('ค่าบริการ', _baht.format(sale.serviceCharge)),
      await row('รวมทั้งสิ้น', _baht.format(sale.total), bold: true),
      if (profile.vatEnabled) ...[
        pw.Divider(),
        await row('มูลค่าก่อนภาษี', _baht.format(vat.netMinor / 100),
            fontSize: 9),
        await row('ภาษีมูลค่าเพิ่ม ${_baht.format(profile.vatRate)}%',
            _baht.format(vat.vatMinor / 100),
            fontSize: 9),
        await text('ราคานี้รวมภาษีมูลค่าเพิ่มแล้ว',
            style: pw.TextStyle(fontSize: 8 * fontScale)),
      ],
      pw.Divider(),
      if (sale.splitCount > 1)
        await row(
          'แยก ${sale.splitCount} คน',
          '${_baht.format(sale.total / sale.splitCount)} / คน',
        ),
      if (!sale.isDebt) ...[
        await row(sale.paymentMethod.label, _baht.format(sale.paid)),
        if (sale.paymentMethod == PaymentMethod.cash)
          await row('เงินทอน', _baht.format(sale.change)),
      ],
      if (sale.isDebt)
        pw.Center(
          child: await text('** เชื่อ: ${sale.customerName} **',
              style: pw.TextStyle(
                  fontSize: 10 * fontScale, fontWeight: pw.FontWeight.bold)),
        ),
      pw.SizedBox(height: 8),
      pw.Center(
          child: await text('ขอบคุณที่ใช้บริการ',
              style: pw.TextStyle(fontSize: 9 * fontScale))),
    ];
    if (pageFormat.height.isFinite) {
      pdf.addPage(pw.MultiPage(pageFormat: pageFormat, build: (_) => content));
    } else {
      pdf.addPage(pw.Page(
          pageFormat: pageFormat,
          build: (_) => pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: content)));
    }

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
}
