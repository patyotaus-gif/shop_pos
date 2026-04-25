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
  });

  bool get isLowStock => stock <= lowStockThreshold;
  double get profit => price - costPrice;
  double get profitMargin => price > 0 ? (profit / price) * 100 : 0;

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
      );
}
