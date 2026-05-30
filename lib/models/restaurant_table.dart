import 'package:cloud_firestore/cloud_firestore.dart';

/// Status of a restaurant table. `occupied` means an open TableOrder is
/// currently linked via `currentOrderId`.
enum TableStatus { available, occupied, reserved }

extension TableStatusExt on TableStatus {
  String get label => switch (this) {
        TableStatus.available => 'ว่าง',
        TableStatus.occupied => 'มีลูกค้า',
        TableStatus.reserved => 'จอง',
      };
}

/// A dine-in table in a restaurant. Named `RestaurantTable` to avoid
/// clashing with Flutter's built-in `Table` widget.
class RestaurantTable {
  final String id;
  final String name;
  final int capacity;
  final String? section;
  final TableStatus status;
  final String? currentOrderId;
  final DateTime createdAt;

  const RestaurantTable({
    required this.id,
    required this.name,
    this.capacity = 4,
    this.section,
    this.status = TableStatus.available,
    this.currentOrderId,
    required this.createdAt,
  });

  factory RestaurantTable.fromFirestore(
          Map<String, dynamic> data, String id) =>
      RestaurantTable(
        id: id,
        name: data['name'] ?? '',
        capacity: (data['capacity'] ?? 4) as int,
        section: data['section'] as String?,
        status: TableStatus.values.firstWhere(
          (e) => e.name == (data['status'] ?? 'available'),
          orElse: () => TableStatus.available,
        ),
        currentOrderId: data['currentOrderId'] as String?,
        createdAt:
            (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'capacity': capacity,
        if (section != null) 'section': section,
        'status': status.name,
        if (currentOrderId != null) 'currentOrderId': currentOrderId,
        'createdAt': Timestamp.fromDate(createdAt),
      };

  RestaurantTable copyWith({
    String? name,
    int? capacity,
    String? section,
    TableStatus? status,
    String? currentOrderId,
    bool clearCurrentOrderId = false,
  }) =>
      RestaurantTable(
        id: id,
        name: name ?? this.name,
        capacity: capacity ?? this.capacity,
        section: section ?? this.section,
        status: status ?? this.status,
        currentOrderId:
            clearCurrentOrderId ? null : (currentOrderId ?? this.currentOrderId),
        createdAt: createdAt,
      );
}
