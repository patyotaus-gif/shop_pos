import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/product.dart';
import '../models/sale.dart';
import '../services/product_service.dart';
import '../services/sale_service.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  static final _baht = NumberFormat('#,##0.00', 'th_TH');

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ภาพรวม'),
        centerTitle: true,
      ),
      body: RefreshIndicator(
        onRefresh: () async {},
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            // Today summary
            StreamBuilder<List<Sale>>(
              stream: SaleService.watchByRange(startOfDay, now),
              builder: (ctx, snap) {
                final sales = snap.data ?? [];
                final revenue = sales.fold<double>(0, (s, e) => s + e.total);
                final cashRevenue = sales.where((s) => !s.isDebt).fold<double>(0, (s, e) => s + e.total);
                final debtRevenue = sales.where((s) => s.isDebt).fold<double>(0, (s, e) => s + e.total);

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('วันนี้', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _BigCard(
                          label: 'รายได้รวม',
                          value: '฿${_baht.format(revenue)}',
                          icon: Icons.attach_money,
                          color: Colors.green,
                        ),
                        const SizedBox(width: 8),
                        _BigCard(
                          label: 'จำนวนบิล',
                          value: '${sales.length} บิล',
                          icon: Icons.receipt_long,
                          color: cs.primary,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        _BigCard(
                          label: 'เงินสด',
                          value: '฿${_baht.format(cashRevenue)}',
                          icon: Icons.payments_outlined,
                          color: Colors.teal,
                        ),
                        const SizedBox(width: 8),
                        _BigCard(
                          label: 'ยอดเชื่อ',
                          value: '฿${_baht.format(debtRevenue)}',
                          icon: Icons.person_outline,
                          color: Colors.orange,
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),

            // Low stock
            StreamBuilder<List<Product>>(
              stream: ProductService.watchLowStock(),
              builder: (ctx, snap) {
                final products = snap.data ?? [];
                if (products.isEmpty) return const SizedBox.shrink();
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.warning_amber, color: Colors.orange, size: 18),
                        const SizedBox(width: 4),
                        Text('สินค้าใกล้หมด (${products.length} รายการ)',
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...products.map((p) => Card(
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          child: ListTile(
                            dense: true,
                            leading: const CircleAvatar(
                              backgroundColor: Colors.red,
                              radius: 16,
                              child: Icon(Icons.inventory_2_outlined, color: Colors.white, size: 16),
                            ),
                            title: Text(p.name),
                            trailing: Text(
                              'เหลือ ${p.stock}',
                              style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                            ),
                          ),
                        )),
                    const SizedBox(height: 16),
                  ],
                );
              },
            ),

            // Top selling today
            StreamBuilder<List<Sale>>(
              stream: SaleService.watchByRange(startOfDay, now),
              builder: (ctx, snap) {
                final sales = snap.data ?? [];
                if (sales.isEmpty) return const SizedBox.shrink();

                // Aggregate items
                final Map<String, _TopItem> topMap = {};
                for (final sale in sales) {
                  for (final item in sale.items) {
                    topMap.update(
                      item.productId,
                      (existing) => _TopItem(
                        name: item.productName,
                        qty: existing.qty + item.quantity,
                        revenue: existing.revenue + item.subtotal,
                      ),
                      ifAbsent: () => _TopItem(
                        name: item.productName,
                        qty: item.quantity,
                        revenue: item.subtotal,
                      ),
                    );
                  }
                }

                final topItems = topMap.values.toList()
                  ..sort((a, b) => b.qty.compareTo(a.qty));
                final top5 = topItems.take(5).toList();

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('สินค้าขายดีวันนี้',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    ...top5.asMap().entries.map((e) => Card(
                          margin: const EdgeInsets.symmetric(vertical: 3),
                          child: ListTile(
                            dense: true,
                            leading: CircleAvatar(
                              backgroundColor: cs.primaryContainer,
                              radius: 16,
                              child: Text('${e.key + 1}',
                                  style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: cs.onPrimaryContainer,
                                      fontSize: 12)),
                            ),
                            title: Text(e.value.name),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('${e.value.qty} ชิ้น',
                                    style: const TextStyle(fontWeight: FontWeight.bold)),
                                Text('฿${_baht.format(e.value.revenue)}',
                                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
                              ],
                            ),
                          ),
                        )),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _TopItem {
  final String name;
  final int qty;
  final double revenue;
  const _TopItem({required this.name, required this.qty, required this.revenue});
}

class _BigCard extends StatelessWidget {
  final String label, value;
  final IconData icon;
  final Color color;

  const _BigCard({required this.label, required this.value, required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value,
                      style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 14),
                      overflow: TextOverflow.ellipsis),
                  Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
