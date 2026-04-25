import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/product.dart';

class ProductService {
  static final _col = FirebaseFirestore.instance.collection('products');

  static Stream<List<Product>> watchAll() => _col
      .orderBy('name')
      .snapshots()
      .map((s) => s.docs.map((d) => Product.fromFirestore(d.data(), d.id)).toList());

  static Stream<List<Product>> watchLowStock() => _col
      .snapshots()
      .map((s) => s.docs
          .map((d) => Product.fromFirestore(d.data(), d.id))
          .where((p) => p.isLowStock)
          .toList());

  static Future<Product?> getByBarcode(String barcode) async {
    final snap = await _col.where('barcode', isEqualTo: barcode).limit(1).get();
    if (snap.docs.isEmpty) return null;
    return Product.fromFirestore(snap.docs.first.data(), snap.docs.first.id);
  }

  static Future<String> add(Product product) async {
    final doc = await _col.add(product.toFirestore());
    return doc.id;
  }

  static Future<void> update(Product product) =>
      _col.doc(product.id).update(product.toFirestore());

  static Future<void> delete(String id) => _col.doc(id).delete();

  static Future<void> adjustStock(String id, int delta) =>
      _col.doc(id).update({'stock': FieldValue.increment(delta)});

  static const List<String> categories = [
    'ทั่วไป', 'เครื่องดื่ม', 'ขนม', 'ของใช้', 'อาหารสด', 'ยา', 'อื่นๆ'
  ];
}
