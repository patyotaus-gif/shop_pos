import 'package:flutter/material.dart';

/// Loyalty customer on a table bill, read from the server-priced promotion.
class TableLoyaltyStrip extends StatelessWidget {
  const TableLoyaltyStrip({
    super.key,
    required this.loyalty,
    required this.enabled,
    required this.onAttach,
    required this.onRedeem,
    required this.onRemove,
  });

  final Map<String, dynamic>? loyalty;
  final bool enabled;
  final VoidCallback onAttach, onRedeem, onRemove;

  @override
  Widget build(BuildContext context) {
    final loyalty = this.loyalty;
    if (loyalty == null) {
      return TextButton.icon(
        key: const ValueKey('table-loyalty-attach'),
        onPressed: enabled ? onAttach : null,
        icon: const Icon(Icons.card_giftcard_outlined, size: 18),
        label: const Text('เพิ่มลูกค้าสะสมแต้ม'),
      );
    }
    final redeemed = (loyalty['redeemBaht'] as num? ?? 0).toInt();
    final points = (loyalty['pointsRedeemed'] as num? ?? 0).toInt();
    return Row(children: [
      const Icon(Icons.card_giftcard_outlined, size: 18),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
            '${loyalty['customerName'] ?? ''}'
            '${redeemed > 0 ? ' · ใช้ $points แต้ม -฿$redeemed' : ''}',
            style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
      TextButton(
        key: const ValueKey('table-loyalty-redeem'),
        onPressed: enabled ? onRedeem : null,
        child: Text(redeemed > 0 ? 'แก้แต้ม' : 'ใช้แต้ม'),
      ),
      IconButton(
        key: const ValueKey('table-loyalty-remove'),
        tooltip: 'เอาลูกค้าออก',
        onPressed: enabled ? onRemove : null,
        icon: const Icon(Icons.close, size: 18),
      ),
    ]);
  }
}
