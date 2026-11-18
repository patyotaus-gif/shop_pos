import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/sale.dart';
import '../theme/report_palette.dart';
import '../utils/sales_report_csv.dart';

enum _TrendGroup { calendar, hour, weekday }

const _weekdays = ['จ.', 'อ.', 'พ.', 'พฤ.', 'ศ.', 'ส.', 'อา.'];
final _currency =
    NumberFormat.currency(locale: 'th_TH', symbol: '฿', decimalDigits: 2);

int _calendarDays(DateTimeRange range) {
  final first = range.start;
  final last = range.end;
  return DateTime.utc(last.year, last.month, last.day)
          .difference(DateTime.utc(first.year, first.month, first.day))
          .inDays +
      1;
}

DateTimeRange precedingSalesRange(DateTimeRange range) {
  final first = range.start;
  final days = _calendarDays(range);
  return DateTimeRange(
      start: DateTime(first.year, first.month, first.day - days),
      end: DateTime(first.year, first.month, first.day - 1));
}

class _Bucket {
  final String label, title;
  final List<Sale> bills = [];
  int satang = 0;
  _Bucket(this.label, this.title);
}

List<_Bucket> _buckets(
    List<Sale> sales, DateTimeRange range, _TrendGroup group) {
  final start = DateUtils.dateOnly(range.start),
      end = DateUtils.dateOnly(range.end);
  final multiMonth = _calendarDays(range) > 62;
  final buckets = <int, _Bucket>{};
  int calendarKey(DateTime day) => multiMonth
      ? day.year * 100 + day.month
      : day.year * 10000 + day.month * 100 + day.day;
  switch (group) {
    case _TrendGroup.calendar:
      for (var day = start;
          !day.isAfter(end);
          day = multiMonth
              ? DateTime(day.year, day.month + 1)
              : DateTime(day.year, day.month, day.day + 1)) {
        buckets[calendarKey(day)] = _Bucket(
            DateFormat(multiMonth ? 'MM/yy' : 'd/M').format(day),
            DateFormat(multiMonth ? 'MM/yyyy' : 'dd/MM/yyyy').format(day));
      }
    case _TrendGroup.hour:
      for (var h = 0; h < 24; h++) {
        final hour = h.toString().padLeft(2, '0');
        buckets[h] = _Bucket(hour, '$hour:00 – $hour:59');
      }
    case _TrendGroup.weekday:
      for (var d = 1; d <= 7; d++) {
        buckets[d] = _Bucket(
            _weekdays[d - 1],
            [
              'วันจันทร์',
              'วันอังคาร',
              'วันพุธ',
              'วันพฤหัสบดี',
              'วันศุกร์',
              'วันเสาร์',
              'วันอาทิตย์'
            ][d - 1]);
      }
  }
  for (final sale in sales) {
    final local = sale.createdAt.toLocal();
    final key = switch (group) {
      _TrendGroup.calendar => calendarKey(local),
      _TrendGroup.hour => local.hour,
      _TrendGroup.weekday => local.weekday,
    };
    final bucket = buckets[key];
    if (bucket == null) continue;
    bucket.bills.add(sale);
    if (!sale.isRefunded) bucket.satang += (sale.total * 100).round();
  }
  return buckets.values.toList();
}

class ReportSalesTrend extends StatefulWidget {
  final List<Sale> sales;
  final DateTimeRange range;
  final Stream<List<Sale>> Function(DateTimeRange) previousSales;
  final ValueChanged<Sale> onOpenBill;
  const ReportSalesTrend(
      {super.key,
      required this.sales,
      required this.range,
      required this.previousSales,
      required this.onOpenBill});
  @override
  State<ReportSalesTrend> createState() => _ReportSalesTrendState();
}

class _ReportSalesTrendState extends State<ReportSalesTrend> {
  late _TrendGroup _group =
      DateUtils.isSameDay(widget.range.start, widget.range.end)
          ? _TrendGroup.hour
          : _TrendGroup.calendar;
  int? _page;
  Stream<List<Sale>>? _previous;
  void _compare() => setState(() {
        _previous = widget.previousSales(precedingSalesRange(widget.range));
      });

  Future<void> _drill(_Bucket bucket) async {
    final selected = await showModalBottomSheet<Sale>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        builder: (ctx) => SafeArea(
                child: ConstrainedBox(
              constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(ctx).height * .75),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                ListTile(
                    title: Text(bucket.title),
                    subtitle: Text(
                        'ยอดขายสุทธิ ${_currency.format(bucket.satang / 100)}'),
                    trailing: IconButton(
                        tooltip: 'ปิด',
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close))),
                const Divider(height: 1),
                if (bucket.bills.isEmpty)
                  const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('ไม่มีบิลในช่วงนี้')),
                if (bucket.bills.isNotEmpty)
                  Flexible(
                      child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: bucket.bills.length,
                          itemBuilder: (_, i) {
                            final s = bucket.bills[i];
                            return ListTile(
                                title: Text(s.receiptNo ?? 'บิลขาย'),
                                subtitle: Text(
                                    "${DateFormat('dd/MM HH:mm').format(s.createdAt.toLocal())} · ${s.isRefunded ? 'คืนเงินแล้ว' : s.isDebt ? 'ค้างชำระ' : s.reportPaymentLabel}"),
                                trailing: Text(_currency.format(s.total)),
                                onTap: () => Navigator.pop(ctx, s));
                          })),
              ]),
            )));
    if (selected != null && mounted) widget.onOpenBill(selected);
  }

  @override
  Widget build(BuildContext context) {
    final groups = _buckets(widget.sales, widget.range, _group);
    final pages = (groups.length / 7).ceil();
    final firstActive = groups.indexWhere((b) => b.satang > 0);
    final page = (_page ??
            (_group == _TrendGroup.hour && firstActive >= 0
                ? firstActive ~/ 7
                : _group == _TrendGroup.calendar
                    ? pages - 1
                    : 0))
        .clamp(0, pages - 1);
    final visible = groups.skip(page * 7).take(7);
    final max = groups.fold<int>(1, (v, b) => math.max(v, b.satang));
    final current = sumReportMoney(
        widget.sales.where((s) => !s.isRefunded).map((s) => s.total));
    final period = precedingSalesRange(widget.range);
    final theme = Theme.of(context);
    final bar = ReportPalette.series(context, _group.index);
    return Card.outlined(
        margin: const EdgeInsets.symmetric(vertical: 8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('แนวโน้มยอดขายสุทธิ', style: theme.textTheme.titleMedium),
            Wrap(spacing: 6, children: [
              for (final group in _TrendGroup.values)
                ChoiceChip(
                    label: Text(switch (group) {
                      _TrendGroup.calendar => _calendarDays(widget.range) > 62
                          ? 'รายเดือน'
                          : 'รายวัน',
                      _TrendGroup.hour => 'ตามชั่วโมง',
                      _TrendGroup.weekday => 'ตามวันในสัปดาห์',
                    }),
                    selected: _group == group,
                    onSelected: (_) => setState(() {
                          _group = group;
                          _page = null;
                        })),
            ]),
            const SizedBox(height: 8),
            Text(
                'ยอดสูงสุด ${_currency.format(groups.fold<int>(0, (v, b) => math.max(v, b.satang)) / 100)}',
                style: theme.textTheme.bodySmall),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (final b in visible)
                Expanded(
                    child: Semantics(
                        button: true,
                        label:
                            '${b.title} ยอดสุทธิ ${_currency.format(b.satang / 100)} ดูบิล',
                        child: Tooltip(
                            message:
                                '${b.title} · ${_currency.format(b.satang / 100)}',
                            child: InkWell(
                                onTap: () => _drill(b),
                                child: Column(children: [
                                  SizedBox(
                                      height: 72,
                                      child: Align(
                                          alignment: Alignment.bottomCenter,
                                          child: FractionallySizedBox(
                                              widthFactor: .62,
                                              heightFactor: b.satang <= 0
                                                  ? 0
                                                  : b.satang / max,
                                              child: DecoratedBox(
                                                  decoration: BoxDecoration(
                                                      color: bar,
                                                      borderRadius:
                                                          const BorderRadius
                                                              .vertical(
                                                              top: Radius
                                                                  .circular(
                                                                      4))))))),
                                  const Divider(height: 1),
                                  Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 6),
                                      child: Text(b.label,
                                          textAlign: TextAlign.center,
                                          style: theme.textTheme.bodySmall)),
                                ]))))),
            ]),
            if (pages > 1)
              Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                IconButton(
                    tooltip: 'ช่วงก่อนหน้า',
                    onPressed: page == 0
                        ? null
                        : () => setState(() => _page = page - 1),
                    icon: const Icon(Icons.chevron_left)),
                Text('${page + 1}/$pages'),
                IconButton(
                    tooltip: 'ช่วงถัดไป',
                    onPressed: page >= pages - 1
                        ? null
                        : () => setState(() => _page = page + 1),
                    icon: const Icon(Icons.chevron_right)),
              ]),
            Text('แตะแท่งกราฟเพื่อดูบิล', style: theme.textTheme.bodySmall),
            const Divider(),
            if (_previous == null)
              Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                      onPressed: _compare,
                      icon: const Icon(Icons.compare_arrows),
                      label: const Text('เปรียบเทียบกับช่วงก่อนหน้า')))
            else
              StreamBuilder<List<Sale>>(
                  stream: _previous,
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return TextButton(
                          onPressed: _compare,
                          child: const Text(
                              'โหลดช่วงก่อนหน้าไม่สำเร็จ · ลองอีกครั้ง'));
                    }
                    if (!snapshot.hasData) {
                      return const LinearProgressIndicator();
                    }
                    final previous = sumReportMoney(snapshot.data!
                        .where((s) => !s.isRefunded)
                        .map((s) => s.total));
                    final delta = ((current - previous) * 100).round() / 100;
                    final direction = delta > 0
                        ? 'เพิ่มขึ้น'
                        : delta < 0
                            ? 'ลดลง'
                            : 'เท่าเดิม';
                    final percent = previous > 0
                        ? ' (${(delta.abs() * 100 / previous).toStringAsFixed(1)}%)'
                        : '';
                    return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              '${DateFormat('dd/MM/yy').format(period.start)} – ${DateFormat('dd/MM/yy').format(period.end)} · ${_currency.format(previous)}'),
                          Text(
                              delta == 0
                                  ? 'ยอดขายเท่าเดิม'
                                  : 'ยอดขาย$direction ${_currency.format(delta.abs())}$percent',
                              style: theme.textTheme.titleMedium),
                          if (DateUtils.isSameDay(
                              widget.range.end, DateTime.now()))
                            const Text('ยอดวันนี้นับถึงเวลาปัจจุบัน'),
                        ]);
                  }),
            if (_previous != null)
              Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                      onPressed: () => setState(() => _previous = null),
                      child: const Text('ปิดการเปรียบเทียบ'))),
          ]),
        ));
  }
}
