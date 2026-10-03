import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/services/shop_database.dart';
import 'package:shop_pos/services/shop_service.dart';
import 'package:shop_pos/models/shop.dart';

void main() {
  tearDown(() => ShopDatabase.overrideShop = null);
  test('returning or linked user cannot reset shop tier or restart trial',
      () async {
    final db = FakeFirebaseFirestore();
    ShopDatabase.overrideShop = db.doc('shops/existing-uid');
    await ShopDatabase.shop.set({
      'name': 'Existing',
      'tier': 'lite',
      'subscriptionStatus': 'active',
      'email': 'original@example.test'
    });
    await ShopService.createShop(
        name: 'New name',
        email: 'new@example.test',
        tier: ShopTier.full,
        shopType: ShopType.restaurant,
        policyVersion: 'test');
    final saved = (await ShopDatabase.shop.get()).data()!;
    expect(saved['name'], 'Existing');
    expect(saved['tier'], 'lite');
    expect(saved['subscriptionStatus'], 'active');
    expect(saved.containsKey('trialEndsAt'), false);
  });
  test(
      'first-time social owner receives one consented shop at authenticated UID',
      () async {
    final db = FakeFirebaseFirestore();
    ShopDatabase.overrideShop = db.doc('shops/provider-uid');
    await ShopService.createShop(
        name: 'Restaurant',
        email: 'relay@privaterelay.appleid.com',
        tier: ShopTier.solo,
        shopType: ShopType.restaurant,
        policyVersion: 'test');
    final before = (await ShopDatabase.shop.get()).data()!;
    await ShopService.createShop(
        name: 'Retry', email: 'other@example.test', tier: ShopTier.full);
    final after = (await ShopDatabase.shop.get()).data()!;
    expect(after, before);
    expect(after['shopType'], 'restaurant');
    expect(after['tier'], 'solo');
    expect((after['consent'] as Map)['policyVersion'], 'test');
    expect((await db.collection('shops').get()).docs.length, 1);
  });
}
