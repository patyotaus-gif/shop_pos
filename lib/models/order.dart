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

  /// Sum of [items] — what the cart says.
  final double total;

  /// The amount the customer is actually instructed to transfer. May differ
  /// from [total] by 1–99 satang so two parallel orders never collide on the
  /// same banking notification (see PromptPayQR.uniqueAmountFor).
  /// Falls back to [total] for legacy orders that didn't carry this field.
  final double finalAmount;

  /// 'promptpay' (default) or 'stripe' for legacy online orders.
  final String paymentMethod;

  /// Bank/SlipOK transaction reference once the order is marked paid.
  final String? paymentRef;

  /// Signed URL of the slip image, set when verifyPromptPaySlip auto-
  /// confirmed the order. Null for orders confirmed manually or by
  /// the Android notification listener.
  final String? slipUrl;

  /// True when the order was confirmed by an automated path (slip
  /// verify or bank notification) rather than the shop owner tapping
  /// "ได้รับเงินแล้ว" manually.
  final bool autoConfirmed;

  final OrderStatus status;
  final DateTime createdAt;
  final DateTime? paidAt;

  const ShopOrder({
    required this.id,
    required this.customerName,
    required this.customerPhone,
    required this.items,
    required this.total,
    double? finalAmount,
    this.paymentMethod = 'promptpay',
    this.paymentRef,
    this.slipUrl,
    this.autoConfirmed = false,
    required this.status,
    required this.createdAt,
    this.paidAt,
  }) : finalAmount = finalAmount ?? total;

  factory ShopOrder.fromFirestore(Map<String, dynamic> data, String id) =>
      ShopOrder(
        id: id,
        customerName: data['customerName'] ?? '',
        customerPhone: data['customerPhone'] ?? '',
        items: (data['items'] as List<dynamic>? ?? [])
            .map((e) => OrderItem.fromMap(e as Map<String, dynamic>))
            .toList(),
        total: (data['total'] ?? 0).toDouble(),
        finalAmount: (data['finalAmount'] as num?)?.toDouble(),
        paymentMethod: data['paymentMethod'] as String? ?? 'promptpay',
        paymentRef: data['paymentRef'] as String?,
        slipUrl: data['slipUrl'] as String?,
        autoConfirmed: data['autoConfirmed'] as bool? ?? false,
        status: OrderStatus.values.firstWhere(
          (e) => e.name == (data['status'] ?? 'pendingPayment'),
          orElse: () => OrderStatus.pendingPayment,
        ),
        createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        paidAt: (data['paidAt'] as Timestamp?)?.toDate(),
      );
}
