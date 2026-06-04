import 'package:cloud_firestore/cloud_firestore.dart';

enum SubscriptionStatus { trial, active, expired }

/// Pricing tier — chosen at signup and used by the entitlements service to
/// gate features (max users, kitchen display, multi-branch, API sync ฯลฯ).
/// Order matches "ladder logic" from Solo (cheapest, BYOD) to Restaurant
/// (full kit + kitchen + multi-branch).
enum ShopTier { solo, lite, full, restaurant }

extension ShopTierX on ShopTier {
  String get label => switch (this) {
        ShopTier.solo => 'Pokpok Solo',
        ShopTier.lite => 'Pokpok Lite',
        ShopTier.full => 'Pokpok Full',
        ShopTier.restaurant => 'Pokpok Restaurant',
      };

  /// Map tier → ShopType so the existing nav/UI gating (which keys on
  /// retail vs restaurant) keeps working without a separate `shopType`
  /// field becoming stale. Only Tier 4 unlocks restaurant features.
  ShopType get derivedShopType =>
      this == ShopTier.restaurant ? ShopType.restaurant : ShopType.retail;
}

/// What kind of business this shop runs. Picked at signup and gates which
/// POS workflow is shown — retail uses the original immediate-checkout flow,
/// restaurant uses tables + open tabs + kitchen tickets (PR 2+).
///
/// Existing shops written before this field existed default to `retail` on
/// read, so no Firestore migration is required.
enum ShopType { retail, restaurant }

class Shop {
  final String id;
  final String name;
  final String email;
  final SubscriptionStatus subscriptionStatus;
  final String plan; // 'monthly' | 'yearly' — billing cycle, NOT tier
  final ShopType shopType;
  final ShopTier tier;
  final int locations; // > 1 only for Restaurant tier (multi-branch)
  final DateTime? trialEndsAt;
  final DateTime? subscriptionEndsAt;
  final DateTime createdAt;

  /// Code other shops enter at signup to credit this shop with a referral.
  /// Generated once at createShop; shown in Settings to share.
  final String? referralCode;

  /// The code this shop used at signup (if any). Non-null marks the
  /// referral reward as already claimed — the applyReferral function
  /// won't credit twice.
  final String? referredBy;

  const Shop({
    required this.id,
    required this.name,
    required this.email,
    required this.subscriptionStatus,
    this.plan = 'monthly',
    this.shopType = ShopType.retail,
    this.tier = ShopTier.full,
    this.locations = 1,
    this.trialEndsAt,
    this.subscriptionEndsAt,
    required this.createdAt,
    this.referralCode,
    this.referredBy,
  });

  bool get isAccessAllowed {
    final now = DateTime.now();
    switch (subscriptionStatus) {
      case SubscriptionStatus.active:
        return subscriptionEndsAt?.isAfter(now) ?? false;
      case SubscriptionStatus.trial:
        return trialEndsAt?.isAfter(now) ?? false;
      case SubscriptionStatus.expired:
        return false;
    }
  }

  int get trialDaysLeft {
    if (trialEndsAt == null) return 0;
    return trialEndsAt!.difference(DateTime.now()).inDays.clamp(0, 999);
  }

  int get subscriptionDaysLeft {
    if (subscriptionEndsAt == null) return 0;
    return subscriptionEndsAt!.difference(DateTime.now()).inDays.clamp(0, 9999);
  }

  factory Shop.fromFirestore(Map<String, dynamic> data, String id) {
    // Backward compat: shops created before the 4-tier model had only
    // `shopType` (retail/restaurant). Map them onto the closest matching
    // tier so they keep working without a Firestore migration:
    //   - shopType=restaurant → tier=restaurant (Tier 4 has the same
    //     feature set they were paying for)
    //   - shopType=retail (or missing) → tier=full (Tier 3 was the
    //     historical ฿299 ≈ ฿599 equivalent — closest experience)
    final shopType = ShopType.values.firstWhere(
      (e) => e.name == (data['shopType'] ?? 'retail'),
      orElse: () => ShopType.retail,
    );
    final tier = data['tier'] != null
        ? ShopTier.values.firstWhere(
            (e) => e.name == data['tier'],
            orElse: () => ShopTier.full,
          )
        : (shopType == ShopType.restaurant ? ShopTier.restaurant : ShopTier.full);

    return Shop(
      id: id,
      name: data['name'] ?? '',
      email: data['email'] ?? '',
      subscriptionStatus: SubscriptionStatus.values.firstWhere(
        (e) => e.name == (data['subscriptionStatus'] ?? 'trial'),
        orElse: () => SubscriptionStatus.trial,
      ),
      plan: data['plan'] ?? 'monthly',
      shopType: shopType,
      tier: tier,
      locations: (data['locations'] ?? 1) as int,
      trialEndsAt: (data['trialEndsAt'] as Timestamp?)?.toDate(),
      subscriptionEndsAt: (data['subscriptionEndsAt'] as Timestamp?)?.toDate(),
      createdAt:
          (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      referralCode: data['referralCode'] as String?,
      referredBy: data['referredBy'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'email': email,
        'subscriptionStatus': subscriptionStatus.name,
        'plan': plan,
        'shopType': shopType.name,
        'tier': tier.name,
        'locations': locations,
        'trialEndsAt':
            trialEndsAt != null ? Timestamp.fromDate(trialEndsAt!) : null,
        'subscriptionEndsAt': subscriptionEndsAt != null
            ? Timestamp.fromDate(subscriptionEndsAt!)
            : null,
        'createdAt': Timestamp.fromDate(createdAt),
        if (referralCode != null) 'referralCode': referralCode,
        if (referredBy != null) 'referredBy': referredBy,
      };
}
