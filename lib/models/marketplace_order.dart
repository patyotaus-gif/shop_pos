import 'package:cloud_firestore/cloud_firestore.dart';

/// Lifecycle of a marketplace (B2B) order from shop → supplier.
/// Distinct from the customer-facing ShopOrder; this is the shop buying
/// stock from a wholesaler.
enum MarketplaceOrderStatus {
  /// Shop submitted — supplier hasn't acknowledged yet.
  placed,

  /// Supplier accepted + is preparing.
  accepted,

  /// Out for delivery.
  shipped,

  /// Received by the shop — triggers the 2.5% take-rate billing.
  delivered,

  /// Cancelled by either side before delivery.
  cancelled,
}

extension MarketplaceOrderStatusX on MarketplaceOrderStatus {
  String get label => switch (this) {
        MarketplaceOrderStatus.placed => 'รอร้านค้าส่งยืนยัน',
        MarketplaceOrderStatus.accepted => 'กำลังเตรียมของ',
        MarketplaceOrderStatus.shipped => 'กำลังจัดส่ง',
        MarketplaceOrderStatus.delivered => 'รับของแล้ว',
        MarketplaceOrderStatus.cancelled => 'ยกเลิก',
      };
}

/// A line on a marketplace order — snapshot of the supplier product at
/// order time so price/name stay fixed even if the catalog changes.
class MarketplaceOrderItem {
  final String productId;
  final String name;
  final String unit;
  final double price;
  final int quantity;

  const MarketplaceOrderItem({
    required this.productId,
    required this.name,
    required this.unit,
    required this.price,
    required this.quantity,
  });

  double get subtotal => price * quantity;

  factory MarketplaceOrderItem.fromMap(Map<String, dynamic> m) =>
      MarketplaceOrderItem(
        productId: m['productId'] ?? '',
        name: m['name'] ?? '',
        unit: m['unit'] ?? 'ชิ้น',
        price: (m['price'] ?? 0).toDouble(),
        quantity: (m['quantity'] ?? 1) as int,
      );

  Map<String, dynamic> toMap() => {
        'productId': productId,
        'name': name,
        'unit': unit,
        'price': price,
        'quantity': quantity,
      };
}

/// A B2B order placed by a shop with a supplier. Stored in two places by
/// MarketplaceService so each side can query its own:
///   - shops/{shopId}/marketplaceOrders/{orderId}  (shop's view)
///   - suppliers/{supplierId}/orders/{orderId}      (supplier's view)
/// Both copies share the same id.
class MarketplaceOrder {
  final String id;
  final String shopId;
  final String shopName;
  final String supplierId;
  final String supplierName;
  final List<MarketplaceOrderItem> items;
  final MarketplaceOrderStatus status;

  /// 2.5% platform take rate computed from [subtotal] at delivery time.
  /// Stored on the order so statements/reports don't recompute drift.
  final double takeRate;

  final DateTime createdAt;
  final DateTime? deliveredAt;

  const MarketplaceOrder({
    required this.id,
    required this.shopId,
    required this.shopName,
    required this.supplierId,
    required this.supplierName,
    required this.items,
    this.status = MarketplaceOrderStatus.placed,
    this.takeRate = 0,
    required this.createdAt,
    this.deliveredAt,
  });

  double get subtotal =>
      items.fold<double>(0, (s, i) => s + i.subtotal);

  int get itemCount => items.fold<int>(0, (s, i) => s + i.quantity);

  factory MarketplaceOrder.fromFirestore(
          Map<String, dynamic> data, String id) =>
      MarketplaceOrder(
        id: id,
        shopId: data['shopId'] ?? '',
        shopName: data['shopName'] ?? '',
        supplierId: data['supplierId'] ?? '',
        supplierName: data['supplierName'] ?? '',
        items: (data['items'] as List<dynamic>? ?? [])
            .map((e) => MarketplaceOrderItem.fromMap(
                e as Map<String, dynamic>))
            .toList(),
        status: MarketplaceOrderStatus.values.firstWhere(
          (e) => e.name == (data['status'] ?? 'placed'),
          orElse: () => MarketplaceOrderStatus.placed,
        ),
        takeRate: (data['takeRate'] ?? 0).toDouble(),
        createdAt:
            (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        deliveredAt: (data['deliveredAt'] as Timestamp?)?.toDate(),
      );

  Map<String, dynamic> toFirestore() => {
        'shopId': shopId,
        'shopName': shopName,
        'supplierId': supplierId,
        'supplierName': supplierName,
        'items': items.map((e) => e.toMap()).toList(),
        'status': status.name,
        'takeRate': takeRate,
        'createdAt': Timestamp.fromDate(createdAt),
        if (deliveredAt != null)
          'deliveredAt': Timestamp.fromDate(deliveredAt!),
      };
}
