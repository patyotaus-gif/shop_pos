import 'package:cloud_firestore/cloud_firestore.dart';

import 'order_modifier.dart';
import 'receipt_profile.dart';
import 'round_queue.dart';

enum PaymentMethod { cash, transfer, qr, online }

enum SalesChannel {
  unspecified,
  storefront,
  dineIn,
  takeaway,
  lineMan,
  grab,
  otherDelivery
}

extension SalesChannelName on SalesChannel {
  String get label => switch (this) {
        SalesChannel.unspecified => 'ไม่ระบุช่องทาง',
        SalesChannel.storefront => 'หน้าร้าน',
        SalesChannel.dineIn => 'ทานที่ร้าน',
        SalesChannel.takeaway => 'ซื้อกลับ',
        SalesChannel.lineMan => 'LINE MAN',
        SalesChannel.grab => 'Grab',
        SalesChannel.otherDelivery => 'เดลิเวอรีอื่น',
      };
}

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
  final bool? costKnown;
  final String? category;
  final String unit;
  final bool isWeighed;
  final num quantity;
  final double subtotal;
  final List<OrderModifier> modifiers;
  final String? notes;
  final bool isGift;

  const SaleItem({
    required this.productId,
    required this.productName,
    required this.price,
    this.costPrice = 0,
    this.costKnown,
    this.category,
    this.unit = 'ชิ้น',
    this.isWeighed = false,
    required this.quantity,
    required this.subtotal,
    this.modifiers = const [],
    this.notes,
    this.isGift = false,
  });

  double get unitCost {
    final cost = costPrice +
        modifiers.fold<double>(0, (value, m) => value + (m.costAdjust ?? 0));
    return cost.isFinite ? (cost * 100).round() / 100 : 0;
  }

  double get profit => subtotal - unitCost * quantity;
  bool get hasKnownCost =>
      (costKnown == true || (costKnown == null && costPrice > 0)) &&
      costPrice.isFinite &&
      costPrice >= 0 &&
      modifiers.every((m) =>
          m.costAdjust != null && m.costAdjust!.isFinite && m.costAdjust! >= 0);

  factory SaleItem.fromMap(Map<String, dynamic> m) => SaleItem(
        productId: m['productId'] ?? '',
        productName: m['productName'] ?? '',
        price: (m['price'] ?? 0).toDouble(),
        costPrice: (m['costPrice'] ?? 0).toDouble(),
        costKnown: m['costKnown'] as bool?,
        category: m['category'] as String?,
        unit: m['unit'] as String? ?? 'ชิ้น',
        isWeighed: m['isWeighed'] == true,
        quantity: m['quantity'] ?? 1,
        subtotal: (m['subtotal'] ?? 0).toDouble(),
        notes: m['notes'] as String?,
        isGift: m['isGift'] == true,
        modifiers: ((m['modifiers'] as List<dynamic>?) ?? const [])
            .map((e) => OrderModifier.fromMap(e as Map<String, dynamic>))
            .toList(),
      );

  Map<String, dynamic> toMap() => {
        if (isGift) 'isGift': true,
        'productId': productId,
        'productName': productName,
        'price': price,
        'costPrice': costPrice,
        if (costKnown != null) 'costKnown': costKnown,
        if (category != null) 'category': category,
        'quantity': quantity,
        'unit': unit,
        'isWeighed': isWeighed,
        'subtotal': subtotal,
        if (notes != null) 'notes': notes,
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
  final SalesChannel salesChannel;
  final bool isRefunded;
  final DateTime? refundedAt;
  final String? refundReason;
  final String? stripePaymentIntentId;

  /// Service charge added on top of the items subtotal. 0 for retail and
  /// for restaurants that haven't configured a percentage.
  final double serviceCharge;
  final double paymentAdjustment;
  final List<Map<String, dynamic>> buyGet;
  final List<Map<String, dynamic>> bundles;
  final double bundleDiscount;

  /// 1 for normal bills; > 1 means the bill was split evenly N ways at
  /// close time. The receipt shows the per-person figure when > 1.
  final int splitCount;

  /// Name of the staff member who rang the sale (PIN-based attribution,
  /// Full/Restaurant tiers). Null when no staff profile was active.
  final String? staffName;

  /// Per-day receipt number (YYMMDD-NNN) assigned at checkout. Null for
  /// online-order sales (digital, not printed at a till) and legacy sales.
  final String? receiptNo;
  final RoundQueue? queue;
  final List<String> offlineReview;

  /// Restaurant table this bill closed from (null for retail/takeaway).
  final String? tableName;
  final ReceiptProfile? receiptProfile;

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
    this.salesChannel = SalesChannel.unspecified,
    this.isRefunded = false,
    this.refundedAt,
    this.refundReason,
    this.stripePaymentIntentId,
    this.serviceCharge = 0,
    this.paymentAdjustment = 0,
    this.buyGet = const [],
    this.bundles = const [],
    this.bundleDiscount = 0,
    this.splitCount = 1,
    this.staffName,
    this.receiptNo,
    this.queue,
    this.offlineReview = const [],
    this.tableName,
    this.receiptProfile,
  });

  /// Sum of line item subtotals — total minus service charge plus discount.
  /// Useful for receipts that want to show subtotal explicitly.
  double get itemsSubtotal =>
      total - serviceCharge - paymentAdjustment + discount;

  /// Allocate the bill discount in satang; rounded lines must still sum exactly.
  List<double> get itemNetRevenue {
    final weights = items.map((i) => (i.subtotal * 100).round()).toList();
    final bundleCuts = List.filled(items.length, 0);
    final left = items.map((i) => i.isGift ? 0 : i.quantity).toList();
    for (final b in bundles) {
      final partWeights = List.filled(items.length, 0);
      for (final c in b['components'] as List) {
        num needed = (c['quantity'] as int) * (b['sets'] as int);
        for (var n = 0; n < items.length; n++) {
          final i = items[n];
          if (i.productId != c['productId'] ||
              i.isGift ||
              i.modifiers.isNotEmpty) {
            continue;
          }
          final take = needed < left[n] ? needed : left[n];
          needed -= take;
          left[n] -= take;
          partWeights[n] += (take * (c['unitPriceMinor'] as int)).round();
        }
      }
      final part = _allocate((b['discountMinor'] as num).toInt(), partWeights);
      for (var n = 0; n < items.length; n++) {
        bundleCuts[n] += part[n];
      }
    }
    final remaining =
        List.generate(items.length, (n) => weights[n] - bundleCuts[n]);
    final cut =
        (discount * 100).round() - bundleCuts.fold<int>(0, (v, c) => v + c);
    final cuts = _allocate(cut, remaining);
    return List.generate(items.length, (n) => (remaining[n] - cuts[n]) / 100);
  }

  static List<int> _allocate(int amount, List<int> weights) {
    final sum = weights.fold<int>(0, (value, w) => value + w);
    if (sum == 0) return List.filled(weights.length, 0);
    final cut = amount.clamp(0, sum);
    final cuts = weights.map((w) => cut * w ~/ sum).toList();
    final ranks = List.generate(weights.length, (i) => i)
      ..sort((a, b) {
        final compare =
            (cut * weights[b] % sum).compareTo(cut * weights[a] % sum);
        return compare == 0 ? a.compareTo(b) : compare;
      });
    final remainder = cut - cuts.fold<int>(0, (value, c) => value + c);
    for (var n = 0; n < remainder; n++) {
      cuts[ranks[n]]++;
    }
    return cuts;
  }

  factory Sale.fromFirestore(Map<String, dynamic> data, String id) => Sale(
        id: id,
        items: (data['items'] as List<dynamic>? ?? [])
            .map((e) => SaleItem.fromMap(e as Map<String, dynamic>))
            .toList(),
        total: (data['total'] ?? 0).toDouble(),
        discount: (data['discount'] ?? 0).toDouble(),
        paid: (data['paid'] ?? 0).toDouble(),
        change: (data['change'] ?? 0).toDouble(),
        createdAt:
            (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        isDebt: data['isDebt'] ?? false,
        salesChannel: SalesChannel.values.firstWhere(
            (c) => c.name == data['salesChannel'],
            orElse: () => SalesChannel.unspecified),
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
        paymentAdjustment: (data['paymentAdjustment'] as num?)?.toDouble() ?? 0,
        bundleDiscount: (data['bundleDiscount'] as num?)?.toDouble() ?? 0,
        bundles: ((data['bundles'] as List?) ?? const [])
            .map((b) => Map<String, dynamic>.from(b as Map))
            .toList(),
        buyGet: ((data['buyGet'] as List?) ?? const [])
            .map((g) => Map<String, dynamic>.from(g as Map))
            .toList(),
        splitCount: (data['splitCount'] ?? 1) as int,
        staffName: data['staffName'] as String?,
        receiptNo: data['receiptNo'] as String?,
        queue: RoundQueue.fromMap(data),
        offlineReview:
            List<String>.from(data['offlineReview'] as List? ?? const []),
        tableName: data['tableName'] as String?,
        receiptProfile: data['receiptProfile'] is Map
            ? ReceiptProfile.fromMap(
                Map<String, dynamic>.from(data['receiptProfile']))
            : null,
      );

  Map<String, dynamic> toFirestore() => {
        'items': items.map((e) => e.toMap()).toList(),
        'total': total,
        'discount': discount,
        'paid': paid,
        'change': change,
        'createdAt': Timestamp.fromDate(createdAt),
        'isDebt': isDebt,
        'isRefunded': isRefunded,
        'customerName': customerName,
        'paymentMethod': paymentMethod.name,
        if (salesChannel != SalesChannel.unspecified)
          'salesChannel': salesChannel.name,
        if (serviceCharge > 0) 'serviceCharge': serviceCharge,
        if (paymentAdjustment != 0) 'paymentAdjustment': paymentAdjustment,
        if (buyGet.isNotEmpty) 'buyGet': buyGet,
        if (bundles.isNotEmpty) 'bundles': bundles,
        if (bundles.isNotEmpty) 'bundleDiscount': bundleDiscount,
        if (splitCount > 1) 'splitCount': splitCount,
        if (staffName != null) 'staffName': staffName,
        if (receiptNo != null) 'receiptNo': receiptNo,
        ...?queue?.toMap(),
        if (tableName != null) 'tableName': tableName,
        if (receiptProfile != null) 'receiptProfile': receiptProfile!.toMap(),
      };
}
