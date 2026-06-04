import '../models/shop.dart';

/// Per-tier capability map. Single source of truth for "what can this
/// shop do?" — every screen that gates a feature reads from here so the
/// 4-tier ladder stays consistent and easy to audit.
///
/// Numbers mirror the GTM plan (Solo → Restaurant). Tier upgrades are
/// monotonic: anything Solo can do, Lite can too; anything Lite can do,
/// Full can too; etc. Adding a new tier means inserting a row, not
/// rewriting checks at call sites.
class Entitlements {
  Entitlements._();

  /// Max staff accounts per shop. -1 = unlimited (Restaurant).
  static int maxUsers(ShopTier t) => switch (t) {
        ShopTier.solo => 1,
        ShopTier.lite => 1,
        ShopTier.full => 3,
        ShopTier.restaurant => -1,
      };

  /// Pokpok kit (printer + drawer) prints physical receipts and opens the
  /// cash drawer via ESC/POS. Solo is BYOD-only, so no peripheral.
  static bool canUsePaperReceipt(ShopTier t) => t != ShopTier.solo;

  /// Inventory features: low-stock threshold, low-stock notifications,
  /// stock adjust history. Solo POS doesn't track stock at SKU level.
  static bool canUseInventory(ShopTier t) => t != ShopTier.solo;

  /// Customer database = the "ลูกหนี้" / debts collection today, plus
  /// future loyalty + customer history. Solo is single-transaction POS,
  /// no customer record.
  static bool canUseCustomerDb(ShopTier t) => t != ShopTier.solo;

  /// Per-customer loyalty (points, discount tiers) — Full and Restaurant
  /// only. Not built yet; flag is reserved so UI can foreshadow upgrade.
  static bool canUseLoyalty(ShopTier t) =>
      t == ShopTier.full || t == ShopTier.restaurant;

  /// Advanced report sections (top products, profit-margin breakdown,
  /// per-hour heatmap). Solo + Lite see the basic daily report only.
  static bool canUseAdvancedReports(ShopTier t) =>
      t == ShopTier.full || t == ShopTier.restaurant;

  /// Kitchen ticket display + send-to-kitchen flow. Restaurant only.
  static bool canUseKitchen(ShopTier t) => t == ShopTier.restaurant;

  /// Dine-in table management + open tabs. Restaurant only.
  static bool canUseTables(ShopTier t) => t == ShopTier.restaurant;

  /// Multi-location dashboard, location switching. Restaurant only.
  static bool canUseMultiBranch(ShopTier t) => t == ShopTier.restaurant;

  /// Xero / FlowAccount sync, REST API access. Restaurant only.
  static bool canUseApiSync(ShopTier t) => t == ShopTier.restaurant;

  /// Human-readable support promise per tier — shown in Settings under
  /// "สิ่งที่มีในแผน".
  static String supportSla(ShopTier t) => switch (t) {
        ShopTier.solo => 'Best-effort',
        ShopTier.lite => '48 ชม.',
        ShopTier.full => '24 ชม. + onsite repair',
        ShopTier.restaurant => '12 ชม. + dedicated AM',
      };

  /// The lowest tier that unlocks [feature]. Used by the upgrade prompt
  /// to tell the user "อัพเกรดเป็น X เพื่อใช้ฟีเจอร์นี้".
  static ShopTier minTierFor(EntitlementFeature feature) => switch (feature) {
        EntitlementFeature.paperReceipt => ShopTier.lite,
        EntitlementFeature.inventory => ShopTier.lite,
        EntitlementFeature.customerDb => ShopTier.lite,
        EntitlementFeature.loyalty => ShopTier.full,
        EntitlementFeature.advancedReports => ShopTier.full,
        EntitlementFeature.kitchen => ShopTier.restaurant,
        EntitlementFeature.tables => ShopTier.restaurant,
        EntitlementFeature.multiBranch => ShopTier.restaurant,
        EntitlementFeature.apiSync => ShopTier.restaurant,
      };
}

/// Stable identifier for a gated feature — keeps upgrade prompts from
/// passing free-form strings around.
enum EntitlementFeature {
  paperReceipt,
  inventory,
  customerDb,
  loyalty,
  advancedReports,
  kitchen,
  tables,
  multiBranch,
  apiSync,
}

extension EntitlementFeatureX on EntitlementFeature {
  /// Thai display name for upgrade prompts.
  String get label => switch (this) {
        EntitlementFeature.paperReceipt => 'ใบเสร็จกระดาษ + cash drawer',
        EntitlementFeature.inventory => 'จัดการสต็อกสินค้า',
        EntitlementFeature.customerDb => 'ฐานข้อมูลลูกค้า + ลูกหนี้',
        EntitlementFeature.loyalty => 'ระบบสะสมแต้มลูกค้า',
        EntitlementFeature.advancedReports => 'รายงานเชิงลึก',
        EntitlementFeature.kitchen => 'หน้าจอครัว',
        EntitlementFeature.tables => 'จัดการโต๊ะ',
        EntitlementFeature.multiBranch => 'จัดการหลายสาขา',
        EntitlementFeature.apiSync => 'เชื่อมต่อ Xero / FlowAccount',
      };
}
