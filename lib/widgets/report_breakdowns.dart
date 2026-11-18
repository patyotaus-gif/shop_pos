import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/sale.dart';
import '../theme/report_palette.dart';
import '../utils/sales_breakdown.dart';

final _baht = NumberFormat('#,##0.00');
String _money(num minor) => '฿${_baht.format(minor / 100)}';

class ReportBreakdowns extends StatelessWidget {
  const ReportBreakdowns({
    super.key,
    required this.sales,
    this.advanced = false,
  });

  final List<Sale> sales;
  final bool advanced;

  @override
  Widget build(BuildContext context) {
    final data = SalesBreakdown(sales);
    final rankedStaff = data.cashiers.entries.toList()
      ..sort((a, b) {
        final byAmount = b.value.amountMinor.compareTo(a.value.amountMinor);
        return byAmount != 0 ? byAmount : (a.key ?? '').compareTo(b.key ?? '');
      });
    final payment = _Panel(
      title: 'ยอดขายตามวิธีชำระเงิน',
      children: [
        for (final method in PaymentMethod.values)
          if (data.payments[method] case final group?)
            _Distribution(
              label: method.label,
              group: group,
              total: data.paidAtSaleMinor,
              color: ReportPalette.series(context, method.index),
            ),
        if (data.payments.isEmpty)
          const Text('ไม่มีบิลที่รับชำระตอนขายในช่วงนี้'),
        if (data.payments[null] case final unknown?)
          _Distribution(
            label: 'ไม่ระบุวิธีชำระ',
            group: unknown,
            total: data.paidAtSaleMinor,
            color: Theme.of(context).colorScheme.outline,
          ),
        if (data.debt.count > 0) ...[
          const Divider(),
          _Value('ค้างชำระ', _money(data.debt.amountMinor)),
          Text(
              '${data.debt.count} บิล · ยอดตามบิลตอนขาย ดูยอดค้างปัจจุบันที่หน้าลูกค้าเครดิต',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ],
    );
    final channels = _Panel(
      title: 'ช่องทางที่ลูกค้าสั่งซื้อ',
      children: [
        for (final channel in SalesChannel.values)
          if (data.channels[channel] case final group?)
            _Distribution(
              label: channel.label,
              group: group,
              total: data.netSalesMinor,
              color: ReportPalette.series(context, channel.index + 2),
            ),
        if (data.channels.isEmpty) const Text('ไม่มีบิลขายสุทธิในช่วงนี้'),
      ],
    );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxWidth < 690) {
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [payment, channels]);
        }
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: payment),
          const SizedBox(width: 8),
          Expanded(child: channels),
        ]);
      }),
      ExpansionTile(
        title: const Text('กระทบยอดขาย'),
        subtitle: Text('ยอดสุทธิ ${_money(data.netSalesMinor)}'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          _Value('ยอดสินค้าก่อนส่วนลด', _money(data.beforeDiscountMinor)),
          _Value('หักส่วนลด', _money(-data.discountMinor)),
          _Value('ค่าบริการ', _money(data.serviceMinor)),
          if (data.adjustmentMinor != 0)
            _Value('ยอดปรับชำระ', _money(data.adjustmentMinor)),
          _Value('หักบิลคืนเงิน (${data.refunds.count} บิล)',
              _money(-data.refunds.amountMinor)),
          const Divider(),
          _Value('ยอดขายสุทธิ', _money(data.netSalesMinor)),
          const Text('รวมบิลตามวันที่ขาย และหักบิลที่คืนเงินเต็มจำนวน'),
        ],
      ),
      if (advanced) ...[
        ExpansionTile(
          title: const Text('ยอดขายตามโต๊ะ'),
          childrenPadding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            if (data.tables.isEmpty)
              const Text('ไม่มีบิลขายสุทธิที่ระบุโต๊ะในช่วงนี้')
            else ...[
              const Text('นับเฉพาะบิลที่ระบุโต๊ะ เมื่อแยกจ่ายจะนับแต่ละบิล'),
              for (final table in data.tables.keys.toList()..sort())
                _Value('$table · ${data.tables[table]!.count} บิล',
                    _money(data.tables[table]!.amountMinor)),
            ],
          ],
        ),
        ExpansionTile(
          title: const Text('ยอดขายตามผู้ปิดบิล'),
          childrenPadding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            if (rankedStaff.isEmpty) const Text('ไม่มีบิลขายสุทธิในช่วงนี้'),
            for (final row in rankedStaff)
              _Value(
                  '${row.key ?? "ไม่ระบุผู้ปิดบิล"} · ${row.value.count} บิล',
                  _money(row.value.amountMinor)),
          ],
        ),
        ExpansionTile(
          title: const Text('ยอดซื้อของสมาชิก'),
          childrenPadding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            _Value('สมาชิกที่ซื้อสินค้า', '${data.memberIds.length} คน'),
            _Value('บิลที่ระบุสมาชิก', '${data.members.count} บิล'),
            _Value('ยอดขายของสมาชิก', _money(data.members.amountMinor)),
            if (data.memberIds.isNotEmpty)
              _Value('ยอดเฉลี่ยต่อสมาชิก',
                  _money(data.members.amountMinor / data.memberIds.length)),
            _Value('ยอดขายจากบิลที่ไม่ระบุสมาชิก',
                _money(data.netSalesMinor - data.members.amountMinor)),
          ],
        ),
        ExpansionTile(
          title: const Text('การใช้โปรโมชัน'),
          childrenPadding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            _Value('บิลที่ขายชุดโปรโมชัน', '${data.setsSoldBills} บิล'),
            _Value('ส่วนลดจากชุดสินค้า', _money(data.bundleDiscountMinor)),
            _Value('บิลที่มีของแถม', '${data.giftBills} บิล'),
          ],
        ),
      ],
    ]);
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...children,
          ]),
        ),
      );
}

class _Distribution extends StatelessWidget {
  const _Distribution(
      {required this.label,
      required this.group,
      required this.total,
      required this.color});
  final String label;
  final BillGroup group;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final share = total > 0 ? (group.amountMinor / total).clamp(0.0, 1.0) : 0.0;
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: _Value(label, _money(group.amountMinor)),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(
            '${group.count} บิล${total > 0 ? ' · ${(100 * share).toStringAsFixed(1)}%' : ''}'),
        const SizedBox(height: 4),
        ExcludeSemantics(
            child: LinearProgressIndicator(
                value: share.toDouble(),
                color: color,
                backgroundColor:
                    Theme.of(context).colorScheme.surfaceContainerHighest)),
      ]),
    );
  }
}

class _Value extends StatelessWidget {
  const _Value(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 8,
            children: [
              Text(label),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w600))
            ]),
      );
}
