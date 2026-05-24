import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../models/order.dart';
import '../services/auth_service.dart';
import '../services/order_service.dart';

class OrdersScreen extends StatelessWidget {
  const OrdersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Orders'),
          centerTitle: true,
          bottom: const TabBar(
            tabs: [
              Tab(text: 'รอดำเนินการ'),
              Tab(text: 'ทั้งหมด'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _OrderList(stream: OrderService.watchActive()),
            _OrderList(stream: OrderService.watchAll()),
          ],
        ),
        // แสดงลิงก์แชร์ให้ลูกค้า
        floatingActionButton: _ShareLinkButton(),
      ),
    );
  }
}

class _ShareLinkButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final shopId = AuthService.shopId ?? '';
    final link = 'https://pok-pok.app/order/?shop=$shopId';

    return FloatingActionButton.extended(
      onPressed: () => _showLinkDialog(context, link),
      icon: const Icon(Icons.link),
      label: const Text('ลิงก์สั่งออนไลน์'),
    );
  }

  void _showLinkDialog(BuildContext context, String link) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('ลิงก์สำหรับลูกค้า',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('แชร์ลิงก์นี้ให้ลูกค้าเพื่อให้สั่งสินค้าออนไลน์',
                style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(link,
                  style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: link));
                  if (!context.mounted) return;
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('คัดลอกลิงก์แล้ว')),
                  );
                },
                icon: const Icon(Icons.copy),
                label: const Text('คัดลอกลิงก์'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderList extends StatelessWidget {
  final Stream<List<ShopOrder>> stream;
  const _OrderList({required this.stream});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<ShopOrder>>(
      stream: stream,
      builder: (ctx, snap) {
        if (snap.hasError) return const Center(child: Text('โหลดข้อมูลไม่สำเร็จ'));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final orders = snap.data!;
        if (orders.isEmpty) {
          return const Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.inbox_outlined, size: 64, color: Colors.grey),
                SizedBox(height: 8),
                Text('ยังไม่มี order', style: TextStyle(color: Colors.grey)),
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
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
    await OrderService.confirmPaid(
      order.id,
      paymentRef: refCtrl.text.trim().isEmpty ? null : refCtrl.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        OutlinedButton(
          onPressed: () =>
              OrderService.updateStatus(order.id, OrderStatus.cancelled),
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

  Future<void> _update(OrderStatus status) =>
      OrderService.updateStatus(order.id, status);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Cancel
        OutlinedButton(
          onPressed: () => _update(OrderStatus.cancelled),
          style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
              padding: const EdgeInsets.symmetric(horizontal: 12)),
          child: const Text('ยกเลิก', style: TextStyle(fontSize: 13)),
        ),
        const SizedBox(width: 8),
        // Main action
        Expanded(
          child: FilledButton(
            onPressed: () => _update(_nextStatus),
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
