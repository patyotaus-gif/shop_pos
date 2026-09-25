// Shop type and subscription tier are independent. Keep legacy Restaurant
// records readable without rewriting customer subscriptions or expiry dates.
function shopTypeOf(shop) {
  return shop.tier === 'restaurant' ? 'restaurant' : (shop.shopType || 'retail');
}
function canUseTables(shop) {
  return shop.tier === 'restaurant' || (shopTypeOf(shop) === 'restaurant' &&
    ['lite', 'full'].includes(shop.tier || 'full'));
}
function canSelectTier(shop, tier) {
  return ['solo', 'lite', 'full'].includes(tier) ||
    (tier === 'restaurant' && (shop.tier === 'restaurant' || (!shop.tier && shop.shopType === 'restaurant')));
}
module.exports = { shopTypeOf, canUseTables, canSelectTier };
