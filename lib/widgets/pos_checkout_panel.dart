import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Presentation only; checkout and permission checks remain in the POS flow.
class PosCheckoutPanel extends StatelessWidget {
  const PosCheckoutPanel(
      {super.key,
      required this.subtotal,
      required this.discount,
      required this.total,
      required this.onDiscount,
      required this.onCheckout,
      required this.onDebt,
      required this.hasItems,
      required this.canDiscount,
      required this.canDebt,
      this.compact = false,
      this.horizontalTotal = false});

  final double subtotal, discount, total;
  final VoidCallback onDiscount, onCheckout, onDebt;
  final bool hasItems, canDiscount, canDebt, compact;
  final bool horizontalTotal;

  @override
  Widget build(BuildContext context) {
    final baht = NumberFormat('#,##0.00', 'th_TH');
    final cs = Theme.of(context).colorScheme;
    final totalTexts = <Widget>[
      Text('ยอดสุทธิ',
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      Text('฿${baht.format(total)}',
          style: TextStyle(
              fontSize: 20, fontWeight: FontWeight.w700, color: cs.primary)),
    ];
    final totalLabel = horizontalTotal
        ? Wrap(
            spacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: totalTexts)
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: totalTexts);
    // Secondary actions live behind a menu on phones and tablets so the bar
    // stays short enough to keep the basket visible.
    final actions = Wrap(
        alignment: WrapAlignment.end,
        spacing: 4,
        runSpacing: 4,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (canDiscount || canDebt)
            PopupMenuButton<String>(
              key: const ValueKey('checkout-more'),
              tooltip: 'ส่วนลด และค้างชำระ',
              icon: const Icon(Icons.more_vert),
              constraints: const BoxConstraints(minWidth: 180),
              onSelected: (value) {
                if (value == 'discount' && canDiscount) onDiscount();
                if (value == 'debt' && canDebt && hasItems) onDebt();
              },
              itemBuilder: (_) => [
                if (canDiscount)
                  const PopupMenuItem(value: 'discount', child: Text('ส่วนลด')),
                if (canDebt)
                  PopupMenuItem(
                      value: 'debt',
                      enabled: hasItems,
                      child: const Text('ค้างชำระ')),
              ],
            ),
          FilledButton(
            key: const ValueKey('checkout-pay'),
            onPressed: hasItems ? onCheckout : null,
            style: FilledButton.styleFrom(
                minimumSize: const Size(112, 48),
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10)),
            child: const Text('ชำระเงิน'),
          ),
        ]);
    return SafeArea(
        top: false,
        child: Container(
          padding: compact
              ? const EdgeInsets.symmetric(horizontal: 12, vertical: 8)
              : const EdgeInsets.fromLTRB(16, 12, 16, 8),
          decoration: BoxDecoration(
              color: cs.surface,
              border: Border(top: BorderSide(color: cs.outlineVariant))),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                OverflowBar(
                  spacing: 8,
                  overflowSpacing: 4,
                  alignment: MainAxisAlignment.spaceBetween,
                  overflowAlignment: OverflowBarAlignment.end,
                  children: [totalLabel, actions],
                ),
                if (discount > 0) ...[
                  const SizedBox(height: 4),
                  Text(
                      'รวม ฿${baht.format(subtotal)} · ส่วนลด ฿${baht.format(discount)}',
                      style:
                          TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
                ],
              ]),
        ));
  }
}
