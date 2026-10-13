import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/product.dart';
import 'shop_database.dart';
import '../utils/stock_quantity.dart';

class InventoryService {
  static void record(Transaction tx,
      DocumentReference<Map<String, dynamic>> shop, String productId,
      {required String id,
      required String kind,
      required num delta,
      required num before,
      String unit = 'ชิ้น',
      String reason = '',
      String? referenceId,
      Map<String, dynamic> extra = const {}}) {
    tx.set(
        shop
            .collection('products')
            .doc(productId)
            .collection('stockMovements')
            .doc(id),
        {
          'kind': kind,
          'delta': delta,
          'before': before,
          'after': stockRound(before + delta),
          'unit': unit,
          'reason': reason,
          'referenceId': referenceId,
          'actor': shop.id,
          'createdAt': FieldValue.serverTimestamp(),
          ...extra,
        });
  }

  static Stream<List<Map<String, dynamic>>> history(String productId) =>
      ShopDatabase.shop
          .collection('products')
          .doc(productId)
          .collection('stockMovements')
          .orderBy('createdAt', descending: true)
          .limit(100)
          .snapshots()
          .map((s) => s.docs.map((d) => {'id': d.id, ...d.data()}).toList());

  static Stream<Product?> watchProduct(String id) => ShopDatabase.shop
      .collection('products')
      .doc(id)
      .snapshots()
      .map((s) => s.exists ? Product.fromFirestore(s.data()!, s.id) : null);

  static Stream<num> watchReserved(String id) => ShopDatabase.shop
      .collection('inventoryControl')
      .doc('online')
      .snapshots()
      .map((s) => (s.data()?['products'] as Map?)?[id] as num? ?? 0);

  /// Request id and payload are retained by the editor until confirmed.
  static Future<void> change(
      {required String productId,
      required String requestId,
      required String kind,
      required num quantity,
      required String reason,
      num? expectedStock,
      int? expectedRevision,
      double? totalCost,
      num packSize = 1,
      String documentNumber = '',
      String? lotId,
      String? lotNumber,
      String? expiresOn}) async {
    if (!['receive', 'count', 'waste'].contains(kind) ||
        quantity < 0 ||
        (kind != 'count' && quantity == 0) ||
        quantity > 100000000 ||
        !validStockQuantity(packSize, weight: true) ||
        packSize > 100000 ||
        (kind != 'receive' && packSize != 1) ||
        reason.trim().isEmpty ||
        reason.trim().length > 300 ||
        requestId.isEmpty ||
        requestId.contains('/') ||
        (totalCost != null &&
            (!totalCost.isFinite || totalCost < 0 || totalCost > 1e9))) {
      throw StateError('ตรวจจำนวน ต้นทุน และเหตุผลให้ถูกต้อง');
    }
    final shop = ShopDatabase.shop;
    final ref = shop.collection('products').doc(productId);
    final movement = ref.collection('stockMovements').doc('manual-$requestId');
    final request = {
      'kind': kind,
      'quantity': quantity,
      'reason': reason.trim(),
      'expectedStock': expectedStock,
      'expectedRevision': expectedRevision,
      'totalCost': totalCost,
      'packSize': packSize,
      'documentNumber': documentNumber.trim(),
      'lotId': lotId,
      'lotNumber': lotNumber,
      'expiresOn': expiresOn
    };
    await shop.firestore.runTransaction((tx) async {
      final prior = await tx.get(movement);
      if (prior.exists) {
        final old = prior.data()!['request'] as Map?;
        if (old == null || request.entries.any((e) => old[e.key] != e.value)) {
          throw StateError('รหัสรายการซ้ำกับข้อมูลอื่น กรุณาตรวจประวัติสต๊อก');
        }
        return;
      }
      final snap = await tx.get(ref);
      if (!snap.exists) throw StateError('ไม่พบสินค้า');
      final p = Product.fromFirestore(snap.data()!, snap.id);
      if (!validStockQuantity(quantity,
          weight: p.isWeighed && packSize == 1, zero: kind == 'count')) {
        throw StateError(
            'จำนวนไม่ถูกต้อง สินค้าชั่งใช้ทศนิยมได้สูงสุด 3 ตำแหน่ง');
      }
      if (p.isRecipeMode) {
        throw StateError(
            'สินค้านี้ตัดตามสูตร ให้รับเข้าและปรับยอดที่หน้าวัตถุดิบ');
      }
      if (packSize != 1 && packSize != p.unitsPerPack) {
        throw StateError('จำนวนต่อแพ็กเปลี่ยนแล้ว กรุณาเปิดรายการใหม่');
      }
      if (kind == 'count' &&
          (expectedStock != p.stock || expectedRevision != p.stockRevision)) {
        throw StateError(
            'สต๊อกเปลี่ยนระหว่างตรวจนับ กรุณาตรวจยอดล่าสุดและนับใหม่');
      }
      final lots =
          p.trackLots ? stockLots(p.toFirestore()) : <Map<String, dynamic>>[];
      Map<String, dynamic>? lot;
      if (p.trackLots) {
        if (kind == 'receive') {
          lots.removeWhere((row) => row['quantity'] == 0);
          lot = {
            'id': requestId,
            'number': lotNumber?.trim(),
            'expiresOn': expiresOn,
            'quantity': 0
          };
          if (!validLot(lot) || lots.length >= 200) {
            throw StateError(
                'ระบุเลขล็อตและวันหมดอายุให้ถูกต้อง (สูงสุด 200 ล็อตที่มีสต๊อกต่อสินค้า)');
          }
          lots.add(lot);
        } else {
          for (final row in lots) {
            if (row['id'] == lotId) lot = row;
          }
          if (lot == null) {
            throw StateError('เลือกล็อตที่จะตรวจนับหรือลงของเสีย');
          }
        }
      }
      final base = lot?['quantity'] as num? ?? p.stock;
      final delta = stockRound(kind == 'count'
          ? quantity - base
          : (kind == 'waste' ? -quantity : quantity * packSize));
      final after = stockRound(p.stock + delta);
      if (lot != null) {
        lot['quantity'] = stockRound(base + delta);
        if ((lot['quantity'] as num) < 0) throw StateError('จำนวนในล็อตไม่พอ');
      }
      final control =
          await tx.get(shop.collection('inventoryControl').doc('online'));
      final held =
          (control.data()?['products'] as Map?)?[productId] as num? ?? 0;
      final saleableAfter = saleableStock(
          {...p.toFirestore(), 'stock': after, 'stockLots': lots});
      if (after < 0 || (delta < 0 && saleableAfter + 1e-9 < held)) {
        throw StateError(
            'ลดสต๊อกไม่ได้: มีสินค้าจองออนไลน์ $held ${p.unit} กรุณาตรวจออเดอร์ก่อน');
      }
      if (after > 100000000) throw StateError('จำนวนคงเหลือเกินขอบเขต');
      final updates = <String, dynamic>{
        'stock': after,
        'stockRevision': p.stockRevision + 1
      };
      if (p.trackLots) updates['stockLots'] = lots;
      if (kind == 'receive' && totalCost != null) {
        final base = p.stock > 0 ? p.stock : 0;
        updates['costPrice'] =
            (base * p.costPrice + totalCost) / (base + delta);
      }
      tx.update(ref, updates);
      record(tx, shop, productId,
          id: movement.id,
          kind: kind,
          delta: delta,
          before: p.stock,
          unit: p.unit,
          reason: reason.trim(),
          extra: {
            'request': request,
            'totalCost': totalCost,
            'costBefore': p.costPrice,
            'costAfter': updates['costPrice'] ?? p.costPrice,
            'documentNumber': documentNumber.trim(),
            if (lot != null) 'lot': Map<String, dynamic>.from(lot),
          });
    });
  }
}
