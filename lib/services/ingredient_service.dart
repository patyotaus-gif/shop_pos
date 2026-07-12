import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/ingredient.dart';
import 'auth_service.dart';

/// Ingredient CRUD + receiving goods (weighted-average cost) + adjustments.
/// Auto-DEDUCTION is server-side (onSaleDeductIngredients trigger) — this
/// service only covers what the owner does by hand in the app.
class IngredientService {
  static CollectionReference<Map<String, dynamic>> _col() =>
      FirebaseFirestore.instance
          .collection('shops')
          .doc(AuthService.shopId)
          .collection('ingredients');

  static CollectionReference<Map<String, dynamic>> _purchases() =>
      FirebaseFirestore.instance
          .collection('shops')
          .doc(AuthService.shopId)
          .collection('ingredientPurchases');

  static CollectionReference<Map<String, dynamic>> _products() =>
      FirebaseFirestore.instance
          .collection('shops')
          .doc(AuthService.shopId)
          .collection('products');

  static Stream<List<Ingredient>> watchAll() => _col()
      .orderBy('name')
      .snapshots()
      .map((s) => s.docs
          .map((d) => Ingredient.fromFirestore(d.data(), d.id))
          .toList());

  static Future<List<Ingredient>> getAll() async {
    final s = await _col().orderBy('name').get();
    return s.docs
        .map((d) => Ingredient.fromFirestore(d.data(), d.id))
        .toList();
  }

  static Future<void> add(Ingredient ing) async {
    await _col().add(ing.toFirestore());
  }

  static Future<void> update(Ingredient ing) async {
    await _col().doc(ing.id).update({
      'name': ing.name,
      'unit': ing.unit,
      'lowStockThreshold': ing.lowStockThreshold,
    });
  }

  static Future<void> delete(String id) => _col().doc(id).delete();

  /// รับของเข้า: weighted-average cost. Mirrors functions/inventory.js
  /// applyPurchase — negative/zero starting stock is treated as zero for
  /// costing so a bad count can't poison the average.
  static Future<void> receiveStock(
    Ingredient ing, {
    required double qty,
    required double totalPrice,
  }) async {
    final base = ing.stock > 0 ? ing.stock : 0.0;
    final value = base * ing.avgCost + totalPrice;
    final denom = base + qty;
    final newAvg = denom > 0 ? value / denom : 0.0;

    final batch = FirebaseFirestore.instance.batch();
    batch.update(_col().doc(ing.id), {
      'stock': FieldValue.increment(qty),
      'avgCost': newAvg,
    });
    batch.set(_purchases().doc(), {
      'ingredientId': ing.id,
      'ingredientName': ing.name,
      'qty': qty,
      'totalPrice': totalPrice,
      'type': 'purchase',
      'at': FieldValue.serverTimestamp(),
    });
    await batch.commit();
    await _recomputeCostsFor(ing.id, newAvg);
  }

  /// ปรับสต็อก (นับใหม่/ของเสีย): sets the absolute count, avgCost
  /// unchanged, logged as an adjustment.
  static Future<void> adjustStock(
    Ingredient ing, {
    required double newStock,
    String note = '',
  }) async {
    final batch = FirebaseFirestore.instance.batch();
    batch.update(_col().doc(ing.id), {'stock': newStock});
    batch.set(_purchases().doc(), {
      'ingredientId': ing.id,
      'ingredientName': ing.name,
      'qty': newStock - ing.stock,
      'totalPrice': 0,
      'type': 'adjust',
      if (note.isNotEmpty) 'note': note,
      'at': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  /// After a cost change, refresh costPrice on every recipe-mode product
  /// using this ingredient (recipeIngredientIds enables the query). Reads
  /// each product's full recipe and re-sums against current avg costs.
  static Future<void> _recomputeCostsFor(
      String ingredientId, double newAvg) async {
    final affected = await _products()
        .where('recipeIngredientIds', arrayContains: ingredientId)
        .get();
    if (affected.docs.isEmpty) return;

    // Current avg cost of every ingredient (recipes reference several).
    final all = await getAll();
    final costById = {for (final i in all) i.id: i.avgCost};
    costById[ingredientId] = newAvg; // batch above may not be visible yet

    final batch = FirebaseFirestore.instance.batch();
    for (final doc in affected.docs) {
      final recipe = ((doc.data()['recipe'] as List<dynamic>?) ?? const [])
          .map((e) => RecipeLine.fromMap(e as Map<String, dynamic>));
      double cost = 0;
      for (final line in recipe) {
        cost += (costById[line.ingredientId] ?? 0) * line.qty;
      }
      batch.update(doc.reference, {'costPrice': cost});
    }
    await batch.commit();
  }
}
