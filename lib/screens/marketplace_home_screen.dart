import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/marketplace_order.dart';
import '../models/supplier.dart';
import '../services/marketplace_service.dart';
import 'supplier_catalog_screen.dart';

/// Marketplace landing — two tabs: suppliers to browse, and the shop's
/// own B2B order history. Available in every tier.
class MarketplaceHomeScreen extends StatelessWidget {
  const MarketplaceHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('สั่งของ'),
          centerTitle: true,
          bottom: const TabBar(
            tabs: [
              Tab(text: 'ร้านส่ง'),
              Tab(text: 'ออเดอร์ของฉัน'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _SuppliersTab(),
            _MyOrdersTab(),
          ],
        ),
      ),
    );
  }
}

class _SuppliersTab extends StatelessWidget {
  const _SuppliersTab();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return StreamBuilder<List<Supplier>>(
      stream: MarketplaceService.watchSuppliers(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final suppliers = snap.data ?? const [];
        if (suppliers.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.storefront_outlined,
                      size: 72,
                      color: cs.onSurface.withValues(alpha: 0.3)),
                  const SizedBox(height: 16),
                  const Text('ยังไม่มีร้านส่งในพื้นที่',
                      style: TextStyle(
                          fontSize: 17, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(
                    'เรากำลังเชิญ supplier เข้ามาเพิ่ม — เร็วๆ นี้คุณจะสั่งของได้ในแอป',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurface.withValues(alpha: 0.6)),
                  ),
                ],
              ),
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: suppliers.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) => _SupplierCard(supplier: suppliers[i]),
        );
      },
    );
  }
}

class _SupplierCard extends StatelessWidget {
  const _SupplierCard({required this.supplier});
  final Supplier supplier;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => SupplierCatalogScreen(supplier: supplier),
        )),
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: cs.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                clipBehavior: Clip.antiAlias,
                child: supplier.imageUrl != null
                    ? Image.network(supplier.imageUrl!,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Icon(
                            Icons.storefront, color: cs.primary))
                    : Icon(Icons.storefront, color: cs.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(supplier.name,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
                    if (supplier.category.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(supplier.category,
                          style: TextStyle(
                              fontSize: 12,
                              color:
                                  cs.onSurface.withValues(alpha: 0.6))),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (supplier.deliveryDays != null) ...[
                          Icon(Icons.local_shipping_outlined,
                              size: 12,
                              color:
                                  cs.onSurface.withValues(alpha: 0.5)),
                          const SizedBox(width: 3),
                          Text(supplier.deliveryDays!,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: cs.onSurface
                                      .withValues(alpha: 0.6))),
                          const SizedBox(width: 10),
                        ],
                        if (supplier.minOrder > 0) ...[
                          Icon(Icons.shopping_basket_outlined,
                              size: 12,
                              color:
                                  cs.onSurface.withValues(alpha: 0.5)),
                          const SizedBox(width: 3),
                          Text('ขั้นต่ำ ฿${supplier.minOrder.toStringAsFixed(0)}',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: cs.onSurface
                                      .withValues(alpha: 0.6))),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _MyOrdersTab extends StatelessWidget {
  const _MyOrdersTab();

  static final _baht = NumberFormat('#,##0.00', 'th_TH');
  static final _dt = DateFormat('dd/MM HH:mm', 'th_TH');

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return StreamBuilder<List<MarketplaceOrder>>(
      stream: MarketplaceService.watchMyOrders(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        final orders = snap.data ?? const [];
        if (orders.isEmpty) {
          return Center(
            child: Text('ยังไม่มีออเดอร์สั่งของ',
                style: TextStyle(
                    color: cs.onSurface.withValues(alpha: 0.5))),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: orders.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) =>
              _MyOrderCard(order: orders[i], baht: _baht, dt: _dt),
        );
      },
    );
  }
}

class _MyOrderCard extends StatelessWidget {
  const _MyOrderCard({
    required this.order,
    required this.baht,
    required this.dt,
  });
  final MarketplaceOrder order;
  final NumberFormat baht;
  final DateFormat dt;

  Color _statusColor(BuildContext context) => switch (order.status) {
        MarketplaceOrderStatus.placed => Colors.orange,
        MarketplaceOrderStatus.accepted => Colors.blue,
        MarketplaceOrderStatus.shipped => Colors.indigo,
        MarketplaceOrderStatus.delivered => Colors.green,
        MarketplaceOrderStatus.cancelled => Colors.red,
      };

  Future<void> _cancel(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('ยกเลิกออเดอร์?'),
        content: Text('ยกเลิกออเดอร์จาก ${order.supplierName}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('กลับ')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('ยกเลิก'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await MarketplaceService.cancelOrder(order);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  Future<void> _confirmDelivered(BuildContext context) async {
    try {
      await MarketplaceService.confirmDelivered(order);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final statusColor = _statusColor(context);
    final canCancel = order.status == MarketplaceOrderStatus.placed ||
        order.status == MarketplaceOrderStatus.accepted;
    final canConfirm = order.status == MarketplaceOrderStatus.shipped;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(order.supplierName,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(order.status.label,
                    style: TextStyle(
                        color: statusColor,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...order.items.map((item) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${item.name} × ${item.quantity} ${item.unit}',
                        style: const TextStyle(fontSize: 13)),
                    Text('฿${baht.format(item.subtotal)}',
                        style: const TextStyle(fontSize: 13)),
                  ],
                ),
              )),
          const Divider(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(dt.format(order.createdAt),
                  style: TextStyle(
                      fontSize: 12,
                      color: cs.onSurface.withValues(alpha: 0.5))),
              Text('฿${baht.format(order.subtotal)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
            ],
          ),
          if (canCancel || canConfirm) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                if (canCancel)
                  OutlinedButton(
                    onPressed: () => _cancel(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                    ),
                    child:
                        const Text('ยกเลิก', style: TextStyle(fontSize: 13)),
                  ),
                if (canConfirm)
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () => _confirmDelivered(context),
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('รับของแล้ว',
                          style: TextStyle(fontSize: 13)),
                      style: FilledButton.styleFrom(
                        backgroundColor: Colors.green,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
