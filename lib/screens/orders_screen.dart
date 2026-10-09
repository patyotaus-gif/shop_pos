import 'dart:async';
import '../models/order_queue.dart';
import 'order_sale_screen.dart';
import '../services/shop_database.dart';
import 'order_ticket_screen.dart';
import 'kitchen_screen.dart';
import 'package:flutter/material.dart';

import 'package:intl/intl.dart';
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
      appBar: AppBar(title: const Text('ออเดอร์'), centerTitle: true),
      body: StreamBuilder<List<ShopOrder>>(
        stream: _orders,
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Text('โหลดออเดอร์ไม่สำเร็จ กรุณาตรวจการเชื่อมต่อ'),
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
            ..sort((a, b) => _filter == OrderQueue.all
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
                    ? Center(child: Text('ไม่มีออเดอร์ในหมวด ${_filter.label}'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: orders.length,
                        itemBuilder: (_, i) => Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (pickupUrgency(orders[i], now)
                                      case final String urgency)
                                    Padding(
                                        padding: const EdgeInsets.all(8),
                                        child: Text(urgency,
                                            style: TextStyle(
                                                color: cs.error,
                                                fontWeight: FontWeight.bold))),
                                  _OrderCard(order: orders[i]),
                                ]))),
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
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: selected ? cs.onPrimary : cs.onSurface,
                ),
              ),
              if (count > 0) ...[
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: selected
                        ? cs.onPrimary.withValues(alpha: 0.2)
                        : cs.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: selected ? cs.onPrimary : cs.primary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _OrderCard extends StatelessWidget {
  final ShopOrder order;
  const _OrderCard({required this.order});

  static final _baht = NumberFormat('#,##0.00', 'th_TH');
  static final _dt = DateFormat('dd/MM HH:mm', 'th_TH');

  Color get _statusColor => switch (order.status) {
        OrderStatus.paid => Colors.blue,
        OrderStatus.accepted => Colors.orange,
        OrderStatus.ready => Colors.green,
        OrderStatus.completed => Colors.grey,
        OrderStatus.cancelled => Colors.red,
        OrderStatus.pendingPayment => Colors.grey,
      };

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
                    color: Colors.white,
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
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(order.customerName,
                          style: const TextStyle(
                              fontWeight: FontWeight.bold, fontSize: 15)),
                      Text(order.customerPhone,
                          style: const TextStyle(
                              color: Colors.grey, fontSize: 13)),
                      if (order.pickupDescription != null)
                        Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text(order.pickupDescription!,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF7A1F2B)))),
                      // QR-link context: โต๊ะ / รับกลับบ้าน
                      if (order.tableName != null ||
                          order.orderType == 'takeaway')
                        Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Text(
                            order.tableName != null
                                ? '🍽️ โต๊ะ ${order.tableName}'
                                : '🛍️ รับกลับบ้าน',
                            style: const TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: Color(0xFF7A1F2B)),
                          ),
                        ),
                    ],
                  ),
                ),
                if (order.autoConfirmed) ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.verified, size: 12, color: Colors.blue),
                        SizedBox(width: 3),
                        Text(
                          'auto',
                          style: TextStyle(
                            color: Colors.blue,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: _statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(order.status.label,
                      style: TextStyle(
                          color: _statusColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            if (order.bankMatchPending &&
                order.status == OrderStatus.pendingPayment)
              const Text(
                  'พบแจ้งเตือนยอดเงินตรงกัน โปรดตรวจเงินเข้าในแอปธนาคารก่อนยืนยัน'),
            if (order.slipUrl != null) ...[
              const SizedBox(height: 8),
              GestureDetector(
                onTap: () => _showSlip(context, order.slipUrl!),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    order.slipUrl!,
                    height: 80,
                    fit: BoxFit.cover,
                    width: double.infinity,
                    errorBuilder: (_, __, ___) => Container(
                      height: 80,
                      color: Colors.grey.shade200,
                      alignment: Alignment.center,
                      child: const Text('โหลดสลิปไม่ได้',
                          style: TextStyle(color: Colors.grey)),
                    ),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            // Items
            ...order.items.map((item) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                          child: Text(
                              '${item.productName} × ${item.quantity}${item.preparationNote.isEmpty ? '' : '\n${item.preparationNote}'}',
                              style: const TextStyle(fontSize: 13))),
                      Text('฿${_baht.format(item.subtotal)}',
                          style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                )),
            const Divider(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(_dt.format(order.createdAt),
                    style: const TextStyle(color: Colors.grey, fontSize: 12)),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (order.status != OrderStatus.cancelled)
                      Text(
                        order.status == OrderStatus.pendingPayment
                            ? 'ยอดที่ต้องชำระ'
                            : 'ยอดรับเงิน',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 11,
                        ),
                      ),
                    Text(
                      '฿${_baht.format(order.paymentMethod == 'stripe' ? order.total : order.finalAmount)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 15,
                        color: order.status == OrderStatus.pendingPayment
                            ? Colors.orange.shade800
                            : null,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  icon: const Icon(Icons.print_outlined),
                  label: const Text('ใบงาน / พิมพ์ / PDF'),
                  onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                          builder: (_) => OrderTicketScreen(order: order))),
                )),
            // Action buttons
            if ([OrderStatus.paid, OrderStatus.accepted, OrderStatus.ready]
                .contains(order.status))
              TextButton.icon(
                icon: const Icon(Icons.soup_kitchen_outlined),
                label: const Text('จอครัว / พิมพ์ที่ครัว'),
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => const KitchenScreen())),
              ),
            if (order.status == OrderStatus.pendingPayment) ...[
              const SizedBox(height: 10),
              _PendingPaymentActions(order: order),
            ] else if (order.status == OrderStatus.paid ||
                order.status == OrderStatus.accepted ||
                order.status == OrderStatus.ready) ...[
              const SizedBox(height: 10),
              _ActionButtons(order: order),
            ],
          ],
        ),
      ),
    );
  }
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
              'ตรวจ ${order.customerName} โอน ฿${order.finalAmount.toStringAsFixed(2)} '
              'ในแอปธนาคารแล้วหรือยัง?',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: refCtrl,
              decoration: const InputDecoration(
                labelText: 'เลขอ้างอิง (optional)',
                hintText: 'เช่น เลข trans จาก slip',
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
            style: FilledButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('ได้รับเงินแล้ว'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    if (!context.mounted) return;
    await performShopOperation(
        context,
        () => OrderService.confirmPaid(
              order.id,
              paymentRef:
                  refCtrl.text.trim().isEmpty ? null : refCtrl.text.trim(),
            ),
        success: 'บันทึกรับเงินและยอดขายแล้ว');
    refCtrl.dispose();
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
  Widget build(BuildContext context) {
    return Row(
      children: [
        OutlinedButton(
          onPressed: () => _cancel(context),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.red,
            side: const BorderSide(color: Colors.red),
            padding: const EdgeInsets.symmetric(horizontal: 12),
          ),
          child: const Text('ยกเลิก', style: TextStyle(fontSize: 13)),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: FilledButton.icon(
            onPressed: () => _confirm(context),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.green,
              padding: const EdgeInsets.symmetric(horizontal: 12),
            ),
            icon: const Icon(Icons.check, size: 18),
            label: const Text('ได้รับเงินแล้ว', style: TextStyle(fontSize: 13)),
          ),
        ),
      ],
    );
  }
}

class _ActionButtons extends StatelessWidget {
  final ShopOrder order;
  const _ActionButtons({required this.order});

  Future<void> _update(BuildContext context, OrderStatus status) async {
    await performShopOperation(
        context, () => OrderService.updateStatus(order.id, status));
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Cancel
        OutlinedButton(
          onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => OrderSaleScreen(orderId: order.id))),
          style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
              padding: const EdgeInsets.symmetric(horizontal: 12)),
          child: const Text('คืนเงิน', style: TextStyle(fontSize: 13)),
        ),
        const SizedBox(width: 8),
        // Main action
        Expanded(
          child: FilledButton(
            onPressed: () => _update(context, _nextStatus),
            style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 12)),
            child: Text(_nextLabel, style: const TextStyle(fontSize: 13)),
          ),
        ),
      ],
    );
  }

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
      appBar: AppBar(title: const Text('รายละเอียดออเดอร์')),
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
                  order: ShopOrder.fromFirestore(
                      snap.data!.data()!, snap.data!.id)),
            ]);
          }));
}
