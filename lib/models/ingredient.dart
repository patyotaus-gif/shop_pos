import 'package:cloud_firestore/cloud_firestore.dart';

/// A raw ingredient (วัตถุดิบ) tracked for recipe-mode products. Stock is a
/// double (0.25 กก.) and MAY go negative — selling never blocks on
/// ingredients; negative just signals "ไปนับใหม่".
class Ingredient {
  final String id;
  final String name;
  final String unit; // กรัม / มล. / ฟอง / ชิ้น ... (free text)
  final double stock;
  final double avgCost; // ต้นทุนเฉลี่ยถ่วงน้ำหนัก ต่อหน่วย
  final double lowStockThreshold;
  final DateTime createdAt;

  const Ingredient({
    required this.id,
    required this.name,
    required this.unit,
    this.stock = 0,
    this.avgCost = 0,
    this.lowStockThreshold = 0,
    required this.createdAt,
  });

  bool get isLow => lowStockThreshold > 0 && stock <= lowStockThreshold;
  bool get isNegative => stock < 0;

  factory Ingredient.fromFirestore(Map<String, dynamic> data, String id) =>
      Ingredient(
        id: id,
        name: data['name'] ?? '',
        unit: data['unit'] ?? '',
        stock: (data['stock'] ?? 0).toDouble(),
        avgCost: (data['avgCost'] ?? 0).toDouble(),
        lowStockThreshold: (data['lowStockThreshold'] ?? 0).toDouble(),
        createdAt:
            (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'unit': unit,
        'stock': stock,
        'avgCost': avgCost,
        'lowStockThreshold': lowStockThreshold,
        'createdAt': Timestamp.fromDate(createdAt),
      };
}

/// One line of a product's recipe: `qty` of an ingredient per dish.
class RecipeLine {
  final String ingredientId;
  final double qty;

  const RecipeLine({required this.ingredientId, required this.qty});

  factory RecipeLine.fromMap(Map<String, dynamic> m) => RecipeLine(
        ingredientId: m['ingredientId'] ?? '',
        qty: (m['qty'] ?? 0).toDouble(),
      );

  Map<String, dynamic> toMap() => {'ingredientId': ingredientId, 'qty': qty};
}
