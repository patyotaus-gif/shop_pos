import 'package:cloud_firestore/cloud_firestore.dart';

import 'order_modifier.dart';

/// Lifecycle of a restaurant tab.
/// - `open`: customer seated, items being added
/// - `closed`: bill settled → a matching Sale doc exists (linked via saleId)
/// - `cancelled`: tab voided before paying (no Sale created)
enum TableOrderStatus { open, closed, cancelled }

/// Kitchen-side lifecycle of one line.
/// - `pending`: just added by cashier, kitchen hasn't seen it
/// - `sent`: sent to the kitchen, being cooked
/// - `ready`: kitchen marked it done — ready to serve
enum KitchenStatus { pending, sent, ready }

/// One line on an open tab. Mirrors the fields of `SaleItem` so closing the
/// tab can build the Sale doc with no field translation.
class TableOrderItem {
  final String id;
  final String productId;
  final String productName;
  final double price;
  final double costPrice;
  final int quantity;
  final String? notes;
  final List<OrderModifier> modifiers;
  final KitchenStatus kitchenStatus;
  final DateTime? sentToKitchenAt;
  final DateTime? readyAt;

  const TableOrderItem({
    this.id = '',
    required this.productId,
    required this.productName,
    required this.price,
    this.costPrice = 0,
    required this.quantity,
    this.notes,
    this.modifiers = const [],
    this.kitchenStatus = KitchenStatus.pending,
    this.sentToKitchenAt,
    this.readyAt,
  });

  /// Per-unit price after modifier adjustments (e.g. base ฿65 + เพิ่มไข่ ฿10).
  double get unitPrice =>
      price + modifiers.fold<double>(0, (s, m) => s + m.priceAdjust);

  double get subtotal => unitPrice * quantity;

  factory TableOrderItem.fromMap(Map<String, dynamic> m) => TableOrderItem(
        id: m['id'] as String? ?? '',
        productId: m['productId'] ?? '',
        productName: m['productName'] ?? '',
        price: (m['price'] ?? 0).toDouble(),
        costPrice: (m['costPrice'] ?? 0).toDouble(),
        quantity: (m['quantity'] ?? 1) as int,
        notes: m['notes'] as String?,
        modifiers: ((m['modifiers'] as List<dynamic>?) ?? const [])
            .map((e) => OrderModifier.fromMap(e as Map<String, dynamic>))
            .toList(),
        kitchenStatus: KitchenStatus.values.firstWhere(
          (e) => e.name == (m['kitchenStatus'] ?? 'pending'),
          orElse: () => KitchenStatus.pending,
        ),
        sentToKitchenAt: (m['sentToKitchenAt'] as Timestamp?)?.toDate(),
        readyAt: (m['readyAt'] as Timestamp?)?.toDate(),
      );

  Map<String, dynamic> toMap() => {
        if (id.isNotEmpty) 'id': id,
        'productId': productId,
        'productName': productName,
        'price': price,
        'costPrice': costPrice,
        'quantity': quantity,
        if (notes != null) 'notes': notes,
        if (modifiers.isNotEmpty)
          'modifiers': modifiers.map((m) => m.toMap()).toList(),
        'kitchenStatus': kitchenStatus.name,
        if (sentToKitchenAt != null)
          'sentToKitchenAt': Timestamp.fromDate(sentToKitchenAt!),
        if (readyAt != null) 'readyAt': Timestamp.fromDate(readyAt!),
      };

  TableOrderItem copyWith({
    String? id,
    int? quantity,
    String? notes,
    List<OrderModifier>? modifiers,
    KitchenStatus? kitchenStatus,
    DateTime? sentToKitchenAt,
    DateTime? readyAt,
  }) =>
      TableOrderItem(
        id: id ?? this.id,
        productId: productId,
        productName: productName,
        price: price,
        costPrice: costPrice,
        quantity: quantity ?? this.quantity,
        notes: notes ?? this.notes,
        modifiers: modifiers ?? this.modifiers,
        kitchenStatus: kitchenStatus ?? this.kitchenStatus,
        sentToKitchenAt: kitchenStatus == KitchenStatus.pending
            ? null
            : sentToKitchenAt ?? this.sentToKitchenAt,
        readyAt: kitchenStatus == KitchenStatus.pending
            ? null
            : readyAt ?? this.readyAt,
      );
}

/// An open tab on a restaurant table. Closes via [TableService.closeOrder]
/// which produces a Sale doc and frees the table.
class TableOrder {
  final String id;
  final String tableId;
  final String tableName;
  final List<TableOrderItem> items;
  final TableOrderStatus status;
  final DateTime openedAt;
  final DateTime? closedAt;

  /// Set when status == closed — points to the resulting Sale doc.
  final String? saleId;

  const TableOrder({
    required this.id,
    required this.tableId,
    required this.tableName,
    required this.items,
    this.status = TableOrderStatus.open,
    required this.openedAt,
    this.closedAt,
    this.saleId,
  });

  double get subtotal => items.fold<double>(0, (s, i) => s + i.subtotal);

  int get itemCount => items.fold<int>(0, (s, i) => s + i.quantity);

  factory TableOrder.fromFirestore(Map<String, dynamic> data, String id) =>
      TableOrder(
        id: id,
        tableId: data['tableId'] ?? '',
        tableName: data['tableName'] ?? '',
        items: (data['items'] as List<dynamic>? ?? [])
            .asMap()
            .entries
            .map((e) => TableOrderItem.fromMap({
                  ...Map<String, dynamic>.from(e.value as Map),
                  'id': (e.value as Map)['id'] ?? 'legacy-${e.key}',
                }))
            .toList(),
        status: TableOrderStatus.values.firstWhere(
          (e) => e.name == (data['status'] ?? 'open'),
          orElse: () => TableOrderStatus.open,
        ),
        openedAt: (data['openedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        closedAt: (data['closedAt'] as Timestamp?)?.toDate(),
        saleId: data['saleId'] as String?,
      );

  Map<String, dynamic> toFirestore() => {
        'tableId': tableId,
        'tableName': tableName,
        'items': items.map((e) => e.toMap()).toList(),
        'status': status.name,
        'openedAt': Timestamp.fromDate(openedAt),
        if (closedAt != null) 'closedAt': Timestamp.fromDate(closedAt!),
        if (saleId != null) 'saleId': saleId,
      };
}
