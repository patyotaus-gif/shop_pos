import 'package:cloud_firestore/cloud_firestore.dart';

/// Lifecycle of a restaurant tab.
/// - `open`: customer seated, items being added
/// - `closed`: bill settled → a matching Sale doc exists (linked via saleId)
/// - `cancelled`: tab voided before paying (no Sale created)
enum TableOrderStatus { open, closed, cancelled }

/// One line on an open tab. Mirrors the fields of `SaleItem` so closing the
/// tab can build the Sale doc with no field translation.
class TableOrderItem {
  final String productId;
  final String productName;
  final double price;
  final double costPrice;
  final int quantity;
  final String? notes;

  const TableOrderItem({
    required this.productId,
    required this.productName,
    required this.price,
    this.costPrice = 0,
    required this.quantity,
    this.notes,
  });

  double get subtotal => price * quantity;

  factory TableOrderItem.fromMap(Map<String, dynamic> m) => TableOrderItem(
        productId: m['productId'] ?? '',
        productName: m['productName'] ?? '',
        price: (m['price'] ?? 0).toDouble(),
        costPrice: (m['costPrice'] ?? 0).toDouble(),
        quantity: (m['quantity'] ?? 1) as int,
        notes: m['notes'] as String?,
      );

  Map<String, dynamic> toMap() => {
        'productId': productId,
        'productName': productName,
        'price': price,
        'costPrice': costPrice,
        'quantity': quantity,
        if (notes != null) 'notes': notes,
      };

  TableOrderItem copyWith({int? quantity, String? notes}) => TableOrderItem(
        productId: productId,
        productName: productName,
        price: price,
        costPrice: costPrice,
        quantity: quantity ?? this.quantity,
        notes: notes ?? this.notes,
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

  double get subtotal =>
      items.fold<double>(0, (s, i) => s + i.subtotal);

  int get itemCount => items.fold<int>(0, (s, i) => s + i.quantity);

  factory TableOrder.fromFirestore(Map<String, dynamic> data, String id) =>
      TableOrder(
        id: id,
        tableId: data['tableId'] ?? '',
        tableName: data['tableName'] ?? '',
        items: (data['items'] as List<dynamic>? ?? [])
            .map((e) => TableOrderItem.fromMap(e as Map<String, dynamic>))
            .toList(),
        status: TableOrderStatus.values.firstWhere(
          (e) => e.name == (data['status'] ?? 'open'),
          orElse: () => TableOrderStatus.open,
        ),
        openedAt:
            (data['openedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
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
