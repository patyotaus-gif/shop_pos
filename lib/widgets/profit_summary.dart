import 'package:flutter/material.dart';

/// Per-unit profit shown while the owner edits price and cost, so the margin
/// is visible without doing the math by hand.
class ProfitSummary extends StatelessWidget {
  const ProfitSummary(
      {super.key,
      required this.price,
      required this.cost,
      this.fromRecipe = false});

  final double? price;
  final double? cost;

  /// Cost comes from the recipe rather than the cost field.
  final bool fromRecipe;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final price = this.price, cost = this.cost;
    final String text;
    Color color = cs.onSurfaceVariant;
    if (price == null || price <= 0) {
      text = 'ใส่ราคาขายเพื่อดูกำไร';
    } else if (cost == null || cost <= 0) {
      text = fromRecipe
          ? 'เพิ่มวัตถุดิบในสูตรเพื่อดูต้นทุนและกำไร'
          : 'ใส่ราคาต้นทุนเพื่อดูกำไร';
    } else {
      final profit = ((price - cost) * 100).round() / 100;
      final percent = profit / price * 100;
      text = '${fromRecipe ? 'ต้นทุนตามสูตร' : 'ต้นทุน'} ฿${cost.toStringAsFixed(2)}'
          ' · กำไร ฿${profit.toStringAsFixed(2)}'
          ' (${percent.toStringAsFixed(1)}% ของราคาขาย)';
      color = profit < 0 ? cs.error : Colors.green.shade700;
    }
    return Container(
      key: const ValueKey('profit-summary'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(8)),
      child: Text(text,
          style: TextStyle(fontWeight: FontWeight.w600, color: color)),
    );
  }
}
