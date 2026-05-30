import 'package:cloud_firestore/cloud_firestore.dart';

enum SubscriptionStatus { trial, active, expired }

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
  final String plan; // 'monthly' | 'yearly'
  final ShopType shopType;
  final DateTime? trialEndsAt;
  final DateTime? subscriptionEndsAt;
  final DateTime createdAt;

  const Shop({
    required this.id,
    required this.name,
    required this.email,
    required this.subscriptionStatus,
    this.plan = 'monthly',
    this.shopType = ShopType.retail,
    this.trialEndsAt,
    this.subscriptionEndsAt,
    required this.createdAt,
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

  factory Shop.fromFirestore(Map<String, dynamic> data, String id) => Shop(
        id: id,
        name: data['name'] ?? '',
        email: data['email'] ?? '',
        subscriptionStatus: SubscriptionStatus.values.firstWhere(
          (e) => e.name == (data['subscriptionStatus'] ?? 'trial'),
          orElse: () => SubscriptionStatus.trial,
        ),
        plan: data['plan'] ?? 'monthly',
        shopType: ShopType.values.firstWhere(
          (e) => e.name == (data['shopType'] ?? 'retail'),
          orElse: () => ShopType.retail,
        ),
        trialEndsAt: (data['trialEndsAt'] as Timestamp?)?.toDate(),
        subscriptionEndsAt: (data['subscriptionEndsAt'] as Timestamp?)?.toDate(),
        createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );

  Map<String, dynamic> toFirestore() => {
        'name': name,
        'email': email,
        'subscriptionStatus': subscriptionStatus.name,
        'plan': plan,
        'shopType': shopType.name,
        'trialEndsAt':
            trialEndsAt != null ? Timestamp.fromDate(trialEndsAt!) : null,
        'subscriptionEndsAt': subscriptionEndsAt != null
            ? Timestamp.fromDate(subscriptionEndsAt!)
            : null,
        'createdAt': Timestamp.fromDate(createdAt),
      };
}
