const { test } = require('node:test');
const assert = require('node:assert/strict');
const { shopTypeOf, canUseTables, canSelectTier } = require('./shop_capabilities');
test('table ordering respects both type and level for all six plans', () => {
  for (const shopType of ['retail','restaurant']) {
    for (const tier of ['solo','lite','full']) {
      const shop = { shopType, tier };
      assert.equal(shopTypeOf(shop), shopType);
      assert.equal(canUseTables(shop), shopType === 'restaurant' && tier !== 'solo');
      assert.equal(canSelectTier(shop, tier), true);
      assert.equal(canSelectTier(shop, 'restaurant'), false);
      assert.equal(canSelectTier(shop, 'fake'), false);
    }
  }
});
test('legacy restaurant can renew without forced migration', () => {
  for (const shop of [{tier:'restaurant'}, {shopType:'restaurant'}]) {
    assert.equal(shopTypeOf(shop), 'restaurant');
    assert.equal(canUseTables(shop), true);
    assert.equal(canSelectTier(shop, 'restaurant'), true);
  }
});
