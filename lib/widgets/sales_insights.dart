import 'package:flutter/material.dart';
import '../models/sale.dart';

class ProductSalesTotal {
  ProductSalesTotal(this.name);
  final String name;
  int quantity = 0;
  double revenue = 0;
}

Map<String, ProductSalesTotal> productSalesTotals(
    List<Sale> sales, String? category) {
  final totals = <String, ProductSalesTotal>{};
  for (final sale in sales.where((s) => !s.isRefunded)) {
    for (final item in sale.items) {
      if (category != null && (item.category ?? 'ไม่ระบุหมวด') != category) {
        continue;
      }
      final total = totals.putIfAbsent(
          item.productId, () => ProductSalesTotal(item.productName));
      total.quantity += item.quantity;
      total.revenue += item.subtotal;
    }
  }
  return totals;
}

class SalesInsights extends StatefulWidget {
  const SalesInsights({super.key, required this.sales});
  final List<Sale> sales;
  @override
  State<SalesInsights> createState() => _SalesInsightsState();
}

class _SalesInsightsState extends State<SalesInsights> {
  String? _category;
  bool _byRevenue = false;
  @override
  Widget build(BuildContext context) {
    final active = widget.sales.where((s) => !s.isRefunded).toList();
    final categories = active
        .expand((s) => s.items)
        .map((i) => i.category ?? 'ไม่ระบุหมวด')
        .toSet()
        .toList()
      ..sort();
    final selected = categories.contains(_category) ? _category : null;
    final products = productSalesTotals(active, selected).values.toList()
      ..sort((a, b) => _byRevenue
          ? b.revenue.compareTo(a.revenue)
          : b.quantity.compareTo(a.quantity));
    return ListView(padding: const EdgeInsets.all(16), children: [
      const Text('ยอดขายตามช่องทาง',
          style: TextStyle(fontWeight: FontWeight.bold)),
      const Text('ยอดหลังส่วนลดและคืนเงิน ก่อนหักค่าธรรมเนียมแพลตฟอร์ม'),
      for (final channel in SalesChannel.values)
        if (active.any((s) => s.salesChannel == channel))
          ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(channel.label),
              subtitle: Text(
                  '${active.where((s) => s.salesChannel == channel).length} บิล'),
              trailing: Text(
                  '฿${active.where((s) => s.salesChannel == channel).fold(0.0, (sum, s) => sum + s.total).toStringAsFixed(2)}')),
      const Divider(),
      const Text('สินค้าขายดี', style: TextStyle(fontWeight: FontWeight.bold)),
      const Text('ยอดสินค้าก่อนส่วนลดท้ายบิล ไม่รวมบิลคืนเงิน'),
      DropdownButton<String>(
          isExpanded: true,
          value: selected ?? '',
          items: [
            const DropdownMenuItem(value: '', child: Text('ทุกหมวด')),
            for (final category in categories)
              DropdownMenuItem(value: category, child: Text(category)),
          ],
          onChanged: (value) =>
              setState(() => _category = value == '' ? null : value)),
      Wrap(spacing: 8, children: [
        ChoiceChip(
            label: const Text('จำนวนขาย'),
            selected: !_byRevenue,
            onSelected: (_) => setState(() => _byRevenue = false)),
        ChoiceChip(
            label: const Text('ยอดขาย'),
            selected: _byRevenue,
            onSelected: (_) => setState(() => _byRevenue = true)),
      ]),
      if (products.isEmpty)
        const Padding(
            padding: EdgeInsets.all(16),
            child: Text('ยังไม่มีรายการขายในช่วงนี้')),
      for (final product in products)
        ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(product.name),
            subtitle: Text('${product.quantity} หน่วย'),
            trailing: Text('฿${product.revenue.toStringAsFixed(2)}')),
    ]);
  }
}
