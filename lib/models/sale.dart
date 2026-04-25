import 'package:cloud_firestore/cloud_firestore.dart';

enum PaymentMethod { cash, transfer, qr }

extension PaymentMethodExt on PaymentMethod {
  String get label => switch (this) {
        PaymentMethod.cash => 'เงินสด',
        PaymentMethod.transfer => 'โอนเงิน',
        PaymentMethod.qr => 'QR Code',
      };
}

class SaleItem {
  final String productId;
  final String productName;
  final double price;
  final int quantity;
  final double subtotal;

  const SaleItem({
    required this.productId,
    required this.productName,
    required this.price,
    required this.quantity,
    required this.subtotal,
  });

  factory SaleItem.fromMap(Map<String, dynamic> m) => SaleItem(
        productId: m['productId'] ?? '',
        productName: m['productName'] ?? '',
        price: (m['price'] ?? 0).toDouble(),
        quantity: m['quantity'] ?? 1,
        subtotal: (m['subtotal'] ?? 0).toDouble(),
      );

  Map<String, dynamic> toMap() => {
        'productId': productId,
        'productName': productName,
        'price': price,
        'quantity': quantity,
        'subtotal': subtotal,
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
  });

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
      };
}
