import 'package:cloud_firestore/cloud_firestore.dart';

/// A wholesale supplier on the Pokpok marketplace. Top-level collection
/// `suppliers/{supplierId}` — shared across all shops (not nested under a
/// shop) because the same supplier serves many shops in an area. Onboarded
/// white-glove by the founder during Stage 3; shops only read these.
class Supplier {
  final String id;
  final String name;

  /// Short category line shown on the browse card, e.g. "ผัก · ผลไม้".
  final String category;

  /// Area the supplier delivers to — matched against the shop's area so
  /// shops only see suppliers that can actually reach them.
  final String? area;

  /// Logo / cover image URL (optional).
  final String? imageUrl;

  /// Days the supplier delivers, e.g. "จ-ส" — free text for now.
  final String? deliveryDays;

  /// Minimum order value in baht before the supplier accepts an order.
  final double minOrder;

  /// Soft on/off switch — lets the founder pause a supplier without
  /// deleting their catalog.
  final bool active;

  final DateTime createdAt;

  const Supplier({
    required this.id,
    required this.name,
    this.category = '',
    this.area,
    this.imageUrl,
    this.deliveryDays,
    this.minOrder = 0,
    this.active = true,
    required this.createdAt,
  });

  factory Supplier.fromFirestore(Map<String, dynamic> data, String id) =>
      Supplier(
        id: id,
        name: data['name'] ?? '',
        category: data['category'] ?? '',
        area: data['area'] as String?,
        imageUrl: data['imageUrl'] as String?,
        deliveryDays: data['deliveryDays'] as String?,
        minOrder: (data['minOrder'] ?? 0).toDouble(),
        active: data['active'] ?? true,
        createdAt:
            (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'category': category,
        if (area != null) 'area': area,
        if (imageUrl != null) 'imageUrl': imageUrl,
        if (deliveryDays != null) 'deliveryDays': deliveryDays,
        'minOrder': minOrder,
        'active': active,
        'createdAt': Timestamp.fromDate(createdAt),
      };
}

/// One line in a supplier's catalog. Lives at
/// `suppliers/{supplierId}/products/{productId}`.
class SupplierProduct {
  final String id;
  final String name;

  /// Selling unit, e.g. "กก.", "ลัง", "แพ็ค".
  final String unit;
  final double price;

  /// Minimum order quantity for this item (in [unit]s).
  final int moq;

  /// In stock / available right now.
  final bool available;

  /// Product photo URL (optional). Uploaded by the supplier from the web
  /// portal to `suppliers/{supplierId}/products/{file}` in Storage.
  final String? imageUrl;

  const SupplierProduct({
    required this.id,
    required this.name,
    this.unit = 'ชิ้น',
    required this.price,
    this.moq = 1,
    this.available = true,
    this.imageUrl,
  });

  factory SupplierProduct.fromFirestore(
          Map<String, dynamic> data, String id) =>
      SupplierProduct(
        id: id,
        name: data['name'] ?? '',
        unit: data['unit'] ?? 'ชิ้น',
        price: (data['price'] ?? 0).toDouble(),
        moq: (data['moq'] ?? 1) as int,
        available: data['available'] ?? true,
        imageUrl: data['imageUrl'] as String?,
      );

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'unit': unit,
        'price': price,
        'moq': moq,
        'available': available,
        if (imageUrl != null) 'imageUrl': imageUrl,
      };
}
