import 'package:flutter/material.dart';
import '../widgets/shop_operation.dart';

import '../models/table_order.dart';
import '../services/table_service.dart';

/// Kitchen display — one card per table tab that has any item the kitchen
/// is working on (sent or ready). Cashier hits "ส่งครัว" on the table
/// detail screen → cards show up here → kitchen taps each item to mark it
/// ready. Pending items (not yet sent) are hidden so the kitchen only
/// sees what the cashier has confirmed.
///
/// Designed for a tablet stand in the kitchen — large tap targets, no
/// nested menus, status colours that read at arm's length.
class KitchenScreen extends StatelessWidget {
  const KitchenScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('ครัว'), centerTitle: true),
      body: StreamBuilder<List<TableOrder>>(
        stream: TableService.watchOpenOrders(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          // Keep only orders with at least one item the kitchen owns.
          final orders = (snap.data ?? const <TableOrder>[])
              .where((o) => o.items.any((i) =>
                  i.kitchenStatus == KitchenStatus.sent ||
                  i.kitchenStatus == KitchenStatus.ready))
              .toList();

          if (orders.isEmpty) return const _EmptyKitchen();

          return GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 360,
              childAspectRatio: 0.95,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: orders.length,
            itemBuilder: (_, i) => _TicketCard(order: orders[i]),
          );
        },
      ),
    );
  }
}

class _TicketCard extends StatelessWidget {
  const _TicketCard({required this.order});
  final TableOrder order;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final kitchenItems = order.items
        .asMap()
        .entries
        .where((e) =>
            e.value.kitchenStatus == KitchenStatus.sent ||
            e.value.kitchenStatus == KitchenStatus.ready)
        .toList();

    final allReady =
        kitchenItems.every((e) => e.value.kitchenStatus == KitchenStatus.ready);

    return Material(
      color: allReady ? Colors.green.withValues(alpha: 0.08) : cs.surface,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: allReady ? Colors.green : cs.outlineVariant,
            width: allReady ? 2 : 1,
          ),
        ),
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.table_restaurant_outlined,
                    color: cs.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('โต๊ะ ${order.tableName}',
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w800)),
                ),
                if (allReady)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(100),
                    ),
                    child: const Text('พร้อมเสิร์ฟทั้งหมด',
                        style: TextStyle(
                            fontSize: 10,
                            color: Colors.green,
                            fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _elapsed(order.openedAt),
              style: TextStyle(
                  fontSize: 11, color: cs.onSurface.withValues(alpha: 0.6)),
            ),
            const Divider(height: 16),
            Expanded(
              child: ListView.separated(
                itemCount: kitchenItems.length,
                separatorBuilder: (_, __) => const SizedBox(height: 6),
                itemBuilder: (_, i) {
                  final entry = kitchenItems[i];
                  return _ItemRow(
                    orderId: order.id,
                    item: entry.value,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _elapsed(DateTime opened) {
    final mins = DateTime.now().difference(opened).inMinutes;
    if (mins < 1) return 'เปิดเมื่อสักครู่';
    if (mins < 60) return 'เปิดมา $mins นาที';
    final h = mins ~/ 60;
    return 'เปิดมา $h ชม. ${mins % 60} นาที';
  }
}

class _ItemRow extends StatelessWidget {
  const _ItemRow({
    required this.orderId,
    required this.item,
  });

  final String orderId;
  final TableOrderItem item;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ready = item.kitchenStatus == KitchenStatus.ready;
    final modifierLine = item.modifiers.isEmpty
        ? null
        : item.modifiers.map((m) => m.optionName).join(' · ');

    return InkWell(
      onTap: ready
          ? null
          : () => performShopOperation(
              context, () => TableService.markItemReady(orderId, item.id),
              success: 'พร้อมเสิร์ฟแล้ว'),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: ready
              ? Colors.green.withValues(alpha: 0.1)
              : Colors.amber.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: ready
                ? Colors.green.withValues(alpha: 0.5)
                : Colors.amber.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: cs.primary,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('×${item.quantity}',
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 12)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.productName,
                      style: const TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w700)),
                  if (modifierLine != null)
                    Text('• $modifierLine',
                        style: TextStyle(
                            fontSize: 11,
                            color: cs.onSurface.withValues(alpha: 0.7))),
                  if (item.notes != null && item.notes!.isNotEmpty)
                    Text('โน้ต: ${item.notes}',
                        style: const TextStyle(
                            fontSize: 11, color: Colors.deepOrange)),
                ],
              ),
            ),
            Icon(
              ready ? Icons.check_circle : Icons.local_fire_department,
              color: ready ? Colors.green : Colors.amber.shade700,
              size: 22,
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyKitchen extends StatelessWidget {
  const _EmptyKitchen();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.soup_kitchen_outlined,
                size: 72, color: cs.onSurface.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            const Text('ยังไม่มีออเดอร์เข้าครัว',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(
              'รอจนกว่าหน้าโต๊ะจะกด "ส่งครัว"',
              style: TextStyle(
                  fontSize: 13, color: cs.onSurface.withValues(alpha: 0.6)),
            ),
          ],
        ),
      ),
    );
  }
}
