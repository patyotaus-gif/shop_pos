import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/order.dart';
import '../theme/operational_colors.dart';
import '../utils/money_format.dart';
import 'status_badge.dart';

/// Presentation only. Payment, refund and preparation actions belong to the caller.
class OrderSummaryCard extends StatefulWidget {
  const OrderSummaryCard(
      {super.key,
      required this.order,
      required this.onTicket,
      required this.onSlip,
      this.onKitchen,
      this.actions,
      this.urgency,
      this.initiallyExpanded = false});
  final ShopOrder order;
  final VoidCallback onTicket, onSlip;
  final VoidCallback? onKitchen;
  final Widget? actions;
  final String? urgency;
  final bool initiallyExpanded;

  @override
  State<OrderSummaryCard> createState() => _OrderSummaryCardState();
}

class _OrderSummaryCardState extends State<OrderSummaryCard> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final cs = Theme.of(context).colorScheme;
    final tone = switch (order.status) {
      OrderStatus.pendingPayment ||
      OrderStatus.accepted =>
        OperationalTone.warning,
      OrderStatus.paid => OperationalTone.information,
      OrderStatus.ready => OperationalTone.success,
      OrderStatus.completed => OperationalTone.neutral,
      OrderStatus.cancelled => OperationalTone.danger,
    };
    final icon = switch (order.status) {
      OrderStatus.pendingPayment => Icons.payments_outlined,
      OrderStatus.paid => Icons.receipt_long_outlined,
      OrderStatus.accepted => Icons.soup_kitchen_outlined,
      OrderStatus.ready => Icons.shopping_bag_outlined,
      OrderStatus.completed => Icons.check_circle_outline,
      OrderStatus.cancelled => Icons.cancel_outlined,
    };
    final shownItems = _expanded ? order.items : order.items.take(2);
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
          padding: const EdgeInsets.all(16),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            if (order.pickupDescription != null)
              Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.schedule, size: 20, color: cs.onSurface),
                        const SizedBox(width: 8),
                        Expanded(
                            child: Text(order.pickupDescription!,
                                style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w700))),
                      ])),
            Wrap(spacing: 8, runSpacing: 8, children: [
              StatusBadge(label: order.status.label, tone: tone, icon: icon),
              if (widget.urgency != null)
                StatusBadge(
                    label: widget.urgency!,
                    tone: OperationalTone.danger,
                    icon: Icons.schedule),
            ]),
            const SizedBox(height: 10),
            Text(order.customerName,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            if (order.tableName != null || order.orderType == 'takeaway')
              Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(children: [
                    Icon(
                        order.tableName != null
                            ? Icons.table_restaurant_outlined
                            : Icons.takeout_dining_outlined,
                        size: 18,
                        color: cs.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text(
                            order.tableName != null
                                ? 'โต๊ะ ${order.tableName}'
                                : 'รับกลับบ้าน',
                            style: TextStyle(
                                fontSize: 14, color: cs.onSurfaceVariant))),
                  ])),
            const SizedBox(height: 10),
            for (final item in shownItems)
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text('${item.productName} × ${item.quantity}',
                            style: const TextStyle(fontSize: 14)),
                        if (item.preparationNote.isNotEmpty)
                          Text(item.preparationNote,
                              style: TextStyle(
                                  fontSize: 14, color: cs.onSurfaceVariant)),
                        if (_expanded)
                          Text(formatBaht(item.subtotal),
                              textAlign: TextAlign.end,
                              style: const TextStyle(fontSize: 14)),
                      ])),
            const Divider(height: 20),
            Text(
                order.status == OrderStatus.pendingPayment
                    ? 'ยอดที่ต้องชำระ'
                    : order.status == OrderStatus.cancelled
                        ? 'ยอดออเดอร์'
                        : 'ยอดรับเงิน',
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
            Text(
                formatBaht(order.paymentMethod == 'stripe'
                    ? order.total
                    : order.finalAmount),
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface)),
            if (order.bankMatchPending &&
                order.status == OrderStatus.pendingPayment)
              Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                      'พบแจ้งเตือนยอดเงินตรงกัน โปรดตรวจเงินเข้าในแอปธนาคารก่อนยืนยัน',
                      style: TextStyle(
                          fontSize: 14,
                          color: OperationalColors.of(
                                  context, OperationalTone.warning)
                              .foreground))),
            if (order.slipUrl != null)
              Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                      onPressed: widget.onSlip,
                      icon: const Icon(Icons.image_outlined),
                      label: const Text('ดูสลิปการโอน'))),
            if (widget.actions != null) ...[
              const SizedBox(height: 10),
              widget.actions!,
            ],
            Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                    onPressed: () => setState(() => _expanded = !_expanded),
                    icon:
                        Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                    label: Text(_expanded
                        ? 'ย่อรายละเอียด'
                        : order.items.length > 2
                            ? 'รายละเอียด · ดูครบ ${order.items.length} รายการ'
                            : 'รายละเอียดออเดอร์'))),
            if (_expanded) ...[
              Text(
                  'โทร ${order.customerPhone.isEmpty ? 'ไม่ระบุ' : order.customerPhone}',
                  style: TextStyle(fontSize: 14, color: cs.onSurfaceVariant)),
              Text(
                  'สั่งเมื่อ ${DateFormat('dd/MM HH:mm', 'th_TH').format(order.createdAt)}',
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
              if (order.autoConfirmed)
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Align(
                        alignment: Alignment.centerLeft,
                        child: StatusBadge(
                            label: 'ยืนยันอัตโนมัติ',
                            tone: OperationalTone.information,
                            icon: Icons.verified_outlined))),
              Wrap(spacing: 8, runSpacing: 4, children: [
                TextButton.icon(
                    onPressed: widget.onTicket,
                    icon: const Icon(Icons.print_outlined),
                    label: const Text('ใบงาน / พิมพ์ / PDF')),
                if (widget.onKitchen != null)
                  TextButton.icon(
                      onPressed: widget.onKitchen,
                      icon: const Icon(Icons.soup_kitchen_outlined),
                      label: const Text('จอครัว / พิมพ์ที่ครัว')),
              ]),
            ],
          ])),
    );
  }
}
