import '../widgets/content_width.dart';
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
import '../services/staff_access_service.dart';
import '../services/auth_service.dart';
import '../widgets/shop_operation.dart';

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  OrderQueue _filter = OrderQueue.confirmation;
  late Stream<List<ShopOrder>> _orders = OrderService.watchAll();
  final _search = TextEditingController();
  String? _selectedId;
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
    _search.dispose();
    super.dispose();
  }

  void _retry() => setState(() => _orders = OrderService.watchAll());

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('ออเดอร์'),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: 'หน้านี้แสดงรายการอะไร',
            icon: const Icon(Icons.help_outline),
            onPressed: () => showDialog<void>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('ออเดอร์'),
                content: const Text(
                    'รายการที่ลูกค้าสั่งผ่านลิงก์หรือ QR ของร้าน\n\n'
                    'รอยืนยัน: รอชำระ รอตรวจเงิน หรือชำระแล้วรอร้านรับออเดอร์\n'
                    'กำลังเตรียม: ร้านรับออเดอร์และเริ่มจัดเตรียมแล้ว\n'
                    'พร้อมรับ: เตรียมเสร็จแล้ว รอส่งมอบให้ลูกค้า\n'
                    'นัดล่วงหน้า: นัดรับตั้งแต่วันถัดไปที่ยังไม่เริ่มเตรียม หากมีหลักฐานรอตรวจจะอยู่ในรอยืนยัน เมื่อเริ่มเตรียมจะย้ายไปกำลังเตรียม\n'
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
      body: ContentWidth(
          maxWidth: 1040,
          child: StreamBuilder<List<ShopOrder>>(
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
                  .where((o) =>
                      matchesQueue(o, _filter, now) &&
                      matchesOrderSearch(o, _search.text))
                  .toList()
                ..sort((a, b) => _filter == OrderQueue.history
                    ? b.createdAt.compareTo(a.createdAt)
                    : orderDueAt(a).compareTo(orderDueAt(b)));
              return Column(children: [
                if (AuthService.isStaff && _filter == OrderQueue.history)
                  const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('ประวัติจาก 100 ออเดอร์ล่าสุดของร้าน')),
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
                                onTap: () => setState(() {
                                      _filter = f;
                                      _search.clear();
                                      _selectedId = null;
                                    }))),
                    ])),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                  child: TextField(
                    controller: _search,
                    textInputAction: TextInputAction.search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      labelText: 'ค้นหาเลขออเดอร์ ชื่อลูกค้า หรือเมนู',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'ล้างคำค้น',
                              icon: const Icon(Icons.clear),
                              onPressed: () => setState(_search.clear),
                            ),
                    ),
                  ),
                ),
                Divider(height: 1, color: cs.outlineVariant),
                Expanded(
                    child: orders.isEmpty
                        ? Center(
                            child: Text(_search.text.trim().isEmpty
                                ? 'ไม่มีออเดอร์ในหมวด ${_filter.label}'
                                : 'ไม่พบออเดอร์ที่ตรงกับคำค้นในหมวด ${_filter.label}'))
                        : LayoutBuilder(builder: (context, constraints) {
                            final wide = constraints.maxWidth >= 760;
                            final selected = orders.firstWhere(
                                (o) => o.id == _selectedId,
                                orElse: () => orders.first);
                            final list = ListView.separated(
                              keyboardDismissBehavior:
                                  ScrollViewKeyboardDismissBehavior.onDrag,
                              itemCount: orders.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(height: 1),
                              itemBuilder: (_, i) {
                                final order = orders[i];
                                final locale =
                                    MaterialLocalizations.of(context);
                                final created = order.createdAt.toLocal();
                                final time = locale.formatTimeOfDay(
                                    TimeOfDay.fromDateTime(created),
                                    alwaysUse24HourFormat: true);
                                return ListTile(
                                  key: ValueKey('queue-${order.id}'),
                                  selected: wide && selected.id == order.id,
                                  selectedTileColor: cs.secondaryContainer,
                                  title: Text(order.displayLabel),
                                  subtitle: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                          [
                                            if (!DateUtils.isSameDay(
                                                created, now))
                                              locale.formatShortDate(created),
                                            time,
                                            if (order.customerName.isNotEmpty)
                                              order.customerName,
                                            ...order.items.map((item) =>
                                                '${item.productName} × ${item.quantity}')
                                          ].join(' · '),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis),
                                      if (order.pickupLabel != null)
                                        Text(
                                            'นัดรับ ${order.pickupLabel} (เวลาไทย)'),
                                      if (pickupUrgency(order, now)
                                          case final urgency?)
                                        Text(urgency,
                                            style: TextStyle(color: cs.error)),
                                      Wrap(
                                          spacing: 8,
                                          crossAxisAlignment:
                                              WrapCrossAlignment.center,
                                          children: [
                                            Text(formatBaht(
                                                order.paymentMethod == 'stripe'
                                                    ? order.total
                                                    : order.finalAmount)),
                                            OrderPaymentBadge(order: order),
                                          ]),
                                    ],
                                  ),
                                  trailing: const Icon(Icons.chevron_right),
                                  onTap: () {
                                    FocusScope.of(context).unfocus();
                                    if (wide) {
                                      setState(() => _selectedId = order.id);
                                    } else {
                                      Navigator.of(context).push(
                                          MaterialPageRoute<void>(
                                              builder: (_) => OrderDetailScreen(
                                                  orderId: order.id)));
                                    }
                                  },
                                );
                              },
                            );
                            if (!wide) return list;
                            return Row(children: [
                              Expanded(flex: 4, child: list),
                              const VerticalDivider(width: 1),
                              Expanded(
                                  flex: 6,
                                  child: ListView(
                                    key: ValueKey('detail-${selected.id}'),
                                    padding: const EdgeInsets.all(12),
                                    children: [
                                      _OrderCard(
                                          order: selected,
                                          urgency: pickupUrgency(selected, now),
                                          expanded: true)
                                    ],
                                  )),
                            ]);
                          })),
              ]);
            },
          )),
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
      {required this.order, this.urgency, this.expanded = false});
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
        onReceipt: order.canOpenReceipt
            ? () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => OrderSaleScreen(orderId: order.id)))
            : null,
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
            onPressed: StaffAccessService.can('cancel')
                ? () => _cancel(context)
                : null,
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
  Stream<Map<String, dynamic>?> _watch() => AuthService.isStaff
      ? StaffAccessService.watchRecord('orders', widget.orderId)
      : ShopDatabase.shop
          .collection('orders')
          .doc(widget.orderId)
          .snapshots()
          .map((d) => d.data());
  late var _stream = _watch();
  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('รายละเอียดออเดอร์')),
      body: ContentWidth(
          maxWidth: 1040,
          child: StreamBuilder(
              stream: _stream,
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(
                      child: TextButton(
                          onPressed: () => setState(() => _stream = _watch()),
                          child: const Text('โหลดไม่ได้ · ลองใหม่')));
                }
                if (snap.connectionState == ConnectionState.waiting &&
                    !snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snap.hasData) {
                  return const Center(child: Text('ไม่พบออเดอร์นี้'));
                }
                final order =
                    ShopOrder.fromFirestore(snap.data!, widget.orderId);
                return ListView(padding: const EdgeInsets.all(12), children: [
                  _OrderCard(
                      expanded: true,
                      urgency: pickupUrgency(order, DateTime.now()),
                      order: order),
                ]);
              })));
}
