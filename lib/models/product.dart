class Product {
  final String id;
  final String name;
  final String barcode;
  final double price;
  final int stock;
  final int lowStockThreshold;
  final String category;

  const Product({
    required this.id,
    required this.name,
    required this.barcode,
    required this.price,
    required this.stock,
    this.lowStockThreshold = 5,
    this.category = 'ทั่วไป',
  });

  bool get isLowStock => stock <= lowStockThreshold;

  factory Product.fromFirestore(Map<String, dynamic> data, String id) => Product(
        id: id,
        name: data['name'] ?? '',
        barcode: data['barcode'] ?? '',
        price: (data['price'] ?? 0).toDouble(),
        stock: data['stock'] ?? 0,
        lowStockThreshold: data['lowStockThreshold'] ?? 5,
        category: data['category'] ?? 'ทั่วไป',
      );

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'barcode': barcode,
        'price': price,
        'stock': stock,
        'lowStockThreshold': lowStockThreshold,
        'category': category,
      };

  Product copyWith({
    String? name,
    String? barcode,
    double? price,
    int? stock,
    int? lowStockThreshold,
    String? category,
  }) =>
      Product(
        id: id,
        name: name ?? this.name,
        barcode: barcode ?? this.barcode,
        price: price ?? this.price,
        stock: stock ?? this.stock,
        lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
        category: category ?? this.category,
      );
}
