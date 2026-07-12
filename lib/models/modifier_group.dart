import 'package:cloud_firestore/cloud_firestore.dart';

import 'ingredient.dart';

/// One option inside a ModifierGroup — e.g. "เผ็ดน้อย" / "เพิ่มไข่ดาว +10฿".
/// `priceAdjust` is added to the parent item's unit price; can be 0,
/// positive, or negative. `ingredientUsage` (optional) lists ingredients the
/// option consumes — deducted server-side per sale, e.g. ไข่ดาว = ไข่ 1 ฟอง.
class ModifierOption {
  final String id;
  final String name;
  final double priceAdjust;
  final List<RecipeLine> ingredientUsage;

  const ModifierOption({
    required this.id,
    required this.name,
    this.priceAdjust = 0,
    this.ingredientUsage = const [],
  });

  factory ModifierOption.fromMap(Map<String, dynamic> m) => ModifierOption(
        id: m['id'] ?? '',
        name: m['name'] ?? '',
        priceAdjust: (m['priceAdjust'] ?? 0).toDouble(),
        ingredientUsage: ((m['ingredientUsage'] as List<dynamic>?) ?? const [])
            .map((e) => RecipeLine.fromMap(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'priceAdjust': priceAdjust,
        if (ingredientUsage.isNotEmpty)
          'ingredientUsage': ingredientUsage.map((e) => e.toMap()).toList(),
      };

  ModifierOption copyWith({
    String? name,
    double? priceAdjust,
    List<RecipeLine>? ingredientUsage,
  }) =>
      ModifierOption(
        id: id,
        name: name ?? this.name,
        priceAdjust: priceAdjust ?? this.priceAdjust,
        ingredientUsage: ingredientUsage ?? this.ingredientUsage,
      );
}

/// A group of options that can be attached to products.
///
/// - `required`: customer must pick at least 1 before adding to cart
/// - `multiSelect`: false → radio (pick 1), true → checkboxes (pick many)
///
/// Kept the schema flat (no min/max) on purpose — covers the 95% case
/// (size = radio, add-ons = checkbox) without dragging in a full
/// constraint picker. Can be promoted to min/max later if needed.
class ModifierGroup {
  final String id;
  final String name;
  final bool required;
  final bool multiSelect;
  final List<ModifierOption> options;
  final DateTime createdAt;

  const ModifierGroup({
    required this.id,
    required this.name,
    this.required = false,
    this.multiSelect = false,
    this.options = const [],
    required this.createdAt,
  });

  factory ModifierGroup.fromFirestore(
          Map<String, dynamic> data, String id) =>
      ModifierGroup(
        id: id,
        name: data['name'] ?? '',
        required: data['required'] ?? false,
        multiSelect: data['multiSelect'] ?? false,
        options: (data['options'] as List<dynamic>? ?? [])
            .map((e) => ModifierOption.fromMap(e as Map<String, dynamic>))
            .toList(),
        createdAt:
            (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'required': required,
        'multiSelect': multiSelect,
        'options': options.map((e) => e.toMap()).toList(),
        'createdAt': Timestamp.fromDate(createdAt),
      };

  ModifierGroup copyWith({
    String? name,
    bool? required,
    bool? multiSelect,
    List<ModifierOption>? options,
  }) =>
      ModifierGroup(
        id: id,
        name: name ?? this.name,
        required: required ?? this.required,
        multiSelect: multiSelect ?? this.multiSelect,
        options: options ?? this.options,
        createdAt: createdAt,
      );
}
