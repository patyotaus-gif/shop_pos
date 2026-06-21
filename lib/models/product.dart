import 'package:cloud_firestore/cloud_firestore.dart';

class Product {
  final String id;
  final String name;
  final String barcode;
  final double price;
  final double costPrice;
  final int stock;
  final int lowStockThreshold;
  final String category;
  final bool isPinned;
  final String? imagePath;
  final String? imageUrl;

  /// Optional promotional price. Active only when it's set, below [price], and
  /// not past [saleUntil] (null = no expiry). See [effectivePrice]/[isOnSale].
  final double? salePrice;
  final DateTime? saleUntil;

  /// Restaurant-only: ids of [ModifierGroup]s offered when this product is
  /// added to an order. Empty for retail products. The picker resolves
  /// these ids to full ModifierGroup docs at order time.
  final List<String> modifierGroupIds;

  const Product({
    required this.id,
    required this.name,
    required this.barcode,
    required this.price,
    this.costPrice = 0,
    required this.stock,
    this.lowStockThreshold = 5,
    this.category = 'ทั่วไป',
    this.isPinned = false,
    this.imagePath,
    this.imageUrl,
    this.salePrice,
    this.saleUntil,
    this.modifierGroupIds = const [],
  });

  bool get isLowStock => stock <= lowStockThreshold;

  /// True when a valid, unexpired sale price below the normal price is set.
  bool get isOnSale {
    final sp = salePrice;
    if (sp == null || sp <= 0 || sp >= price) return false;
    final until = saleUntil;
    return until == null || until.isAfter(DateTime.now());
  }

  /// Price to actually charge — the sale price while a sale is active,
  /// otherwise the normal price.
  double get effectivePrice => isOnSale ? salePrice! : price;

  double get profit => effectivePrice - costPrice;
  double get profitMargin =>
      effectivePrice > 0 ? (profit / effectivePrice) * 100 : 0;

  factory Product.fromFirestore(Map<String, dynamic> data, String id) => Product(
        id: id,
        name: data['name'] ?? '',
        barcode: data['barcode'] ?? '',
        price: (data['price'] ?? 0).toDouble(),
        costPrice: (data['costPrice'] ?? 0).toDouble(),
        stock: data['stock'] ?? 0,
        lowStockThreshold: data['lowStockThreshold'] ?? 5,
        category: data['category'] ?? 'ทั่วไป',
        isPinned: data['isPinned'] ?? false,
        imagePath: data['imagePath'],
        imageUrl: data['imageUrl'],
        salePrice: (data['salePrice'] as num?)?.toDouble(),
        saleUntil: (data['saleUntil'] as Timestamp?)?.toDate(),
        modifierGroupIds: ((data['modifierGroupIds'] as List<dynamic>?) ?? const [])
            .map((e) => e.toString())
            .toList(),
      );

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'barcode': barcode,
        'price': price,
        'costPrice': costPrice,
        'stock': stock,
        'lowStockThreshold': lowStockThreshold,
        'category': category,
        'isPinned': isPinned,
        if (imagePath != null) 'imagePath': imagePath,
        if (imageUrl != null) 'imageUrl': imageUrl,
        // Always written (even when null) so clearing a sale via update()
        // removes the old value instead of leaving it behind.
        'salePrice': salePrice,
        'saleUntil': saleUntil != null ? Timestamp.fromDate(saleUntil!) : null,
        if (modifierGroupIds.isNotEmpty) 'modifierGroupIds': modifierGroupIds,
      };

  Product copyWith({
    String? name,
    String? barcode,
    double? price,
    double? costPrice,
    int? stock,
    int? lowStockThreshold,
    String? category,
    bool? isPinned,
    String? imagePath,
    String? imageUrl,
    double? salePrice,
    DateTime? saleUntil,
    List<String>? modifierGroupIds,
  }) =>
      Product(
        id: id,
        name: name ?? this.name,
        barcode: barcode ?? this.barcode,
        price: price ?? this.price,
        costPrice: costPrice ?? this.costPrice,
        stock: stock ?? this.stock,
        lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
        category: category ?? this.category,
        isPinned: isPinned ?? this.isPinned,
        imagePath: imagePath ?? this.imagePath,
        imageUrl: imageUrl ?? this.imageUrl,
        salePrice: salePrice ?? this.salePrice,
        saleUntil: saleUntil ?? this.saleUntil,
        modifierGroupIds: modifierGroupIds ?? this.modifierGroupIds,
      );
}
