import 'package:cloud_firestore/cloud_firestore.dart';
import 'round_queue.dart';

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
  final num quantity;
  final String preparationNote;

  const OrderItem({
    required this.productId,
    required this.productName,
    required this.price,
    required this.quantity,
    this.preparationNote = '',
  });

  double get subtotal => price * quantity;

  factory OrderItem.fromMap(Map<String, dynamic> m) => OrderItem(
        productId: m['productId'] ?? '',
        productName: m['productName'] ?? '',
        price: (m['price'] ?? 0).toDouble(),
        quantity: m['quantity'] ?? 1,
        preparationNote: [
          ...((m['modifiers'] as List?) ?? [])
              .map((v) => v is Map ? (v['optionName'] ?? '').toString() : ''),
          (m['notes'] ?? m['preparationNote'] ?? '').toString(),
        ].where((s) => s.isNotEmpty).join(' • '),
      );

  Map<String, dynamic> toMap() => {
        'productId': productId,
        'productName': productName,
        'price': price,
        'quantity': quantity,
        if (preparationNote.isNotEmpty) 'preparationNote': preparationNote,
      };
}

class ShopOrder {
  final String id;
  final String? orderNumber;
  final RoundQueue? queue;
  String get displayLabel => tableName?.isNotEmpty == true
      ? 'โต๊ะ $tableName'
      : queue?.label ?? 'เลขออเดอร์ $displayNumber';
  String get displayNumber => orderNumber ?? id;
  final String customerName;
  final String customerPhone;
  final List<OrderItem> items;

  /// Merchandise total after discounts.
  final double total;
  final double discount;
  final String? couponCode;
  final double bundleDiscount;
  final List<Map<String, dynamic>> bundles;

  /// The amount the customer is actually instructed to transfer. May differ
  /// from [total] on older orders with an identifying-satang amount. New
  /// orders charge the exact total; old QR amounts must remain unchanged.
  /// Falls back to [total] for legacy orders that didn't carry this field.
  final double finalAmount;

  /// 'promptpay' (default) or 'stripe' for legacy online orders.
  final String paymentMethod;

  /// Bank/SlipOK transaction reference once the order is marked paid.
  final String? paymentRef;

  /// Uploaded slip evidence awaiting review, not proof of payment by itself.
  final String? slipUrl;

  /// True when the order was confirmed by an automated path (slip
  /// verify or bank notification) rather than the shop owner tapping
  /// "ได้รับเงินแล้ว" manually.
  final bool autoConfirmed;
  final bool bankMatchPending;
  final bool bankMatchAmbiguous;

  final OrderStatus status;
  final DateTime createdAt;
  final DateTime? paidAt;
  final DateTime? statusUpdatedAt;

  /// Legacy paid orders may predate sale links. The receipt screen must still
  /// resolve an existing sale; this flag never authorizes or creates a payment.
  bool get canOpenReceipt =>
      [
        OrderStatus.paid,
        OrderStatus.accepted,
        OrderStatus.ready,
        OrderStatus.completed
      ].contains(status) ||
      (status == OrderStatus.cancelled && paidAt != null);

  /// QR-link context tags (display-only): 'takeaway' | 'dineInPrepaid'.
  final String? orderType;
  final String? tableName;
  final String? pickupMode;
  final DateTime? pickupStartAt;
  final DateTime? pickupEndAt;
  final String? pickupLabel;

  String? get pickupDescription {
    final parts =
        RegExp(r'^(\d{2}/\d{2}/\d{4})\s+(.+)$').firstMatch(pickupLabel ?? '');
    if (parts != null) {
      return 'วันรับสินค้า: ${parts[1]}\nเวลารับ: ${parts[2]} (เวลาไทย)';
    }
    return pickupLabel != null
        ? 'นัดรับ $pickupLabel (เวลาไทย)'
        : pickupMode == 'asap'
            ? 'รับเร็วที่สุด • รอร้านแจ้งพร้อมรับ'
            : null;
  }

  const ShopOrder({
    required this.id,
    this.orderNumber,
    this.queue,
    required this.customerName,
    required this.customerPhone,
    required this.items,
    required this.total,
    this.discount = 0,
    this.couponCode,
    this.bundleDiscount = 0,
    this.bundles = const [],
    double? finalAmount,
    this.paymentMethod = 'promptpay',
    this.paymentRef,
    this.slipUrl,
    this.autoConfirmed = false,
    this.bankMatchPending = false,
    this.bankMatchAmbiguous = false,
    required this.status,
    required this.createdAt,
    this.paidAt,
    this.statusUpdatedAt,
    this.orderType,
    this.tableName,
    this.pickupMode,
    this.pickupStartAt,
    this.pickupEndAt,
    this.pickupLabel,
  }) : finalAmount = finalAmount ?? total;

  factory ShopOrder.fromFirestore(Map<String, dynamic> data, String id) =>
      ShopOrder(
        id: id,
        orderNumber: data['orderNumber'] as String?,
        queue: RoundQueue.fromMap(data),
        customerName: data['customerName'] ?? '',
        customerPhone: data['customerPhone'] ?? '',
        items: (data['items'] as List<dynamic>? ?? [])
            .map((e) => OrderItem.fromMap(e as Map<String, dynamic>))
            .toList(),
        total: (data['total'] ?? 0).toDouble(),
        discount: (data['discount'] as num?)?.toDouble() ?? 0,
        couponCode: (data['coupon'] as Map?)?['code'] as String?,
        bundleDiscount: (data['bundleDiscount'] as num?)?.toDouble() ?? 0,
        bundles: ((data['bundles'] as List?) ?? const [])
            .map((b) => Map<String, dynamic>.from(b as Map))
            .toList(),
        finalAmount: (data['finalAmount'] as num?)?.toDouble(),
        paymentMethod: data['paymentMethod'] as String? ?? 'promptpay',
        paymentRef: data['paymentRef'] as String?,
        slipUrl: data['slipUrl'] as String?,
        autoConfirmed: data['autoConfirmed'] as bool? ?? false,
        bankMatchPending:
            ['awaitingOwner', 'ambiguous'].contains(data['bankMatchStatus']),
        bankMatchAmbiguous: data['bankMatchStatus'] == 'ambiguous',
        status: OrderStatus.values.firstWhere(
          (e) => e.name == (data['status'] ?? 'pendingPayment'),
          orElse: () => OrderStatus.pendingPayment,
        ),
        createdAt:
            (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        paidAt: (data['paidAt'] as Timestamp?)?.toDate(),
        statusUpdatedAt: (data['statusUpdatedAt'] as Timestamp?)?.toDate(),
        orderType: data['orderType'] as String?,
        tableName: data['tableName'] as String?,
        pickupMode: data['pickupMode'] as String?,
        pickupStartAt: (data['pickupStartAt'] as Timestamp?)?.toDate(),
        pickupEndAt: (data['pickupEndAt'] as Timestamp?)?.toDate(),
        pickupLabel: data['pickupLabel'] as String?,
      );
}
