import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/models/shop.dart';
import 'package:shop_pos/services/entitlements.dart';
import 'package:shop_pos/widgets/tier_picker.dart';

void main() {
  test('all six combinations preserve independent type and tier', () {
    for (final type in ShopType.values) {
      for (final tier in ShopTierX.selectable) {
        final shop = Shop.fromFirestore(
            {'tier': tier.name, 'shopType': type.name}, 'shop');
        expect(shop.tier, tier);
        expect(shop.shopType, type);
        expect(Entitlements.canUseTables(tier, type),
            type == ShopType.restaurant && tier != ShopTier.solo);
        expect(Entitlements.canUseKitchen(tier, type),
            type == ShopType.restaurant && tier != ShopTier.solo);
        expect(Entitlements.canUseRecipes(tier, type),
            type == ShopType.restaurant && tier == ShopTier.full);
      }
    }
  });
  test('legacy restaurant retains full capabilities and unlimited staff', () {
    for (final data in [
      {'tier': 'restaurant'},
      {'shopType': 'restaurant'}
    ]) {
      final shop = Shop.fromFirestore(data, 'legacy');
      expect(shop.tier, ShopTier.restaurant);
      expect(shop.shopType, ShopType.restaurant);
      expect(Entitlements.canUseTables(shop.tier, shop.shopType), isTrue);
      expect(Entitlements.maxUsers(shop.tier), -1);
    }
  });
  testWidgets('picker offers three plans with restaurant-specific capabilities',
      (tester) async {
    ShopTier? picked;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: TierPicker(
      selected: ShopTier.solo,
      shopType: ShopType.restaurant,
      onChanged: (tier) => picked = tier,
    ))));
    expect(find.text('Pokpok Solo'), findsOneWidget);
    expect(find.text('Pokpok Lite'), findsOneWidget);
    expect(find.text('Pokpok Full'), findsOneWidget);
    expect(find.textContaining('Restaurant'), findsNothing);
    expect(find.textContaining('ส่งครัว'), findsOneWidget);
    await tester.tap(find.text('Pokpok Lite'));
    expect(picked, ShopTier.lite);
  });
}
