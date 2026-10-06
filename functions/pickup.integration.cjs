// Local emulator only: no production order or payment is created.
const assert = require('node:assert/strict');
const admin = require('firebase-admin');
const { initializeTestEnvironment, assertFails } = require('@firebase/rules-unit-testing');
const { doc, setDoc } = require('firebase/firestore');
const { slots, createWithPickup, availability } = require('./pickup');
(async () => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) throw Error('Emulator required');
  const app = admin.initializeApp({ projectId: 'demo-pokpok-admin' }, 'pickup-integration');
  const db = app.firestore(), shopRef = db.doc('shops/pickup-owner');
  const now = Date.parse('2026-10-07T02:00:00Z');
  const pickup = { enabled: true, capacity: 1 };
  await shopRef.collection('settings').doc('shop').set({ pickup });
  const slot = slots(pickup, now)[0];
  const reserve = id => createWithPickup({ db, shopRef, orderRef: shopRef.collection('orders').doc(id),
    order: { status: 'pendingPayment', total: 50, finalAmount: 50.01, requestSignature: id },
    requestedSlot: slot.id, now: () => now });
  const results = await Promise.allSettled(['a', 'b', 'c'].map(reserve));
  assert.equal(results.filter(r => r.status === 'fulfilled').length, 1);
  const orders = await shopRef.collection('orders').get();
  assert.equal(orders.size, 1);
  assert.equal(orders.docs[0].data().pickupStartAt.toMillis(), Number(slot.id));
  assert.equal((await availability(shopRef, pickup, now)).slots.some(s => s.id === slot.id), false);
  await reserve(orders.docs[0].id);
  assert.equal((await shopRef.collection('orders').get()).size, 1);
  await orders.docs[0].ref.update({ status: 'cancelled' });
  await reserve('replacement');
  assert.equal((await shopRef.collection('sales').get()).size, 0);
  // Exercise the actual HTTP handler body against real Firestore references,
  // covering both cached legacy clients (no requestId) and the new response.
  const source = require('node:fs').readFileSync(require.resolve('./index'), 'utf8');
  const exported = {};
  require('node:vm').runInNewContext(source.slice(source.indexOf('exports.createPromptPayOrder ='), source.indexOf('exports.stripeWebhook =')), {
    exports: exported, onRequest: (_, handler) => handler,
    admin: { firestore: Object.assign(() => db, { FieldValue: admin.firestore.FieldValue }) },
    _verifyAppCheck: async () => true, loadModifierGroups: async () => ({}),
    priceLine: require('./tableorder').priceLine, pickupScheduling: require('./pickup'), require, console,
  });
  const webShop = db.doc('shops/pickup-web');
  await webShop.collection('settings').doc('shop').set({ promptpayId: '0812345678', pickup: { enabled: false } });
  await webShop.collection('products').doc('tea').set({ name: 'Tea', price: 50, stock: 10 });
  const body = { shopId: 'pickup-web', customerName: 'Fixture', customerPhone: '0800000000', items: [{ productId: 'tea', quantity: 1 }] };
  const checkout = async extra => {
    const result = { status: 200 };
    const res = { set() {}, status(n) { result.status = n; return this; }, json(data) { result.data = data; }, send() {} };
    await exported.createPromptPayOrder({ method: 'POST', body: { ...body, ...extra } }, res);
    return result;
  };
  assert.equal((await checkout({})).status, 200, 'legacy client still creates auto-ID order');
  await webShop.collection('settings').doc('shop').update({ pickup });
  const webSlot = slots(pickup)[0];
  const payload = { requestId: 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee', pickupMode: 'scheduled', pickupSlot: webSlot.id };
  const created = await checkout(payload), retried = await checkout(payload);
  assert.equal(created.status, 200);
  assert.equal(created.data.pickupLabel, webSlot.label);
  assert.equal(created.data.total, 50);
  assert.deepEqual(created, retried);
  assert.equal((await webShop.collection('orders').get()).size, 2);
  const env = await initializeTestEnvironment({ projectId: 'demo-pokpok-admin' });
  try {
    const owner = env.authenticatedContext('pickup-owner').firestore();
    await assertFails(setDoc(doc(owner, 'shops/pickup-owner/pickupSlots/control'), { revision: 0 }));
    const guest = env.unauthenticatedContext().firestore();
    await assertFails(setDoc(doc(guest, 'shops/pickup-owner/orders/forged'), { pickupSlot: slot.id }));
  } finally { await env.cleanup(); await app.delete(); }
  console.log('PASS pickup real transaction concurrency, retry, cancellation, timezone, no premature sales, protected slot control');
})().catch(error => { console.error(error); process.exitCode = 1; });
