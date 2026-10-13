import 'package:cloud_firestore/cloud_firestore.dart';

import 'ingredient.dart';
import '../utils/stock_quantity.dart';

class Product {
  final String id;
  final String name;
  final String barcode;
  final double price;
  final double costPrice;
  final num stock;
  final int stockRevision;
  final num lowStockThreshold;
  final String category;
  final String sku;
  final String unit;
  final String packUnit;
  final num unitsPerPack;
  final String supplierName;
  final String storageLocation;
  final String notes;
  final bool isWeighed;
  final bool trackLots;
  final List<Map<String, dynamic>> stockLots;
  num get saleable {
    try {
      return saleableStock(toFirestore());
    } on StateError {
      return 0;
    }
  }

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

  /// "count" (default) = the product's own stock counter blocks sales as
  /// always. "recipe" = ingredients deduct per [recipe] server-side on each
  /// sale; the product's stock counter is ignored.
  final String stockMode;

  /// Ingredients consumed per dish (recipe mode). costPrice is recomputed
  /// from this whenever the recipe or ingredient costs change.
  final List<RecipeLine> recipe;

  bool get isRecipeMode => stockMode == 'recipe';

  const Product({
    required this.id,
    required this.name,
    required this.barcode,
    required this.price,
    this.costPrice = 0,
    required this.stock,
    this.stockRevision = 0,
    this.lowStockThreshold = 5,
    this.category = 'ทั่วไป',
    this.sku = '',
    this.unit = 'ชิ้น',
    this.packUnit = 'แพ็ก',
    this.unitsPerPack = 1,
    this.supplierName = '',
    this.storageLocation = '',
    this.notes = '',
    this.isWeighed = false,
    this.trackLots = false,
    this.stockLots = const [],
    this.isPinned = false,
    this.imagePath,
    this.imageUrl,
    this.salePrice,
    this.saleUntil,
    this.modifierGroupIds = const [],
    this.stockMode = 'count',
    this.recipe = const [],
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

  /// Rounded percent off while a sale is active — for "ลด X%" badges.
  /// 0 when there is no active sale or the discount rounds below 1%.
  /// Keep in sync with promoInfo() in public/order/js/catalog.js — the web
  /// badge derives the same percent from price/originalPrice.
  int get discountPercent {
    if (!isOnSale) return 0;
    final pct = ((1 - salePrice! / price) * 100).round();
    return pct < 1 ? 0 : pct;
  }

  double get profit => effectivePrice - costPrice;
  double get profitMargin =>
      effectivePrice > 0 ? (profit / effectivePrice) * 100 : 0;

  factory Product.fromFirestore(Map<String, dynamic> data, String id) =>
      Product(
        id: id,
        name: data['name'] ?? '',
        barcode: data['barcode'] ?? '',
        price: (data['price'] ?? 0).toDouble(),
        costPrice: (data['costPrice'] ?? 0).toDouble(),
        stockRevision: (data['stockRevision'] as num? ?? 0).toInt(),
        stock: data['stock'] ?? 0,
        lowStockThreshold: data['lowStockThreshold'] ?? 5,
        category: data['category'] ?? 'ทั่วไป',
        sku: data['sku'] ?? '',
        unit: data['unit'] ?? 'ชิ้น',
        packUnit: data['packUnit'] ?? 'แพ็ก',
        unitsPerPack: data['unitsPerPack'] as num? ?? 1,
        supplierName: data['supplierName'] ?? '',
        storageLocation: data['storageLocation'] ?? '',
        notes: data['notes'] ?? '',
        isWeighed: data['isWeighed'] == true,
        trackLots: data['trackLots'] == true,
        stockLots: (data['stockLots'] as List? ?? [])
            .map((l) => Map<String, dynamic>.from(l as Map))
            .toList(),
        isPinned: data['isPinned'] ?? false,
        imagePath: data['imagePath'],
        imageUrl: data['imageUrl'],
        salePrice: (data['salePrice'] as num?)?.toDouble(),
        saleUntil: (data['saleUntil'] as Timestamp?)?.toDate(),
        modifierGroupIds:
            ((data['modifierGroupIds'] as List<dynamic>?) ?? const [])
                .map((e) => e.toString())
                .toList(),
        stockMode: data['stockMode'] == 'recipe' ? 'recipe' : 'count',
        recipe: ((data['recipe'] as List<dynamic>?) ?? const [])
            .map((e) => RecipeLine.fromMap(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'barcode': barcode,
        'price': price,
        'costPrice': costPrice,
        'stock': stock, 'stockRevision': stockRevision,
        'lowStockThreshold': lowStockThreshold,
        'category': category,
        'sku': sku,
        'unit': unit,
        'packUnit': packUnit,
        'unitsPerPack': unitsPerPack,
        'supplierName': supplierName,
        'storageLocation': storageLocation,
        'notes': notes,
        'isWeighed': isWeighed,
        'trackLots': trackLots,
        'stockLots': stockLots,
        'isPinned': isPinned,
        if (imagePath != null) 'imagePath': imagePath,
        if (imageUrl != null) 'imageUrl': imageUrl,
        // Always written (even when null) so clearing a sale via update()
        // removes the old value instead of leaving it behind.
        'salePrice': salePrice,
        'saleUntil': saleUntil != null ? Timestamp.fromDate(saleUntil!) : null,
        if (modifierGroupIds.isNotEmpty) 'modifierGroupIds': modifierGroupIds,
        'stockMode': stockMode,
        'recipe': recipe.map((e) => e.toMap()).toList(),
        // Derived index so cost recompute can query "products using
        // ingredient X" with array-contains.
        'recipeIngredientIds': recipe.map((e) => e.ingredientId).toList(),
      };

  Product copyWith({
    String? name,
    String? barcode,
    double? price,
    double? costPrice,
    num? stock,
    num? lowStockThreshold,
    String? category,
    String? sku,
    String? unit,
    String? packUnit,
    num? unitsPerPack,
    String? supplierName,
    String? storageLocation,
    String? notes,
    bool? isWeighed,
    bool? trackLots,
    List<Map<String, dynamic>>? stockLots,
    bool? isPinned,
    String? imagePath,
    String? imageUrl,
    double? salePrice,
    DateTime? saleUntil,
    List<String>? modifierGroupIds,
    String? stockMode,
    List<RecipeLine>? recipe,
  }) =>
      Product(
        id: id,
        name: name ?? this.name,
        barcode: barcode ?? this.barcode,
        price: price ?? this.price,
        costPrice: costPrice ?? this.costPrice,
        stock: stock ?? this.stock,
        stockRevision: stockRevision,
        lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
        category: category ?? this.category,
        sku: sku ?? this.sku,
        unit: unit ?? this.unit,
        packUnit: packUnit ?? this.packUnit,
        unitsPerPack: unitsPerPack ?? this.unitsPerPack,
        supplierName: supplierName ?? this.supplierName,
        storageLocation: storageLocation ?? this.storageLocation,
        notes: notes ?? this.notes,
        isWeighed: isWeighed ?? this.isWeighed,
        trackLots: trackLots ?? this.trackLots,
        stockLots: stockLots ?? this.stockLots,
        isPinned: isPinned ?? this.isPinned,
        imagePath: imagePath ?? this.imagePath,
        imageUrl: imageUrl ?? this.imageUrl,
        salePrice: salePrice ?? this.salePrice,
        saleUntil: saleUntil ?? this.saleUntil,
        modifierGroupIds: modifierGroupIds ?? this.modifierGroupIds,
        stockMode: stockMode ?? this.stockMode,
        recipe: recipe ?? this.recipe,
      );
}
