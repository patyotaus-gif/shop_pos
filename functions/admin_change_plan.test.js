const { test } = require('node:test');
const assert = require('node:assert/strict');
const { createChangePlan } = require('./admin_change_plan');
function fixture() {
  const shop = { tier: 'full', plan: 'monthly', locations: 1, subscriptionStatus: 'trial', trialEndsAt: 'unchanged', subscriptionEndsAt: null };
  const records = new Map([['shops/shop', shop]]);
  const ref = path => ({ path, collection: name => ref(`${path}/${name}`), doc: id => ref(`${path}/${id}`) });
  const db = { collection: name => ref(name), runTransaction: async fn => {
    const writes = []; const value = await fn({
      get: async r => ({ exists: records.has(r.path), data: () => records.get(r.path) }),
      update: (r, d) => writes.push(() => records.set(r.path, { ...records.get(r.path), ...d })),
      set: (r, d) => writes.push(() => records.set(r.path, d)),
    }); writes.forEach(w => w()); return value;
  } };
  return { records, change: createChangePlan({ db, assertFounder: () => {}, FieldValue: { serverTimestamp: () => 'server-time' } }),
    request: { auth: { uid: 'admin' }, data: { shopId: 'shop', tier: 'restaurant', billingCycle: 'yearly', locations: 2,
      expected: { tier: 'full', plan: 'monthly', locations: 1 }, requestId: 'unique-request-123', reason: 'ลูกค้าขอเปลี่ยนแผน' } } };
}
test('changes plan and navigation type, preserves expiry/status and records actor', async () => {
  const f = fixture(); await f.change(f.request);
  const shop = f.records.get('shops/shop');
  assert.equal(shop.tier, 'restaurant'); assert.equal(shop.plan, 'yearly'); assert.equal(shop.locations, 2);
  assert.equal(shop.shopType, 'restaurant'); assert.equal(shop.trialEndsAt, 'unchanged'); assert.equal(shop.subscriptionStatus, 'trial');
  assert.equal(shop.subscriptionEndsAt, null);
  const audit = f.records.get('shops/shop/planChanges/unique-request-123');
  assert.equal(audit.actor, 'admin'); assert.equal(audit.before.tier, 'full'); assert.equal(audit.after.tier, 'restaurant');
});
test('retry does not reapply changes, and a different payload cannot reuse its id', async () => {
  const f = fixture(); await f.change(f.request);
  assert.equal((await f.change(f.request)).replayed, true); assert.equal(f.records.size, 2);
  await assert.rejects(f.change({ ...f.request, data: { ...f.request.data, tier: 'lite' } }), e => e.code === 'already-exists');
});
test('stale form and invalid input leave shop and audit untouched', async () => {
  for (const edits of [{ locations: 0 }, { tier: 'fake' }, { reason: '' }, { expected: { tier: 'lite', plan: 'monthly', locations: 1 } }]) {
    const f = fixture(); await assert.rejects(f.change({ ...f.request, data: { ...f.request.data, ...edits } }));
    assert.equal(f.records.get('shops/shop').tier, 'full'); assert.equal(f.records.size, 1);
  }
});
test('production callable rejects unauthenticated and normal shop users', async () => {
  const { adminChangePlan } = require('./index');
  await assert.rejects(adminChangePlan.run({ data: {} }), e => e.code === 'unauthenticated');
  await assert.rejects(adminChangePlan.run({ auth: { uid: 'shop', token: { email: 'customer@example.com' } }, data: {} }), e => e.code === 'permission-denied');
});
test('changing tier preserves restaurant type unless explicitly changed', async () => {
  const f = fixture();
  f.records.get('shops/shop').shopType = 'restaurant';
  f.request.data.tier = 'lite';
  await f.change(f.request);
  assert.equal(f.records.get('shops/shop').shopType, 'restaurant');
  assert.equal(f.records.get('shops/shop').tier, 'lite');
});
test('explicit type changes are audited and stale type is rejected', async () => {
  const f = fixture();
  f.request.data.tier = 'lite';
  f.request.data.shopType = 'restaurant';
  f.request.data.expected.shopType = 'retail';
  await f.change(f.request);
  assert.equal(f.records.get('shops/shop/planChanges/unique-request-123').after.shopType, 'restaurant');
  f.request.data.requestId = 'different-request-123';
  f.request.data.expected = {tier:'lite',plan:'yearly',locations:2,shopType:'retail'};
  await assert.rejects(f.change(f.request), e => e.code === 'failed-precondition');
});
