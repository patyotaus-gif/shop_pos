import 'package:cloud_firestore/cloud_firestore.dart';

enum OrderStatus { pendingPayment, paid, accepted, ready, completed, cancelled }

extension OrderStatusExt on OrderStatus {
  String get label => switch (this) {
        OrderStatus.pendingPayment => 'รอชำระ',
        OrderStatus.paid => 'ชำระแล้ว',
        OrderStatus.accepted => 'กำลังเตรียม',
        OrderStatus.ready => 'พร้อมรับ',
        OrderStatus.completed => 'เสร็จสิ้น',
        OrderStatus.cancelled => 'ยกเลิก',
      };
}

class OrderItem {
  final String productId;
  final String productName;
  final double price;
  final int quantity;

  const OrderItem({
    required this.productId,
    required this.productName,
    required this.price,
    required this.quantity,
  });

  double get subtotal => price * quantity;

  factory OrderItem.fromMap(Map<String, dynamic> m) => OrderItem(
        productId: m['productId'] ?? '',
        productName: m['productName'] ?? '',
        price: (m['price'] ?? 0).toDouble(),
        quantity: m['quantity'] ?? 1,
      );

  Map<String, dynamic> toMap() => {
        'productId': productId,
        'productName': productName,
        'price': price,
        'quantity': quantity,
      };
}

class ShopOrder {
  final String id;
  final String customerName;
  final String customerPhone;
  final List<OrderItem> items;
  final double total;
  final OrderStatus status;
  final DateTime createdAt;
  final DateTime? paidAt;

  const ShopOrder({
    required this.id,
    required this.customerName,
    required this.customerPhone,
    required this.items,
    required this.total,
    required this.status,
    required this.createdAt,
    this.paidAt,
  });

  factory ShopOrder.fromFirestore(Map<String, dynamic> data, String id) =>
      ShopOrder(
        id: id,
        customerName: data['customerName'] ?? '',
        customerPhone: data['customerPhone'] ?? '',
        items: (data['items'] as List<dynamic>? ?? [])
            .map((e) => OrderItem.fromMap(e as Map<String, dynamic>))
            .toList(),
        total: (data['total'] ?? 0).toDouble(),
        status: OrderStatus.values.firstWhere(
          (e) => e.name == (data['status'] ?? 'pendingPayment'),
          orElse: () => OrderStatus.pendingPayment,
        ),
        createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        paidAt: (data['paidAt'] as Timestamp?)?.toDate(),
      );
}
