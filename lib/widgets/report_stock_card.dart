import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/product.dart';
import '../services/product_service.dart';
import '../utils/stock_quantity.dart';

class ReportStockCard extends StatefulWidget {
  const ReportStockCard(
      {super.key, this.watchProducts = ProductService.watchAll});

  final Stream<List<Product>> Function() watchProducts;

  @override
  State<ReportStockCard> createState() => _ReportStockCardState();
}

class _ReportStockCardState extends State<ReportStockCard> {
  Stream<List<Product>>? _products;

  @override
  Widget build(BuildContext context) {
    final products = _products;
    return Card(
      child: ExpansionTile(
        title: const Text('สินค้าคงเหลือปัจจุบัน'),
        subtitle: const Text('สต็อกขณะนี้ เฉพาะสินค้าที่นับสต็อกโดยตรง'),
        leading: const Icon(Icons.inventory_2_outlined),
        onExpansionChanged: (open) => setState(
          () => _products = open ? widget.watchProducts() : null,
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        children: [
          if (products != null)
            StreamBuilder<List<Product>>(
              stream: products,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const Text(
                      'โหลดสต็อกไม่สำเร็จ กรุณาปิดแล้วเปิดอีกครั้ง');
                }
                if (!snapshot.hasData) return const LinearProgressIndicator();
                final counted = snapshot.data!.where((p) => !p.isRecipeMode);
                if (counted.isEmpty) {
                  return const Text('ยังไม่มีสินค้าที่นับสต็อกโดยตรง');
                }
                final low = <(Product, num)>[];
                var out = 0;
                var invalid = 0;
                var missingCost = 0;
                var value = 0.0;
                for (final p in counted) {
                  if (p.stock > 0) {
                    if (p.costPrice > 0 && p.costPrice.isFinite) {
                      value += p.stock * p.costPrice;
                    } else {
                      missingCost++;
                    }
                  }
                  num available;
                  try {
                    available = saleableStock(p.toFirestore());
                  } on StateError {
                    invalid++;
                    continue;
                  }
                  if (available <= 0) out++;
                  if (available <= 0 || available <= p.lowStockThreshold) {
                    low.add((p, available));
                  }
                }
                // Quantities measured in different units cannot be ranked together.
                low.sort((a, b) {
                  final byStatus =
                      (a.$2 <= 0 ? 0 : 1).compareTo(b.$2 <= 0 ? 0 : 1);
                  return byStatus != 0
                      ? byStatus
                      : a.$1.name.compareTo(b.$1.name);
                });
                final money = NumberFormat('#,##0.00').format(value);
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                        'สินค้าหมด $out รายการ · ใกล้หมด ${low.length - out} รายการ'),
                    Text('มูลค่าสินค้าคงเหลือตามต้นทุนที่บันทึก ฿$money'),
                    if (missingCost > 0)
                      Text('ยังไม่รวม $missingCost รายการที่ไม่มีต้นทุนยืนยัน'),
                    if (invalid > 0)
                      Text('ข้อมูลล็อตต้องตรวจสอบ $invalid รายการ'),
                    if (low.isNotEmpty) ...[
                      const Divider(),
                      for (final item in low.take(5))
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                          title: Text(item.$1.name),
                          subtitle: Text(
                              'พร้อมขาย ${stockText(item.$2)} ${item.$1.unit}'),
                        ),
                      if (low.length > 5)
                        Text('แสดง 5 จาก ${low.length} รายการ'),
                    ],
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}
