import 'package:flutter/material.dart';

import 'package:intl/intl.dart';
import '../models/order.dart';

import '../services/order_service.dart';
import '../widgets/shop_operation.dart';

/// Top-of-screen filter — replaces the old "รอดำเนินการ / ทั้งหมด" tabs.
/// `action` is the default because that's what the shop owner opens this
/// screen for: "what do I need to deal with?".
enum _OrderFilter { action, pendingPayment, all }

extension _OrderFilterX on _OrderFilter {
  String get label => switch (this) {
        _OrderFilter.action => 'ต้องทำต่อ',
        _OrderFilter.pendingPayment => 'รอชำระ',
        _OrderFilter.all => 'ทั้งหมด',
      };

  /// Server-side stream selection — we use the existing watchActive query
  /// when possible (smaller payload) and fall back to watchAll when the
  /// chip needs orders outside the active window.
  bool matches(ShopOrder order) => switch (this) {
        _OrderFilter.action => const {
            OrderStatus.pendingPayment,
            OrderStatus.paid,
            OrderStatus.accepted,
            OrderStatus.ready,
          }.contains(order.status),
        _OrderFilter.pendingPayment =>
          order.status == OrderStatus.pendingPayment,
        _OrderFilter.all => true,
      };
}

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  _OrderFilter _filter = _OrderFilter.action;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Orders'), centerTitle: true),
      body: Column(
        children: [
          // Filter chips — replaces the old TabBar. One row of pills along
          // the top so it stays out of the way of the order cards.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final f in _OrderFilter.values) ...[
                    StreamBuilder<List<ShopOrder>>(
                      stream: OrderService.watchAll(),
                      builder: (context, snap) {
                        final count =
                            (snap.data ?? const []).where(f.matches).length;
                        return _FilterChip(
                          label: f.label,
                          count: count,
                          selected: _filter == f,
                          onTap: () => setState(() => _filter = f),
                        );
                      },
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant),
          Expanded(
            child: _OrderList(
              stream: OrderService.watchAll(),
              filter: _filter,
            ),
          ),
        ],
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

class _OrderList extends StatelessWidget {
  final Stream<List<ShopOrder>> stream;
  final _OrderFilter filter;
  const _OrderList({required this.stream, required this.filter});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ShopOrder>>(
      stream: stream,
      builder: (ctx, snap) {
        if (snap.hasError) {
          return const Center(child: Text('โหลดข้อมูลไม่สำเร็จ'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final orders = snap.data!.where(filter.matches).toList();
        if (orders.isEmpty) {
          // Tailor the empty copy to the chip so the user knows whether
          // there's nothing to do vs. nothing at all.
          final msg = switch (filter) {
            _OrderFilter.action => 'ไม่มี order ที่ต้องทำต่อ',
            _OrderFilter.pendingPayment => 'ไม่มี order รอชำระ',
            _OrderFilter.all => 'ยังไม่มี order',
          };
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.inbox_outlined, size: 64, color: Colors.grey),
                const SizedBox(height: 8),
                Text(msg, style: const TextStyle(color: Colors.grey)),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: orders.length,
          itemBuilder: (ctx, i) => _OrderCard(order: orders[i]),
        );
      },
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
                      Text('${item.productName} × ${item.quantity}',
                          style: const TextStyle(fontSize: 13)),
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
                    if (order.status == OrderStatus.pendingPayment &&
                        order.finalAmount != order.total)
                      Text(
                        'ยอดที่ต้องโอน',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 11,
                        ),
                      ),
                    Text(
                      '฿${_baht.format(order.status == OrderStatus.pendingPayment ? order.finalAmount : order.total)}',
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
            // Action buttons
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
          onPressed: () => showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                    title: const Text('ออเดอร์นี้รับชำระแล้ว'),
                    content: const Text(
                        'คืนเงินได้ที่ รายงาน → รายการขาย → เลือกบิล → คืนเงิน เพื่อให้ยอดขาย สต็อก และเงินในรอบตรงกัน'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('ตกลง'))
                    ],
                  )),
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
        OrderStatus.paid => 'ยืนยัน order',
        OrderStatus.accepted => 'พร้อมรับแล้ว',
        OrderStatus.ready => 'รับของแล้ว',
        _ => 'เสร็จสิ้น',
      };
}
