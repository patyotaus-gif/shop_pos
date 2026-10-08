import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/sale.dart';

/// Consume recipes with the sale, protecting web reservations from parallel POS sales.
class IngredientCheckout {
  static Future<Map<String, double>> read(
      Transaction tx,
      DocumentReference<Map<String, dynamic>> shop,
      List<SaleItem> items,
      Map reserved) async {
    final usage = <String, double>{};
    void add(dynamic raw, num quantity) {
      for (final line in (raw as List?) ?? []) {
        final id = line['ingredientId'] as String?;
        final qty = (line['qty'] as num? ?? 0).toDouble() * quantity;
        if (id != null && id.isNotEmpty && qty > 0) {
          usage.update(id, (v) => v + qty, ifAbsent: () => qty);
        }
      }
    }

    final products = <String, Map<String, dynamic>>{};
    final groups = <String, Map<String, dynamic>>{};
    for (final i in items) {
      products[i.productId] ??=
          (await tx.get(shop.collection('products').doc(i.productId))).data() ??
              {};
      if (products[i.productId]!['stockMode'] == 'recipe') {
        add(products[i.productId]!['recipe'], i.quantity);
      }
      for (final m in i.modifiers) {
        groups[m.groupId] ??=
            (await tx.get(shop.collection('modifierGroups').doc(m.groupId)))
                    .data() ??
                {};
        for (final option in (groups[m.groupId]!['options'] as List?) ?? []) {
          if (option['id'] == m.optionId) {
            add(option['ingredientUsage'], i.quantity);
          }
        }
      }
    }
    final live = <String, double>{};
    for (final entry in usage.entries) {
      final ingredient =
          (await tx.get(shop.collection('ingredients').doc(entry.key))).data();
      final held = (reserved[entry.key] as num? ?? 0).toDouble();
      if (held > 0 &&
          ((ingredient?['stock'] as num? ?? 0) - entry.value + 1e-9) < held) {
        throw StateError(
            'วัตถุดิบถูกจองโดยออเดอร์ออนไลน์ กรุณาตรวจสอบก่อนรับเงิน');
      }
      if (ingredient != null) live[entry.key] = entry.value;
    }
    return live;
  }

  static void write(Transaction tx,
      DocumentReference<Map<String, dynamic>> shop, Map<String, double> usage) {
    for (final entry in usage.entries) {
      tx.update(shop.collection('ingredients').doc(entry.key),
          {'stock': FieldValue.increment(-entry.value)});
    }
  }
}
