import 'package:cloud_firestore/cloud_firestore.dart';

import 'order_modifier.dart';

enum PaymentMethod { cash, transfer, qr, online }

extension PaymentMethodExt on PaymentMethod {
  String get label => switch (this) {
        PaymentMethod.cash => 'เงินสด',
        PaymentMethod.transfer => 'โอนเงิน',
        PaymentMethod.qr => 'QR Code',
        PaymentMethod.online => 'ออนไลน์',
      };
}

class SaleItem {
  final String productId;
  final String productName;
  final double price;
  final double costPrice;
  final int quantity;
  final double subtotal;
  final List<OrderModifier> modifiers;

  const SaleItem({
    required this.productId,
    required this.productName,
    required this.price,
    this.costPrice = 0,
    required this.quantity,
    required this.subtotal,
    this.modifiers = const [],
  });

  double get profit => (price - costPrice) * quantity;

  factory SaleItem.fromMap(Map<String, dynamic> m) => SaleItem(
        productId: m['productId'] ?? '',
        productName: m['productName'] ?? '',
        price: (m['price'] ?? 0).toDouble(),
        costPrice: (m['costPrice'] ?? 0).toDouble(),
        quantity: m['quantity'] ?? 1,
        subtotal: (m['subtotal'] ?? 0).toDouble(),
        modifiers: ((m['modifiers'] as List<dynamic>?) ?? const [])
            .map((e) => OrderModifier.fromMap(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toMap() => {
        'productId': productId,
        'productName': productName,
        'price': price,
        'costPrice': costPrice,
        'quantity': quantity,
        'subtotal': subtotal,
        if (modifiers.isNotEmpty)
          'modifiers': modifiers.map((m) => m.toMap()).toList(),
      };
}

class Sale {
  final String id;
  final List<SaleItem> items;
  final double total;
  final double discount;
  final double paid;
  final double change;
  final DateTime createdAt;
  final bool isDebt;
  final String? customerName;
  final PaymentMethod paymentMethod;
  final bool isRefunded;
  final DateTime? refundedAt;
  final String? refundReason;
  final String? stripePaymentIntentId;

  /// Service charge added on top of the items subtotal. 0 for retail and
  /// for restaurants that haven't configured a percentage.
  final double serviceCharge;

  /// 1 for normal bills; > 1 means the bill was split evenly N ways at
  /// close time. The receipt shows the per-person figure when > 1.
  final int splitCount;

  const Sale({
    required this.id,
    required this.items,
    required this.total,
    required this.discount,
    required this.paid,
    required this.change,
    required this.createdAt,
    this.isDebt = false,
    this.customerName,
    this.paymentMethod = PaymentMethod.cash,
    this.isRefunded = false,
    this.refundedAt,
    this.refundReason,
    this.stripePaymentIntentId,
    this.serviceCharge = 0,
    this.splitCount = 1,
  });

  /// Sum of line item subtotals — total minus service charge plus discount.
  /// Useful for receipts that want to show subtotal explicitly.
  double get itemsSubtotal => total - serviceCharge + discount;

  factory Sale.fromFirestore(Map<String, dynamic> data, String id) => Sale(
        id: id,
        items: (data['items'] as List<dynamic>? ?? [])
            .map((e) => SaleItem.fromMap(e as Map<String, dynamic>))
            .toList(),
        total: (data['total'] ?? 0).toDouble(),
        discount: (data['discount'] ?? 0).toDouble(),
        paid: (data['paid'] ?? 0).toDouble(),
        change: (data['change'] ?? 0).toDouble(),
        createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        isDebt: data['isDebt'] ?? false,
        customerName: data['customerName'],
        paymentMethod: PaymentMethod.values.firstWhere(
          (e) => e.name == (data['paymentMethod'] ?? 'cash'),
          orElse: () => PaymentMethod.cash,
        ),
        isRefunded: data['isRefunded'] ?? false,
        refundedAt: (data['refundedAt'] as Timestamp?)?.toDate(),
        refundReason: data['refundReason'],
        stripePaymentIntentId: data['stripePaymentIntentId'],
        serviceCharge: (data['serviceCharge'] ?? 0).toDouble(),
        splitCount: (data['splitCount'] ?? 1) as int,
      );

  Map<String, dynamic> toFirestore() => {
        'items': items.map((e) => e.toMap()).toList(),
        'total': total,
        'discount': discount,
        'paid': paid,
        'change': change,
        'createdAt': Timestamp.fromDate(createdAt),
        'isDebt': isDebt,
        'customerName': customerName,
        'paymentMethod': paymentMethod.name,
        if (serviceCharge > 0) 'serviceCharge': serviceCharge,
        if (splitCount > 1) 'splitCount': splitCount,
      };
}
