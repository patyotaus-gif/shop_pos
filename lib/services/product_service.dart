import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/product.dart';
import 'auth_service.dart';
import 'staff_access_service.dart';
import 'shop_database.dart';
import 'inventory_service.dart';
import '../utils/stock_quantity.dart';

class ProductService {
  static CollectionReference<Map<String, dynamic>> _col() =>
      ShopDatabase.shop.collection('products');

  static Future<String?> currentShopId() async => AuthService.shopId;

  static Stream<List<Product>> watchAll() => AuthService.isStaff
      ? StaffAccessService.watchWorkspace().map((w) => (w['products'] as List)
          .map((p) => Product.fromFirestore(
              Map<String, dynamic>.from(p as Map), p['id'] as String))
          .toList())
      : _col().orderBy('name').snapshots().map((s) =>
          s.docs.map((d) => Product.fromFirestore(d.data(), d.id)).toList());

  static Stream<List<Product>> watchLowStock() =>
      _col().snapshots().map((s) => s.docs
          .map((d) => Product.fromFirestore(d.data(), d.id))
          .where((p) => p.isLowStock)
          .toList());

  static Future<Product?> getByBarcode(String barcode) async {
    if (AuthService.isStaff) {
      final products = await watchAll().first;
      for (final p in products) {
        if (p.barcode == barcode) return p;
      }
      return null;
    }
    final snap =
        await _col().where('barcode', isEqualTo: barcode).limit(1).get();
    if (snap.docs.isEmpty) return null;
    return Product.fromFirestore(snap.docs.first.data(), snap.docs.first.id);
  }

  static String newId() => _col().doc().id;
  static Future<String> add(Product product) => _save(product, creating: true);

  // Product details must not overwrite a promotion edited on another device.
  static Map<String, dynamic> detailsUpdate(Product product) =>
      product.toFirestore()
        ..remove('salePrice')
        ..remove('saleUntil')
        ..remove('stock')
        ..remove('stockRevision')
        ..remove('stockLots')
        ..remove('costPrice');

  static Future<void> update(Product product, {Product? original}) async {
    await _save(product, original: original);
  }

  static Future<String> _save(Product product,
      {bool creating = false, Product? original}) async {
    if (!product.price.isFinite ||
        product.price < 0 ||
        !product.costPrice.isFinite ||
        product.costPrice < 0 ||
        !validStockQuantity(product.lowStockThreshold,
            weight: product.isWeighed, zero: true)) {
      throw StateError('ตรวจราคา ต้นทุน และจำนวนแจ้งเตือนสต๊อก');
    }
    final ref = _col().doc(product.id.isEmpty ? newId() : product.id);
    final codes = ShopDatabase.shop.collection('productSkus');
    return ref.firestore.runTransaction((tx) async {
      final existing = await tx.get(ref);
      if (!creating && !existing.exists) throw StateError('ไม่พบสินค้า');
      if (creating && existing.exists) {
        if (existing.data()?['creationRequestId'] == ref.id) return ref.id;
        throw StateError('รหัสสินค้านี้มีอยู่แล้ว');
      }
      final previousSku = (existing.data()?['sku'] as String? ?? '').trim();
      final sku = (product.sku.trim().isEmpty
              ? (previousSku.isEmpty ? 'PK-${ref.id}' : previousSku)
              : product.sku)
          .trim()
          .toUpperCase();
      if (!RegExp(r'^[A-Z0-9_-]{1,64}$').hasMatch(sku)) {
        throw StateError(
            'SKU ใช้ตัวอักษรอังกฤษ ตัวเลข - หรือ _ ไม่เกิน 64 ตัว');
      }
      if (product.unit.trim().isEmpty ||
          !validStockQuantity(product.unitsPerPack,
              weight: product.isWeighed) ||
          product.unitsPerPack > 100000 ||
          product.packUnit.trim().isEmpty ||
          !validStockQuantity(product.stock,
              weight: product.isWeighed, zero: true)) {
        throw StateError('ตรวจหน่วย จำนวนต่อแพ็ก และจำนวนสต๊อก');
      }
      final codeRef = codes.doc(sku);
      final code = await tx.get(codeRef);
      if (code.exists && code.data()?['productId'] != ref.id) {
        throw StateError('SKU นี้ใช้กับสินค้าอื่นแล้ว');
      }
      final oldSku = existing.data()?['sku'] as String?;
      DocumentSnapshot<Map<String, dynamic>>? oldCode;
      if (oldSku != null && oldSku.isNotEmpty && oldSku != sku) {
        oldCode = await tx.get(codes.doc(oldSku));
      }
      final payload = creating ? product.toFirestore() : detailsUpdate(product);
      if (existing.exists) {
        final live = existing.data()!;
        final held = (await tx.get(ShopDatabase.shop
                    .collection('inventoryControl')
                    .doc('online')))
                .data()?['products'] as Map? ??
            {};
        final changedMode = (live['unit'] ?? 'ชิ้น') != product.unit.trim() ||
            (live['isWeighed'] == true) != product.isWeighed ||
            (live['stockMode'] ?? 'count') != product.stockMode;
        if (changedMode &&
            ((live['stock'] as num? ?? 0) != 0 ||
                (held[ref.id] as num? ?? 0) != 0)) {
          throw StateError(
              'ยังมีสต๊อกหรือออเดอร์จองอยู่ เปลี่ยนหน่วยหรือวิธีนับไม่ได้ กรุณาสร้างสินค้าใหม่');
        }
      }
      payload['sku'] = sku;
      payload['unit'] = product.unit.trim();
      payload['packUnit'] = product.packUnit.trim();
      if (product.isWeighed && product.isRecipeMode) {
        throw StateError('สินค้าชั่งใช้การนับสต๊อกตามน้ำหนัก');
      }
      if (product.trackLots && product.isRecipeMode) {
        throw StateError('ติดตามล็อตที่วัตถุดิบแทนสินค้าสูตร');
      }
      if (existing.exists &&
          existing.data()?['trackLots'] == true &&
          !product.trackLots &&
          (existing.data()?['stock'] as num? ?? 0) != 0) {
        throw StateError('ยังมีสต๊อกตามล็อต กรุณาจัดการล็อตก่อนปิดการติดตาม');
      }
      if (product.trackLots &&
          (creating || existing.data()?['trackLots'] != true)) {
        if (existing.exists && existing.data()?['stock'] != original?.stock) {
          throw StateError('สต๊อกเปลี่ยนแล้ว กรุณาเปิดสินค้าใหม่ก่อนกำหนดล็อต');
        }
        final stock =
            existing.exists ? existing.data()!['stock'] as num : product.stock;
        if (product.stockLots
                    .fold<num>(0, (n, l) => n + (l['quantity'] as num)) !=
                stock ||
            product.stockLots.any((l) => !validLot(l))) {
          throw StateError('ระบุล็อตและวันหมดอายุให้ครบตามจำนวนสต๊อก');
        }
        payload['stockLots'] = product.stockLots;
        stockLots({...product.toFirestore(), 'stock': stock});
      }
      if (!creating &&
          original != null &&
          product.costPrice != original.costPrice) {
        if ((existing.data()?['costPrice'] as num? ?? 0).toDouble() !=
            original.costPrice) {
          throw StateError(
              'ต้นทุนเปลี่ยนแล้ว กรุณาเปิดสินค้าใหม่ก่อนแก้ต้นทุน');
        }
        payload['costPrice'] = product.costPrice;
      }
      if (creating) {
        payload['creationRequestId'] = ref.id;
        tx.set(ref, payload);
        InventoryService.record(tx, ShopDatabase.shop, ref.id,
            id: 'opening',
            kind: 'opening',
            delta: product.stock,
            before: 0,
            unit: product.unit,
            reason: 'สต๊อกเริ่มต้น');
      } else {
        tx.update(ref, payload);
      }
      tx.set(codeRef, {'productId': ref.id});
      if (oldCode?.data()?['productId'] == ref.id) {
        tx.delete(oldCode!.reference);
      }
      return ref.id;
    });
  }

  static Future<void> setPromotion(Product product,
      {required double? salePrice, DateTime? saleUntil}) async {
    if (AuthService.isStaff) {
      throw StateError('เฉพาะเจ้าของร้านที่จัดการโปรโมชั่นได้');
    }
    final ref = _col().doc(product.id);
    await ref.firestore.runTransaction((tx) async {
      final snapshot = await tx.get(ref);
      if (!snapshot.exists) throw StateError('ไม่พบสินค้า กรุณาเปิดรายการใหม่');
      final current = Product.fromFirestore(snapshot.data()!, snapshot.id);
      if (salePrice != null) {
        if (current.price != product.price) {
          throw StateError('ราคาสินค้าเปลี่ยนแล้ว กรุณาเปิดโปรโมชั่นใหม่');
        }
        if (!salePrice.isFinite ||
            salePrice <= 0 ||
            salePrice >= current.price) {
          throw StateError('ราคาโปรต้องมากกว่า 0 และต่ำกว่าราคาขาย');
        }
        if (saleUntil != null && !saleUntil.isAfter(DateTime.now())) {
          throw StateError('กรุณาเลือกวันสิ้นสุดใหม่');
        }
      }
      tx.update(ref, {
        'salePrice': salePrice,
        'saleUntil': salePrice != null && saleUntil != null
            ? Timestamp.fromDate(saleUntil)
            : null,
      });
    });
  }

  static Future<void> setPinned(String id, bool pinned) async {
    if (AuthService.isStaff) {
      throw StateError('เฉพาะเจ้าของร้านที่จัดการสินค้าได้');
    }
    await _col().doc(id).update({'isPinned': pinned});
  }

  static Future<void> delete(String id) async {
    final ref = _col().doc(id);
    await ref.firestore.runTransaction((tx) async {
      final product = await tx.get(ref);
      final sku = product.data()?['sku'] as String?;
      final code = sku == null || sku.isEmpty
          ? null
          : await tx.get(ShopDatabase.shop.collection('productSkus').doc(sku));
      tx.delete(ref);
      if (code?.data()?['productId'] == id) tx.delete(code!.reference);
    });
  }

  static List<String> categoriesFor(Iterable<Product> products) => {
        for (final product in products)
          if (product.category.isNotEmpty && product.category != 'ทั้งหมด')
            product.category,
      }.toList()
        ..sort();
}
