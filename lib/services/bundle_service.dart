import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/product.dart';
import '../models/sale.dart';

class BundleService {
  static int discountMinor(List<Map<String, dynamic>> bundles) => bundles.fold(
      0, (value, b) => value + (b['discountMinor'] as num).toInt());

  static String fingerprint(List<Map<String, dynamic>> bundles) =>
      jsonEncode(bundles
          .map((b) => [
                b['id'],
                b['revision'],
                b['name'],
                b['sets'],
                b['priceMinor'],
                b['discountMinor'],
                (b['components'] as List)
                    .map((c) =>
                        [c['productId'], c['quantity'], c['unitPriceMinor']])
                    .toList()
              ])
          .toList());

  static Future<void> validate(Transaction tx,
      DocumentReference<Map<String, dynamic>> shop, Sale sale) async {
    final configs =
        (await tx.get(shop.collection('promotionSettings').doc('bundles')))
                .data()?['bundles'] as List? ??
            [];
    final counts = <String, num>{};
    for (final i in sale.items.where((i) => !i.isGift && i.modifiers.isEmpty)) {
      counts.update(i.productId, (n) => n + i.quantity,
          ifAbsent: () => i.quantity);
    }
    final current = <Map<String, dynamic>>[];
    final sorted = configs
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList()
      ..sort((a, b) => (a['id'] as String).compareTo(b['id'] as String));
    final seen = <String>{};
    for (final b in sorted) {
      if (b['active'] != true ||
          !(b['endsAt'] as Timestamp).toDate().isAfter(DateTime.now())) {
        continue;
      }
      final parts = b['components'] as List;
      var sets = b['maxSets'] as int;
      for (final c in parts) {
        if (!seen.add(c['productId'] as String)) {
          throw StateError('ชุดสินค้าซ้ำกัน กรุณาตรวจโปรโมชั่น');
        }
        final possible =
            (counts[c['productId']] ?? 0) ~/ (c['quantity'] as int);
        if (possible < sets) sets = possible;
      }
      if (sets == 0) continue;
      final components = <Map<String, dynamic>>[];
      var full = 0;
      for (final c in parts) {
        final data = (await tx
                .get(shop.collection('products').doc(c['productId'] as String)))
            .data();
        if (data == null) break;
        final p = Product.fromFirestore(data, c['productId'] as String);
        if (p.isWeighed ||
            p.modifierGroupIds.isNotEmpty ||
            (p.isRecipeMode && p.recipe.isEmpty)) {
          break;
        }
        final unit = (p.effectivePrice * 100).round();
        // A stale cart must not charge a different bundle price than previewed.
        if (sale.items
            .where(
                (i) => !i.isGift && i.productId == p.id && i.modifiers.isEmpty)
            .any((i) => (i.price * 100).round() != unit)) {
          throw StateError(
              'ราคาสินค้าในชุดเปลี่ยน กรุณาโหลดสินค้าใหม่ก่อนรับเงิน');
        }
        components.add({
          'productId': p.id,
          'quantity': c['quantity'],
          'unitPriceMinor': unit
        });
        full += unit * (c['quantity'] as int);
      }
      final saving = full - (b['priceMinor'] as int);
      if (components.length != parts.length || saving <= 0) continue;
      current.add({
        'id': b['id'],
        'revision': b['revision'],
        'name': b['name'],
        'sets': sets,
        'priceMinor': b['priceMinor'],
        'discountMinor': saving * sets,
        'components': components
      });
    }
    if (fingerprint(current) != fingerprint(sale.bundles) ||
        (sale.bundleDiscount * 100).round() != discountMinor(current) ||
        sale.discount + 0.001 < sale.bundleDiscount) {
      throw StateError(
          'ชุดสินค้าหรือราคาเปลี่ยน กรุณาตรวจโปรโมชั่นก่อนรับเงิน');
    }
    if (sale.bundles.isNotEmpty &&
        (sale.total * 100).round() !=
            sale.items.fold<int>(0, (s, i) => s + (i.subtotal * 100).round()) -
                (sale.discount * 100).round()) {
      throw StateError('ยอดชุดสินค้าไม่ตรงกับรายการขาย');
    }
  }
}
