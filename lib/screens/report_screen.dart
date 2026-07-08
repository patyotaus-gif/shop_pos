import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'dart:convert';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import '../models/sale.dart';
import '../models/shop.dart';
import '../services/entitlements.dart';
import '../services/sale_service.dart';
import '../services/settings_service.dart';
import '../services/shop_service.dart';
import '../utils/receipt_generator.dart';
import '../widgets/upgrade_prompt.dart';

class ReportScreen extends StatefulWidget {
  const ReportScreen({super.key});
  @override
  State<ReportScreen> createState() => _ReportScreenState();
}

class _ReportScreenState extends State<ReportScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  DateTimeRange? _customRange;

  final _baht = NumberFormat('#,##0.00', 'th_TH');
  final _dateFmt = DateFormat('dd/MM/yyyy HH:mm', 'th_TH');
  final _dayFmt = DateFormat('dd/MM/yyyy', 'th_TH');

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 5, vsync: this);
    _tab.addListener(() {
      if (_tab.index == 4 && !_tab.indexIsChanging) _pickCustomRange();
    });
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  DateTimeRange _rangeFor(int idx) {
    final now = DateTime.now();
    final eod = DateTime(now.year, now.month, now.day, 23, 59, 59);
    return switch (idx) {
      0 => DateTimeRange(start: DateTime(now.year, now.month, now.day), end: eod),
      1 => DateTimeRange(start: DateTime(now.year, now.month, 1), end: eod),
      2 => () {
          final first = DateTime(now.year, now.month - 1, 1);
          final last = DateTime(now.year, now.month, 0, 23, 59, 59);
          return DateTimeRange(start: first, end: last);
        }(),
      3 => DateTimeRange(start: DateTime(now.year, 1, 1), end: eod),
      _ => _customRange ?? DateTimeRange(start: DateTime(now.year, now.month, now.day), end: eod),
    };
  }

  String _titleFor(int idx) => switch (idx) {
        0 => 'วันนี้',
        1 => 'เดือนนี้',
        2 => 'เดือนที่แล้ว',
        3 => 'ปีนี้',
        _ => _customRange != null
            ? '${_dayFmt.format(_customRange!.start)} – ${_dayFmt.format(_customRange!.end)}'
            : 'กำหนดเอง',
      };

  Future<void> _pickCustomRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: _customRange,
      locale: const Locale('th'),
    );
    if (picked != null && mounted) {
      setState(() => _customRange = DateTimeRange(
            start: picked.start,
            end: DateTime(picked.end.year, picked.end.month, picked.end.day, 23, 59, 59),
          ));
    }
  }

  // ─── Professional PDF ───────────────────────────────────────────
  Future<void> _exportPdf(int tabIdx) async {
    final range = _rangeFor(tabIdx);
    final title = _titleFor(tabIdx);
    final info = await SettingsService.getShopInfo();
    final allSales = await SaleService.watchByRange(range.start, range.end).first;
    final active = allSales.where((s) => !s.isRefunded).toList();
    final refunded = allSales.where((s) => s.isRefunded).toList();

    // ── Calculations ──
    final grossRevenue = allSales.fold<double>(0, (a, s) => a + s.total);
    final refundTotal = refunded.fold<double>(0, (a, s) => a + s.total);
    final netRevenue = grossRevenue - refundTotal;
    final cogs = active.fold<double>(
        0, (a, s) => a + s.items.fold(0, (b, i) => b + i.costPrice * i.quantity));
    final grossProfit = netRevenue - cogs;
    final margin = netRevenue > 0 ? grossProfit / netRevenue * 100 : 0.0;
    final avgPerBill = active.isNotEmpty ? netRevenue / active.length : 0.0;

    final byMethod = <String, double>{};
    for (final s in active) {
      final key = s.isDebt ? 'เชื่อ' : s.paymentMethod.label;
      byMethod[key] = (byMethod[key] ?? 0) + s.total;
    }

    final productMap = <String, _ProductStat>{};
    for (final s in active) {
      for (final item in s.items) {
        final stat = productMap.putIfAbsent(item.productName, () => _ProductStat(item.productName));
        stat.qty += item.quantity;
        stat.revenue += item.subtotal;
        stat.profit += item.profit;
      }
    }
    final top10 = productMap.values.toList()..sort((a, b) => b.revenue.compareTo(a.revenue));
    if (top10.length > 10) top10.length = 10;

    final b = NumberFormat('#,##0.00');
    final now = DateTime.now();

    // ── Thai font ──
    final fontRegular = await PdfGoogleFonts.notoSansThaiRegular();
    final fontBold = await PdfGoogleFonts.notoSansThaiSemiBold();

    // ── Colors ──
    const ruby = PdfColor.fromInt(0xFF7A1F2B);
    const rubyLight = PdfColor.fromInt(0xFFF0E2E4);
    const slate = PdfColor.fromInt(0xFF1F1A1B);
    const teal = PdfColor.fromInt(0xFF0F766E);
    const tealLight = PdfColor.fromInt(0xFFF0FDFA);

    // ── Style helpers ──
    pw.TextStyle ts(double size, {bool bold = false, PdfColor? color}) => pw.TextStyle(
          font: bold ? fontBold : fontRegular,
          fontSize: size,
          color: color,
        );

    // Section header with left red border
    pw.Widget sectionHeader(String text) => pw.Container(
          margin: const pw.EdgeInsets.only(top: 14, bottom: 6),
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: const pw.BoxDecoration(
            border: pw.Border(left: pw.BorderSide(color: ruby, width: 3)),
            color: PdfColor.fromInt(0xFFF8FAFC),
          ),
          child: pw.Text(text, style: ts(9, bold: true, color: slate)),
        );

    // P&L row: label left, value right
    pw.Widget plRow(String label, String value,
        {bool bold = false, PdfColor? color, bool indent = false}) =>
        pw.Padding(
          padding: pw.EdgeInsets.symmetric(vertical: 2, horizontal: indent ? 12 : 0),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(label, style: ts(8.5, bold: bold, color: color ?? slate)),
              pw.Text(value, style: ts(8.5, bold: bold, color: color ?? slate)),
            ],
          ),
        );

    // Thin divider
    pw.Widget thinLine() => pw.Container(
          margin: const pw.EdgeInsets.symmetric(vertical: 3),
          height: 0.5,
          color: PdfColors.grey300,
        );

    // Thick double-line divider for totals
    pw.Widget totalLine() => pw.Column(children: [
          pw.Container(height: 0.5, color: PdfColors.grey600, margin: const pw.EdgeInsets.only(top: 3)),
          pw.Container(height: 2, color: PdfColors.grey600, margin: const pw.EdgeInsets.only(top: 1, bottom: 3)),
        ]);

    // Metric box
    pw.Widget metricBox(String label, String value, {PdfColor? bg, PdfColor? fg}) =>
        pw.Expanded(
          child: pw.Container(
            margin: const pw.EdgeInsets.symmetric(horizontal: 3),
            padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            decoration: pw.BoxDecoration(
              color: bg ?? PdfColors.grey50,
              borderRadius: pw.BorderRadius.circular(4),
              border: pw.Border.all(color: PdfColors.grey200),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(label, style: ts(7, color: PdfColors.grey600)),
                pw.SizedBox(height: 3),
                pw.Text(value, style: ts(10, bold: true, color: fg ?? slate)),
              ],
            ),
          ),
        );

    // Table header cell
    pw.Widget th(String text, {pw.CrossAxisAlignment align = pw.CrossAxisAlignment.start}) =>
        pw.Container(
          padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
          color: slate,
          child: pw.Text(text, style: ts(7.5, bold: true, color: PdfColors.white)),
        );

    // Table data cell
    pw.Widget td(String text,
        {bool bold = false,
        PdfColor? color,
        pw.TextAlign align = pw.TextAlign.left}) =>
        pw.Padding(
          padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 3.5),
          child: pw.Text(text,
              textAlign: align,
              style: ts(7.5, bold: bold, color: color ?? PdfColors.black)),
        );

    final pdf = pw.Document();

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.symmetric(horizontal: 36, vertical: 32),
        header: (ctx) => pw.Column(children: [
          // ── Top banner ──
          pw.Container(
            width: double.infinity,
            padding: const pw.EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const pw.BoxDecoration(color: ruby),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
                  pw.Text(info['name'] ?? 'ร้านของชำ',
                      style: ts(15, bold: true, color: PdfColors.white)),
                  if ((info['taxId'] ?? '').isNotEmpty)
                    pw.Text('เลขผู้เสียภาษี: ${info['taxId']}',
                        style: ts(8, color: PdfColor.fromInt(0xFFFFCDD2))),
                  if ((info['address'] ?? '').isNotEmpty)
                    pw.Text(info['address']!,
                        style: ts(8, color: PdfColor.fromInt(0xFFFFCDD2))),
                ]),
                pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
                  pw.Text('รายงานการขาย',
                      style: ts(11, bold: true, color: PdfColors.white)),
                  pw.Text(title,
                      style: ts(9, color: PdfColor.fromInt(0xFFFFCDD2))),
                  pw.Text(
                      '${_dayFmt.format(range.start)} – ${_dayFmt.format(range.end)}',
                      style: ts(8, color: PdfColor.fromInt(0xFFFFCDD2))),
                  pw.Text('พิมพ์: ${DateFormat('dd/MM/yyyy HH:mm').format(now)}',
                      style: ts(7, color: PdfColor.fromInt(0xFFFFCDD2))),
                ]),
              ],
            ),
          ),
          if (ctx.pageNumber > 1) pw.SizedBox(height: 8),
        ]),
        footer: (ctx) => pw.Container(
          padding: const pw.EdgeInsets.only(top: 6),
          decoration: const pw.BoxDecoration(
              border: pw.Border(top: pw.BorderSide(color: PdfColors.grey300))),
          child: pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('จัดทำโดย Pokpok POS',
                  style: ts(7, color: PdfColors.grey500)),
              pw.Text('หน้า ${ctx.pageNumber}/${ctx.pagesCount}',
                  style: ts(7, color: PdfColors.grey500)),
            ],
          ),
        ),
        build: (ctx) => [
          pw.SizedBox(height: 14),

          // ── Metric boxes ──
          pw.Row(children: [
            metricBox('รายได้สุทธิ', '฿${b.format(netRevenue)}',
                bg: const PdfColor.fromInt(0xFFF0FDF4),
                fg: const PdfColor.fromInt(0xFF15803D)),
            metricBox('ต้นทุนสินค้าขาย', '฿${b.format(cogs)}',
                bg: const PdfColor.fromInt(0xFFFFF7ED),
                fg: const PdfColor.fromInt(0xFFC2410C)),
            metricBox(
                'กำไรขั้นต้น  ${margin.toStringAsFixed(1)}%',
                '฿${b.format(grossProfit)}',
                bg: tealLight,
                fg: teal),
            metricBox('จำนวนบิล', '${active.length} บิล',
                bg: const PdfColor.fromInt(0xFFF8FAFC), fg: slate),
          ]),
          pw.SizedBox(height: 4),
          pw.Row(children: [
            metricBox('ค่าเฉลี่ย/บิล', '฿${b.format(avgPerBill)}'),
            metricBox('คืนเงิน', '${refunded.length} บิล  (฿${b.format(refundTotal)})',
                fg: const PdfColor.fromInt(0xFFDC2626)),
            metricBox('รายได้ก่อนหักคืน', '฿${b.format(grossRevenue)}'),
            pw.Expanded(child: pw.SizedBox()),
          ]),

          // ── 1. P&L Statement ──
          sectionHeader('1. งบกำไรขาดทุนเบื้องต้น  (Profit & Loss Statement)'),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.grey200),
              borderRadius: pw.BorderRadius.circular(4),
            ),
            child: pw.Column(children: [
              plRow('รายได้จากการขายทั้งหมด  (Gross Revenue)', '฿${b.format(grossRevenue)}'),
              if (refunded.isNotEmpty)
                plRow('  (-) คืนเงิน  (Refunds)  ${refunded.length} บิล',
                    '(฿${b.format(refundTotal)})',
                    indent: true, color: const PdfColor.fromInt(0xFFDC2626)),
              thinLine(),
              plRow('รายได้สุทธิ  (Net Revenue)', '฿${b.format(netRevenue)}',
                  bold: true),
              plRow('  (-) ต้นทุนสินค้าขาย  (COGS)', '(฿${b.format(cogs)})',
                  indent: true, color: PdfColors.grey700),
              totalLine(),
              plRow('กำไรขั้นต้น  (Gross Profit)', '฿${b.format(grossProfit)}',
                  bold: true,
                  color: grossProfit >= 0
                      ? const PdfColor.fromInt(0xFF0F766E)
                      : const PdfColor.fromInt(0xFFDC2626)),
              plRow('อัตรากำไรขั้นต้น  (Gross Margin)', '${margin.toStringAsFixed(2)}%',
                  bold: true,
                  color: grossProfit >= 0
                      ? const PdfColor.fromInt(0xFF0F766E)
                      : const PdfColor.fromInt(0xFFDC2626)),
              thinLine(),
              plRow('จำนวนบิลทั้งหมด',
                  '${allSales.length} บิล  (ปกติ ${active.length}, คืนเงิน ${refunded.length})'),
              plRow('มูลค่าเฉลี่ยต่อบิล  (Avg. Ticket Size)', '฿${b.format(avgPerBill)}'),
            ]),
          ),

          // ── 2. Payment Breakdown ──
          sectionHeader('2. รายรับแยกตามช่องทางชำระเงิน'),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey200),
            columnWidths: {
              0: const pw.FlexColumnWidth(2),
              1: const pw.FlexColumnWidth(2),
              2: const pw.FlexColumnWidth(1),
              3: const pw.FlexColumnWidth(3),
            },
            children: [
              pw.TableRow(children: [
                th('ช่องทาง'), th('ยอดรวม'), th('สัดส่วน'), th(''),
              ]),
              ...byMethod.entries.map((e) {
                final pct = netRevenue > 0 ? e.value / netRevenue : 0.0;
                final barW = (pct * 120).clamp(0, 120).toDouble();
                return pw.TableRow(children: [
                  td(e.key),
                  td('฿${b.format(e.value)}', bold: true),
                  td('${(pct * 100).toStringAsFixed(1)}%'),
                  pw.Padding(
                    padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 5),
                    child: pw.Stack(children: [
                      pw.Container(height: 8, color: PdfColors.grey100),
                      pw.Container(width: barW, height: 8, color: ruby),
                    ]),
                  ),
                ]);
              }),
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF1F5F9)),
                children: [
                  th('รวม'), th('฿${b.format(netRevenue)}'), th('100%'), pw.SizedBox(),
                ],
              ),
            ],
          ),

          // ── 3. Top 10 Products ──
          sectionHeader('3. สินค้าขายดี 10 อันดับ  (ตามรายได้)'),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey200),
            columnWidths: {
              0: const pw.FixedColumnWidth(22),
              1: const pw.FlexColumnWidth(4),
              2: const pw.FlexColumnWidth(1.2),
              3: const pw.FlexColumnWidth(2),
              4: const pw.FlexColumnWidth(2),
              5: const pw.FlexColumnWidth(1.5),
            },
            children: [
              pw.TableRow(children: [
                th('#'), th('สินค้า'), th('จำนวน'), th('รายได้'), th('กำไร'), th('Margin'),
              ]),
              ...top10.asMap().entries.map((e) {
                final m = e.value.revenue > 0
                    ? e.value.profit / e.value.revenue * 100 : 0.0;
                final rowBg = e.key.isEven ? PdfColors.white : const PdfColor.fromInt(0xFFF8FAFC);
                return pw.TableRow(
                  decoration: pw.BoxDecoration(color: rowBg),
                  children: [
                    td('${e.key + 1}', bold: true, color: ruby),
                    td(e.value.name),
                    td('${e.value.qty}', align: pw.TextAlign.right),
                    td('฿${b.format(e.value.revenue)}', align: pw.TextAlign.right),
                    td('฿${b.format(e.value.profit)}', align: pw.TextAlign.right,
                        color: const PdfColor.fromInt(0xFF0F766E)),
                    td('${m.toStringAsFixed(1)}%', align: pw.TextAlign.right),
                  ],
                );
              }),
            ],
          ),

          // ── 4. Transaction List ──
          sectionHeader('4. รายการขายทั้งหมด  (${allSales.length} บิล)'),
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey200),
            columnWidths: {
              0: const pw.FixedColumnWidth(28),
              1: const pw.FixedColumnWidth(72),
              2: const pw.FlexColumnWidth(1.8),
              3: const pw.FlexColumnWidth(1.2),
              4: const pw.FlexColumnWidth(1.5),
              5: const pw.FlexColumnWidth(1.5),
              6: const pw.FlexColumnWidth(1.5),
            },
            children: [
              pw.TableRow(children: [
                th('#'),
                th('วันที่'),
                th('ลูกค้า / หมายเหตุ'),
                th('ช่องทาง'),
                th('รายได้'),
                th('ต้นทุน'),
                th('กำไร'),
              ]),
              ...allSales.asMap().entries.map((entry) {
                final idx = entry.key;
                final s = entry.value;
                final cost = s.items.fold<double>(0, (a, i) => a + i.costPrice * i.quantity);
                final profit = s.isRefunded ? 0.0 : s.total - cost;
                final isRef = s.isRefunded;
                final rowBg = isRef
                    ? rubyLight
                    : idx.isEven ? PdfColors.white : const PdfColor.fromInt(0xFFF8FAFC);
                final textColor = isRef ? ruby : PdfColors.black;
                return pw.TableRow(
                  decoration: pw.BoxDecoration(color: rowBg),
                  children: [
                    td('${idx + 1}', color: PdfColors.grey500),
                    td(DateFormat('dd/MM/yy HH:mm').format(s.createdAt), color: textColor),
                    td(isRef
                        ? 'คืนเงิน${s.refundReason?.isNotEmpty == true ? ": ${s.refundReason}" : ""}'
                        : (s.customerName ?? '-'),
                        color: textColor),
                    td(isRef ? '-' : (s.isDebt ? 'เชื่อ' : s.paymentMethod.label),
                        color: textColor),
                    td(isRef ? '(฿${b.format(s.total)})' : '฿${b.format(s.total)}',
                        align: pw.TextAlign.right, color: textColor),
                    td(isRef ? '-' : '฿${b.format(cost)}',
                        align: pw.TextAlign.right, color: textColor),
                    td(isRef ? '-' : '฿${b.format(profit)}',
                        align: pw.TextAlign.right,
                        color: isRef ? ruby : const PdfColor.fromInt(0xFF0F766E)),
                  ],
                );
              }),
            ],
          ),
          pw.SizedBox(height: 8),
        ],
      ),
    );

    await Printing.sharePdf(
        bytes: await pdf.save(), filename: 'report_${title.replaceAll('/', '-')}.pdf');
  }

  // ─── Professional CSV ────────────────────────────────────────────
  Future<void> _exportCsv(int tabIdx) async {
    final range = _rangeFor(tabIdx);
    final title = _titleFor(tabIdx);
    final info = await SettingsService.getShopInfo();
    final allSales = await SaleService.watchByRange(range.start, range.end).first;
    final active = allSales.where((s) => !s.isRefunded).toList();
    final refunded = allSales.where((s) => s.isRefunded).toList();

    final grossRevenue = allSales.fold<double>(0, (a, s) => a + s.total);
    final refundTotal = refunded.fold<double>(0, (a, s) => a + s.total);
    final netRevenue = grossRevenue - refundTotal;
    final cogs = active.fold<double>(
        0, (a, s) => a + s.items.fold(0, (b, i) => b + i.costPrice * i.quantity));
    final grossProfit = netRevenue - cogs;
    final margin = netRevenue > 0 ? grossProfit / netRevenue * 100 : 0.0;

    final buf = StringBuffer();

    // Summary header
    buf.writeln('รายงานการขาย,${info['name']}');
    if ((info['taxId'] ?? '').isNotEmpty) {
      buf.writeln('เลขประจำตัวผู้เสียภาษี,${info['taxId']}');
    }
    buf.writeln('ช่วงเวลา,$title');
    buf.writeln('ตั้งแต่,${_dayFmt.format(range.start)}');
    buf.writeln('ถึง,${_dayFmt.format(range.end)}');
    buf.writeln('พิมพ์เมื่อ,${_dateFmt.format(DateTime.now())}');
    buf.writeln();

    buf.writeln('=== สรุปทางการเงิน ===');
    buf.writeln('รายได้จากการขายทั้งหมด,${grossRevenue.toStringAsFixed(2)}');
    buf.writeln('คืนเงิน,${refundTotal.toStringAsFixed(2)}');
    buf.writeln('รายได้สุทธิ,${netRevenue.toStringAsFixed(2)}');
    buf.writeln('ต้นทุนสินค้าขาย (COGS),${cogs.toStringAsFixed(2)}');
    buf.writeln('กำไรขั้นต้น,${grossProfit.toStringAsFixed(2)}');
    buf.writeln('อัตรากำไรขั้นต้น,${margin.toStringAsFixed(2)}%');
    buf.writeln('จำนวนบิลทั้งหมด,${allSales.length}');
    buf.writeln('บิลปกติ,${active.length}');
    buf.writeln('บิลคืนเงิน,${refunded.length}');
    buf.writeln();

    buf.writeln('=== รายการขายทั้งหมด ===');
    buf.writeln('ลำดับ,วันที่,ลูกค้า,ช่องทาง,รายได้,ต้นทุน,กำไร,ส่วนลด,สถานะ,เหตุผลคืนเงิน');

    var i = 1;
    for (final s in allSales) {
      final cost = s.items.fold<double>(0, (a, item) => a + item.costPrice * item.quantity);
      final profit = s.isRefunded ? 0.0 : s.total - cost;
      final method = s.isDebt ? 'เชื่อ' : s.paymentMethod.label;
      final status = s.isRefunded ? 'คืนเงิน' : 'ปกติ';
      buf.writeln(
        '$i,'
        '${DateFormat('dd/MM/yyyy HH:mm').format(s.createdAt)},'
        '"${s.customerName ?? ''}",'
        '$method,'
        '${s.total.toStringAsFixed(2)},'
        '${cost.toStringAsFixed(2)},'
        '${profit.toStringAsFixed(2)},'
        '${s.discount.toStringAsFixed(2)},'
        '$status,'
        '"${s.refundReason ?? ''}"',
      );
      i++;
    }

    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/report_${title.replaceAll('/', '-')}.csv');
    await file.writeAsBytes([0xEF, 0xBB, 0xBF, ...utf8.encode(buf.toString())]);
    await Share.shareXFiles([XFile(file.path)], subject: 'รายงาน $title');
  }

  @override
  Widget build(BuildContext context) {
    // Advanced reports (P&L margin breakdown + PDF/CSV export) are a
    // Full/Restaurant feature. Solo/Lite still get the basic on-screen
    // report (summary cards + transaction list); tapping export nudges
    // them to upgrade instead.
    return StreamBuilder<Shop?>(
      stream: ShopService.watchCurrentShop(),
      builder: (context, snap) {
        final tier = snap.data?.tier ?? ShopTier.full;
        final advanced = Entitlements.canUseAdvancedReports(tier);

        void exportOr(VoidCallback doExport) {
          if (advanced) {
            doExport();
          } else {
            showUpgradePrompt(context,
                feature: EntitlementFeature.advancedReports);
          }
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('รายงาน'),
            centerTitle: true,
            actions: [
              IconButton(
                icon: Icon(advanced
                    ? Icons.table_chart_outlined
                    : Icons.lock_outline),
                tooltip: 'Export CSV',
                onPressed: () => exportOr(() => _exportCsv(_tab.index)),
              ),
              IconButton(
                icon: Icon(advanced
                    ? Icons.picture_as_pdf_outlined
                    : Icons.lock_outline),
                tooltip: 'Export PDF',
                onPressed: () => exportOr(() => _exportPdf(_tab.index)),
              ),
            ],
            bottom: TabBar(
              controller: _tab,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: const [
                Tab(text: 'วันนี้'),
                Tab(text: 'เดือนนี้'),
                Tab(text: 'เดือนที่แล้ว'),
                Tab(text: 'ปีนี้'),
                Tab(text: 'กำหนดเอง'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tab,
            children: List.generate(
              5,
              (i) => _SalesReport(
                rangeBuilder: () => _rangeFor(i),
                baht: _baht,
                dateFormat: _dateFmt,
                advanced: advanced,
              ),
            ),
          ),
        );
      },
    );
  }
}

// ── Product stat helper ──────────────────────────────────────────
class _ProductStat {
  final String name;
  int qty = 0;
  double revenue = 0;
  double profit = 0;
  _ProductStat(this.name);
}

// ── Sales Report Widget ──────────────────────────────────────────
class _SalesReport extends StatelessWidget {
  final DateTimeRange Function() rangeBuilder;
  final NumberFormat baht;
  final DateFormat dateFormat;

  /// Full/Restaurant only — shows the profit & margin P&L bar. Basic
  /// tiers see revenue + bill count + the transaction list without the
  /// cost/profit breakdown.
  final bool advanced;

  const _SalesReport({
    required this.rangeBuilder,
    required this.baht,
    required this.dateFormat,
    required this.advanced,
  });

  @override
  Widget build(BuildContext context) {
    final range = rangeBuilder();
    final cs = Theme.of(context).colorScheme;

    return StreamBuilder<List<Sale>>(
      stream: SaleService.watchByRange(range.start, range.end),
      builder: (ctx, snap) {
        if (snap.hasError) return const Center(child: Text('โหลดข้อมูลไม่สำเร็จ'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());

        final sales = snap.data!;
        final active = sales.where((s) => !s.isRefunded).toList();
        final refunded = sales.where((s) => s.isRefunded).toList();

        final grossRevenue = sales.fold<double>(0, (a, s) => a + s.total);
        final refundTotal = refunded.fold<double>(0, (a, s) => a + s.total);
        final netRevenue = grossRevenue - refundTotal;
        final cogs = active.fold<double>(
            0, (a, s) => a + s.items.fold(0, (b, i) => b + i.costPrice * i.quantity));
        final grossProfit = netRevenue - cogs;
        final margin = netRevenue > 0 ? grossProfit / netRevenue * 100 : 0.0;
        final debtTotal = active.where((s) => s.isDebt).fold<double>(0, (a, s) => a + s.total);

        return Column(
          children: [
            // ── Summary cards ──
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Column(
                children: [
                  Row(children: [
                    _Card(label: 'รายได้สุทธิ', value: '฿${baht.format(netRevenue)}',
                        icon: Icons.attach_money, color: Colors.green),
                    const SizedBox(width: 8),
                    _Card(label: 'จำนวนบิล', value: '${active.length} บิล',
                        icon: Icons.receipt_long, color: cs.primary),
                    const SizedBox(width: 8),
                    _Card(label: 'ยอดเชื่อ', value: '฿${baht.format(debtTotal)}',
                        icon: Icons.person_outline, color: Colors.orange),
                  ]),
                  const SizedBox(height: 8),
                  // P&L bar — advanced (Full/Restaurant). Basic tiers see
                  // a locked teaser that opens the upgrade prompt.
                  if (advanced)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.teal.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.teal.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          _PLItem(label: 'รายได้สุทธิ', value: '฿${baht.format(netRevenue)}', color: Colors.green),
                          const Text('−', style: TextStyle(color: Colors.grey)),
                          _PLItem(label: 'ต้นทุน', value: '฿${baht.format(cogs)}', color: Colors.redAccent),
                          const Text('=', style: TextStyle(color: Colors.grey)),
                          _PLItem(
                            label: 'กำไรขั้นต้น ${margin.toStringAsFixed(1)}%',
                            value: '฿${baht.format(grossProfit)}',
                            color: grossProfit >= 0 ? Colors.teal : Colors.red,
                            bold: true,
                          ),
                        ],
                      ),
                    )
                  else
                    InkWell(
                      onTap: () => showUpgradePrompt(context,
                          feature: EntitlementFeature.advancedReports),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 12),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: cs.outlineVariant),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.lock_outline,
                                size: 18,
                                color: cs.onSurface.withValues(alpha: 0.5)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'กำไร–ต้นทุน + ส่งออก PDF/CSV — อยู่ในแผน Full ขึ้นไป',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: cs.onSurface
                                        .withValues(alpha: 0.7)),
                              ),
                            ),
                            Text('อัพเกรด',
                                style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: cs.primary)),
                          ],
                        ),
                      ),
                    ),
                  if (refunded.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.red.withValues(alpha: 0.2)),
                        ),
                        child: Text(
                          'คืนเงิน ${refunded.length} บิล รวม ฿${baht.format(refundTotal)}',
                          style: const TextStyle(fontSize: 12, color: Colors.red),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            // ── Transaction list ──
            Expanded(
              child: sales.isEmpty
                  ? const Center(child: Text('ยังไม่มีรายการขาย'))
                  : ListView.builder(
                      itemCount: sales.length,
                      itemBuilder: (ctx, i) {
                        final s = sales[i];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: s.isRefunded
                                ? Colors.red.shade100
                                : s.isDebt
                                    ? Colors.orange.shade100
                                    : Colors.green.shade100,
                            child: Icon(
                              s.isRefunded ? Icons.undo : s.isDebt ? Icons.person_outline : Icons.check,
                              color: s.isRefunded ? Colors.red : s.isDebt ? Colors.orange : Colors.green,
                            ),
                          ),
                          title: Row(children: [
                            Expanded(
                              child: Text(
                                s.isDebt ? 'เชื่อ: ${s.customerName}' : s.paymentMethod.label,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  decoration: s.isRefunded ? TextDecoration.lineThrough : null,
                                  color: s.isRefunded ? Colors.grey : null,
                                ),
                              ),
                            ),
                            if (s.isRefunded)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade100,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Text('คืนเงินแล้ว',
                                    style: TextStyle(fontSize: 10, color: Colors.red)),
                              ),
                          ]),
                          subtitle: Text('${s.items.length} รายการ · ${dateFormat.format(s.createdAt)}'),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('฿${baht.format(s.total)}',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: s.isRefunded ? Colors.grey : null,
                                      decoration: s.isRefunded ? TextDecoration.lineThrough : null)),
                              if (s.discount > 0)
                                Text('ลด ฿${baht.format(s.discount)}',
                                    style: const TextStyle(fontSize: 11, color: Colors.green)),
                            ],
                          ),
                          onTap: () => _showDetail(ctx, s),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  void _showDetail(BuildContext context, Sale sale) {
    final bahtFmt = NumberFormat('#,##0.00', 'th_TH');
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('รายละเอียดบิล',
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ...sale.items.map((item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(child: Text('${item.productName} × ${item.quantity}')),
                      Text('฿${bahtFmt.format(item.subtotal)}'),
                    ],
                  ),
                )),
            const Divider(),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('รวม', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('฿${bahtFmt.format(sale.total)}', style: const TextStyle(fontWeight: FontWeight.bold)),
            ]),
            if (sale.staffName != null) ...[
              const SizedBox(height: 4),
              Row(children: [
                Icon(Icons.person_outline,
                    size: 14,
                    color: Theme.of(ctx)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.6)),
                const SizedBox(width: 4),
                Text('ขายโดย ${sale.staffName}',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(ctx)
                            .colorScheme
                            .onSurface
                            .withValues(alpha: 0.6))),
              ]),
            ],
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final shopName = await SettingsService.getShopName();
                    await ReceiptGenerator.printReceipt(sale, shopName: shopName);
                  },
                  icon: const Icon(Icons.receipt_long_outlined),
                  label: const Text('ใบเสร็จ'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: _RefundButton(sale: sale, baht: bahtFmt)),
            ]),
          ],
        ),
      ),
    );
  }
}

// ── Refund Button ────────────────────────────────────────────────
class _RefundButton extends StatelessWidget {
  final Sale sale;
  final NumberFormat baht;
  const _RefundButton({required this.sale, required this.baht});

  @override
  Widget build(BuildContext context) {
    if (sale.isRefunded) {
      return Text(
        'คืนเงินแล้ว${sale.refundReason?.isNotEmpty == true ? " · ${sale.refundReason}" : ""}',
        style: const TextStyle(color: Colors.grey, fontSize: 12),
      );
    }
    return OutlinedButton.icon(
      onPressed: () async {
        Navigator.pop(context);
        final reasonCtrl = TextEditingController();
        final confirm = await showDialog<bool>(
          context: context,
          builder: (c) => AlertDialog(
            title: const Text('คืนเงินลูกค้า'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('ยอด ฿${baht.format(sale.total)}'),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonCtrl,
                  decoration: const InputDecoration(
                    labelText: 'เหตุผล (ไม่บังคับ)',
                    hintText: 'เช่น สินค้าชำรุด',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (sale.paymentMethod == PaymentMethod.online)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text('เงินจะถูกคืนผ่าน Stripe อัตโนมัติ',
                        style: TextStyle(fontSize: 12, color: Colors.grey)),
                  ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('ยกเลิก')),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                child: const Text('คืนเงิน'),
              ),
            ],
          ),
        );
        if (confirm == true) {
          await SaleService.refundSale(sale, reason: reasonCtrl.text.trim());
        }
        reasonCtrl.dispose();
      },
      icon: const Icon(Icons.undo, color: Colors.red),
      label: const Text('คืนเงิน', style: TextStyle(color: Colors.red)),
    );
  }
}

// ── Small widgets ────────────────────────────────────────────────
class _Card extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;
  const _Card({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) => Expanded(
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Column(children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 4),
            Text(value,
                style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 13),
                textAlign: TextAlign.center),
            Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey), textAlign: TextAlign.center),
          ]),
        ),
      );
}

class _PLItem extends StatelessWidget {
  final String label, value;
  final Color color;
  final bool bold;
  const _PLItem({required this.label, required this.value, required this.color, this.bold = false});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(value,
              style: TextStyle(
                  fontWeight: bold ? FontWeight.bold : FontWeight.w600,
                  color: color,
                  fontSize: bold ? 14 : 12)),
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
        ],
      );
}
