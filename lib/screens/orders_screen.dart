import 'dart:async';
import '../models/order_queue.dart';
import 'order_sale_screen.dart';
import '../services/shop_database.dart';
import 'order_ticket_screen.dart';
import 'kitchen_screen.dart';
import 'package:flutter/material.dart';

import '../utils/money_format.dart';
import '../widgets/order_summary_card.dart';
import '../widgets/compact_action.dart';
import '../models/order.dart';

import '../services/order_service.dart';
import '../widgets/shop_operation.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  OrderQueue _filter = OrderQueue.action;
  late Stream<List<ShopOrder>> _orders = OrderService.watchAll();
  Timer? _clock;
  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  void _retry() => setState(() => _orders = OrderService.watchAll());

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('ออเดอร์ออนไลน์'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'หน้านี้แสดงรายการอะไร',
            icon: const Icon(Icons.help_outline),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('ออเดอร์ออนไลน์'),
                content: const Text(
                    'รายการที่ลูกค้าสั่งผ่านลิงก์หรือ QR ของร้าน\n\n'
                    'งานค้าง: งานที่ยังไม่เสร็จ รวมรายการรอตรวจเงิน\n'
                    'นัดล่วงหน้า: นัดรับตั้งแต่วันถัดไป หากมีหลักฐานรอตรวจจะอยู่ในงานค้าง\n'
                    'ประวัติ: ออเดอร์ที่เสร็จแล้วหรือยกเลิก\n\n'
                    'บิลขายที่เคาน์เตอร์และบิลโต๊ะ ดูได้ที่ รายงาน → รายงานยอดขาย → ประวัติการขาย'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('เข้าใจแล้ว')),
                ],
              ),
            ),
          ),
        ],
      ),
      body: StreamBuilder<List<ShopOrder>>(
        stream: _orders,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('โหลดออเดอร์ออนไลน์ไม่สำเร็จ กรุณาตรวจการเชื่อมต่อ'),
              TextButton.icon(
                  onPressed: _retry,
                  icon: const Icon(Icons.refresh),
                  label: const Text('ลองใหม่')),
            ]));
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final now = DateTime.now();
          final all = snap.data!;
          final orders = all
              .where((o) => matchesQueue(o, _filter, now))
              .toList()
            ..sort((a, b) => _filter == OrderQueue.history
                ? b.createdAt.compareTo(a.createdAt)
                : orderDueAt(a).compareTo(orderDueAt(b)));
          return Column(children: [
            SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.all(8),
                child: Row(children: [
                  for (final f in OrderQueue.values)
                    Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: _FilterChip(
                            label: f.label,
                            count: all
                                .where((o) => matchesQueue(o, f, now))
                                .length,
                            selected: _filter == f,
                            onTap: () => setState(() => _filter = f))),
                ])),
            Divider(height: 1, color: cs.outlineVariant),
            Expanded(
                child: orders.isEmpty
                    ? Center(
                        child:
                            Text('ไม่มีออเดอร์ออนไลน์ในหมวด ${_filter.label}'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: orders.length,
                        itemBuilder: (_, i) => _OrderCard(
                            key: ValueKey(orders[i].id),
                            order: orders[i],
                            urgency: pickupUrgency(orders[i], now)))),
          ]);
        },
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: selected ? cs.primary : cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(100),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(100),
        child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: selected ? cs.onPrimary : cs.onSurface,
                    ),
                  ),
                  if (count > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(
                        color: selected
                            ? cs.onPrimary.withValues(alpha: 0.2)
                            : cs.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        '$count',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: selected ? cs.onPrimary : cs.primary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            )),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final ShopOrder order;
  const _OrderCard(
      {super.key, required this.order, this.urgency, this.expanded = false});
  final String? urgency;
  final bool expanded;

  void _showSlip(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Container(
                    color: Theme.of(ctx).colorScheme.surface,
                    padding: const EdgeInsets.all(40),
                    child: const Text('โหลดสลิปไม่ได้'),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white),
                onPressed: () => Navigator.pop(ctx),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.black54,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => OrderSummaryCard(
        key: ValueKey(order.id),
        order: order,
        urgency: urgency,
        initiallyExpanded: expanded,
        onSlip: () => _showSlip(context, order.slipUrl!),
        onTicket: () => Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => OrderTicketScreen(order: order))),
        onKitchen: [OrderStatus.paid, OrderStatus.accepted, OrderStatus.ready]
                .contains(order.status)
            ? () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const KitchenScreen()))
            : null,
        actions: order.status == OrderStatus.pendingPayment
            ? _PendingPaymentActions(order: order)
            : [OrderStatus.paid, OrderStatus.accepted, OrderStatus.ready]
                    .contains(order.status)
                ? _ActionButtons(order: order)
                : null,
      );
}

class _PendingPaymentActions extends StatelessWidget {
  final ShopOrder order;
  const _PendingPaymentActions({required this.order});

  Future<void> _confirm(BuildContext context) async {
    final refCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยืนยันรับเงินแล้ว?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'ตรวจ ${order.customerName} โอน ${formatBaht(order.finalAmount)} '
              'ในแอปธนาคารแล้วหรือยัง?',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: refCtrl,
              decoration: const InputDecoration(
                labelText: 'เลขอ้างอิง (ไม่บังคับ)',
                hintText: 'เช่น เลขรายการจากสลิป',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('ยกเลิก'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('ได้รับเงินแล้ว'),
          ),
        ],
      ),
    );
    final paymentRef = refCtrl.text.trim();
    refCtrl.dispose();
    if (ok != true) return;
    if (!context.mounted) return;
    await performShopOperation(
        context,
        () => OrderService.confirmPaid(
              order.id,
              paymentRef: paymentRef.isEmpty ? null : paymentRef,
            ),
        success: 'บันทึกรับเงินและยอดขายแล้ว');
  }

  Future<void> _cancel(BuildContext context) async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
              title: const Text('ยกเลิกออเดอร์ที่ยังไม่ชำระ'),
              content: TextField(
                  controller: ctrl,
                  maxLength: 500,
                  decoration:
                      const InputDecoration(labelText: 'เหตุผลที่ยกเลิก')),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('กลับ')),
                FilledButton(
                    onPressed: () {
                      if (ctrl.text.trim().isNotEmpty) {
                        Navigator.pop(ctx, ctrl.text.trim());
                      }
                    },
                    child: const Text('ยืนยันยกเลิก')),
              ],
            ));
    ctrl.dispose();
    if (reason == null || !context.mounted) return;
    await performShopOperation(
        context,
        () => OrderService.updateStatus(order.id, OrderStatus.cancelled,
            reason: reason));
  }

  @override
  Widget build(BuildContext context) => ActionButtons(children: [
        OutlinedButton(
            onPressed: () => _cancel(context),
            style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('ยกเลิก')),
        FilledButton.icon(
            onPressed: () => _confirm(context),
            icon: const Icon(Icons.check, size: 18),
            label: const Text('ได้รับเงินแล้ว')),
      ]);
}

class _ActionButtons extends StatelessWidget {
  final ShopOrder order;
  const _ActionButtons({required this.order});

  Future<void> _update(BuildContext context, OrderStatus status) async {
    await performShopOperation(
        context, () => OrderService.updateStatus(order.id, status));
  }

  @override
  Widget build(BuildContext context) => ActionButtons(children: [
        OutlinedButton(
            onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => OrderSaleScreen(orderId: order.id))),
            style: OutlinedButton.styleFrom(
                foregroundColor: Theme.of(context).colorScheme.error),
            child: const Text('คืนเงิน')),
        FilledButton(
            onPressed: () => _update(context, _nextStatus),
            child: Text(_nextLabel)),
      ]);

  OrderStatus get _nextStatus => switch (order.status) {
        OrderStatus.paid => OrderStatus.accepted,
        OrderStatus.accepted => OrderStatus.ready,
        OrderStatus.ready => OrderStatus.completed,
        _ => OrderStatus.completed,
      };

  String get _nextLabel => switch (order.status) {
        OrderStatus.paid => 'รับออเดอร์',
        OrderStatus.accepted => 'พร้อมรับแล้ว',
        OrderStatus.ready => 'รับของแล้ว',
        _ => 'เสร็จสิ้น',
      };
}

/// A focused order view used by daily-close blockers.
class OrderDetailScreen extends StatefulWidget {
  const OrderDetailScreen({super.key, required this.orderId});
  final String orderId;
  @override
  State<OrderDetailScreen> createState() => _OrderDetailScreenState();
}

class _OrderDetailScreenState extends State<OrderDetailScreen> {
  late var _stream =
      ShopDatabase.shop.collection('orders').doc(widget.orderId).snapshots();
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('รายละเอียดออเดอร์ออนไลน์')),
      body: StreamBuilder(
          stream: _stream,
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(
                  child: TextButton(
                      onPressed: () => setState(() => _stream = ShopDatabase
                          .shop
                          .collection('orders')
                          .doc(widget.orderId)
                          .snapshots()),
                      child: const Text('โหลดไม่ได้ · ลองใหม่')));
            }
            if (!snap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            if (!snap.data!.exists) {
              return const Center(child: Text('ไม่พบออเดอร์นี้'));
            }
            return ListView(padding: const EdgeInsets.all(12), children: [
              _OrderCard(
                  expanded: true,
                  order: ShopOrder.fromFirestore(
                      snap.data!.data()!, snap.data!.id)),
            ]);
          }));
}
