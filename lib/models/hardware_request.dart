import 'package:cloud_firestore/cloud_firestore.dart';

import 'shop.dart';

/// Which physical kit a tier ships with. Solo is BYOD (no kit), so it
/// never produces a HardwareRequest. The other tiers each map to a fixed
/// bundle the founder/sales agent assembles and ships.
enum HardwareKit { none, litePeripheral, fullKit, restaurantKit }

extension HardwareKitX on HardwareKit {
  String get label => switch (this) {
        HardwareKit.none => 'ไม่มี hardware (BYOD)',
        HardwareKit.litePeripheral => 'Pokpok kit (printer + drawer + stand)',
        HardwareKit.fullKit => 'ครบชุด: tablet 10" + printer + drawer + stand',
        HardwareKit.restaurantKit =>
          'Full kit + kitchen printer + order pad ที่ 2',
      };

  /// The kit a given tier ships with.
  static HardwareKit forTier(ShopTier tier) => switch (tier) {
        ShopTier.solo => HardwareKit.none,
        ShopTier.lite => HardwareKit.litePeripheral,
        ShopTier.full => HardwareKit.fullKit,
        ShopTier.restaurant => HardwareKit.restaurantKit,
      };
}

/// Lifecycle of a hardware shipment, from the moment a paying-intent shop
/// signs up to the kit landing on their counter (and back, if returned).
/// The founder/sales agent advances these states from an admin tool
/// (built later); the shop owner sees a read-only mirror in Settings.
enum HardwareStatus {
  /// Just created at signup — founder hasn't actioned it yet.
  requested,

  /// Founder confirmed + assembled, waiting for courier / hand delivery.
  preparing,

  /// On the way (or scheduled for onsite setup).
  shipped,

  /// Installed + working at the shop.
  delivered,

  /// Owner downgraded to Solo / churned — kit coming back.
  returned,
}

extension HardwareStatusX on HardwareStatus {
  String get label => switch (this) {
        HardwareStatus.requested => 'รอดำเนินการ',
        HardwareStatus.preparing => 'กำลังเตรียมเครื่อง',
        HardwareStatus.shipped => 'กำลังจัดส่ง / นัดติดตั้ง',
        HardwareStatus.delivered => 'ติดตั้งแล้ว',
        HardwareStatus.returned => 'คืนเครื่องแล้ว',
      };

  /// Progress 0..1 for the owner-facing tracker. `returned` is a terminal
  /// off-ramp, not progress, so it reports 0.
  double get progress => switch (this) {
        HardwareStatus.requested => 0.25,
        HardwareStatus.preparing => 0.5,
        HardwareStatus.shipped => 0.75,
        HardwareStatus.delivered => 1.0,
        HardwareStatus.returned => 0.0,
      };
}

/// One hardware shipment tied to a shop. Lives at
/// `shops/{shopId}/hardware/{requestId}`. A shop usually has exactly one
/// active request; downgrades/upgrades can create additional ones over
/// time (history is kept, not overwritten).
class HardwareRequest {
  final String id;
  final HardwareKit kit;
  final HardwareStatus status;

  /// Deposit the owner agreed to at signup (สตางค์→baht already): Full =
  /// 1000 refundable, Restaurant = 2000/location, Lite = 0 (pays the
  /// peripheral up-front separately).
  final double deposit;

  /// Lite only — the ฿4,000 peripheral bundle, financed or up-front.
  final double upfront;

  /// Optional serial/asset tag once a physical unit is assigned. Lets the
  /// repair workflow (24/12hr SLA) match a ticket to a device.
  final String? serialNumber;

  /// Free-form note from the founder (tracking number, courier, etc).
  final String? note;

  final DateTime createdAt;
  final DateTime? deliveredAt;

  const HardwareRequest({
    required this.id,
    required this.kit,
    this.status = HardwareStatus.requested,
    this.deposit = 0,
    this.upfront = 0,
    this.serialNumber,
    this.note,
    required this.createdAt,
    this.deliveredAt,
  });

  factory HardwareRequest.fromFirestore(
          Map<String, dynamic> data, String id) =>
      HardwareRequest(
        id: id,
        kit: HardwareKit.values.firstWhere(
          (e) => e.name == (data['kit'] ?? 'none'),
          orElse: () => HardwareKit.none,
        ),
        status: HardwareStatus.values.firstWhere(
          (e) => e.name == (data['status'] ?? 'requested'),
          orElse: () => HardwareStatus.requested,
        ),
        deposit: (data['deposit'] ?? 0).toDouble(),
        upfront: (data['upfront'] ?? 0).toDouble(),
        serialNumber: data['serialNumber'] as String?,
        note: data['note'] as String?,
        createdAt:
            (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        deliveredAt: (data['deliveredAt'] as Timestamp?)?.toDate(),
      );

  Map<String, dynamic> toFirestore() => {
        'kit': kit.name,
        'status': status.name,
        'deposit': deposit,
        'upfront': upfront,
        if (serialNumber != null) 'serialNumber': serialNumber,
        if (note != null) 'note': note,
        'createdAt': Timestamp.fromDate(createdAt),
        if (deliveredAt != null)
          'deliveredAt': Timestamp.fromDate(deliveredAt!),
      };
}
