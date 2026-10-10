'use strict';
const assert = require('node:assert/strict');
const admin = require('../functions/node_modules/firebase-admin');
const functionRequire = require('node:module').createRequire(require('node:path').resolve(__dirname, '../functions/package.json'));
const {HttpsError} = functionRequire('firebase-functions/v2/https');
const {archiveTestOrders, fingerprint} = require('./archive_test_orders.cjs');
const {handlers} = require('../functions/cash_accounting');
const {confirmOrder} = require('../functions/order_accounting');

(async () => {
  assert(process.env.FIRESTORE_EMULATOR_HOST, 'Emulator required');
  const app = admin.initializeApp({projectId: 'demo-pokpok-admin'}, 'test-order-archive');
  const db = app.firestore(), FieldValue = admin.firestore.FieldValue;
  const api = handlers({db, FieldValue, HttpsError});
  const old = admin.firestore.Timestamp.fromMillis(1000);
  async function fixture(id) {
    const shopId = 'archive-tests-' + id, shop = db.doc('shops/' + shopId);
    const request = data => ({auth: {uid: shopId, token: {}}, data: {shopId, ...data}});
    await shop.set({name: 'Emulator'});
    await api.open(request({requestId: 'round', openingFloat: 400, acknowledgeDeviceUpdate: true}));
    const entries = [];
    for (const orderId of ['one', 'two']) {
      const saleId = 'order-' + orderId, now = admin.firestore.Timestamp.now();
      const originals = {
        order: {status: 'completed', saleId, total: 20, createdAt: old, paidAt: now},
        sale: {orderId, total: 20, createdAt: now, paymentMethod: 'qr', isDebt: false,
          isRefunded: false, stockDeducted: {}, items: [{productId: 'removed', quantity: 1, price: 20}]},
        movement: {kind: 'sale', saleId, amountMinor: 2000, salesMinor: 2000, debtMinor: 0,
          method: 'qr', sessionId: null, needsReconciliation: true, occurredAt: now, recordedAt: now},
      };
      await shop.collection('orders').doc(orderId).set(originals.order);
      await shop.collection('sales').doc(saleId).set(originals.sale);
      await shop.collection('moneyMovements').doc('sale-' + saleId).set(originals.movement);
      entries.push({orderId, amountMinor: 2000, fingerprint: fingerprint(originals)});
    }
    await shop.collection('moneyMovements').doc('unrelated-old').set({needsReconciliation: true, recordedAt: old, amountMinor: 2002});
    await shop.collection('tableOrders').doc('table').set({status: 'open', openedAt: old, items: []});
    const manifest = {shopId, correctionId: 'correction', sessionId: 'round', entries, totalMinor: 4000,
      reason: 'Owner confirmed test orders; no real payment', operator: 'emulator', confirmedBy: shopId, actualMoneyReceivedMinor: 0};
    return {shopId, shop, request, manifest, run: apply => archiveTestOrders({db, FieldValue, manifest, apply})};
  }
  try {
    const f = await fixture('main');
    const before = await f.shop.collection('orders').doc('one').get();
    await f.run(false);
    assert.equal((await f.shop.collection('sales').get()).size, 2);
    assert.equal((await f.shop.collection('accountingCorrections').get()).size, 0);
    const results = await Promise.all([f.run(true), f.run(true)]);
    assert.equal(results.filter(r => r.alreadyApplied).length, 1);
    assert.equal((await f.shop.collection('sales').get()).size, 0);
    const money = await f.shop.collection('moneyMovements').get();
    assert.equal(money.size, 1); assert.equal(money.docs[0].id, 'unrelated-old');
    assert.equal(money.docs[0].data().amountMinor, 2002);
    const archive = f.shop.collection('accountingCorrections').doc('correction');
    assert.equal((await archive.collection('records').get()).size, 2);
    assert.deepEqual((await archive.collection('records').doc('one').get()).data().order, before.data());
    assert.equal((await archive.get()).data().actualRefundMinor, 0);
    const order = (await f.shop.collection('orders').doc('one').get()).data();
    assert.equal(order.status, 'cancelled'); assert.equal(order.isTestOrder, true);
    assert.equal(order.paidAt, undefined); assert.equal(order.saleId, undefined);
    await assert.rejects(confirmOrder({db, FieldValue, shopId: f.shopId, orderId: 'one', actor: f.shopId}), /Cancelled/);
    await assert.rejects(api.close(f.request({sessionId: 'round', countedCash: 400})), e => {
      assert.deepEqual(e.details.issues.map(i => i.type), ['openTable']); return true;
    });
    // Only emulator data: resolve the unrelated table to check resulting sums.
    await f.shop.collection('tableOrders').doc('table').update({status: 'cancelled'});
    const summary = await api.close(f.request({sessionId: 'round', countedCash: 400}));
    assert.equal(summary.grossTotal, 0); assert.equal(summary.refundTotal, 0);
    assert.equal(summary.billCount, 0); assert.equal(summary.expectedCash, 400);
    assert.equal((await f.run(true)).alreadyApplied, true);
    console.log('PASS: dry-run, atomic archive, concurrent retry, source preservation, no refund, close totals and table guard');

    const g = await fixture('changed');
    await g.shop.collection('sales').doc('order-two').update({total: 30});
    await assert.rejects(g.run(true), /Source changed/);
    assert.equal((await g.shop.collection('sales').get()).size, 2);
    assert.equal((await g.shop.collection('accountingCorrections').get()).size, 0);
    assert.equal((await g.shop.collection('orders').doc('one').get()).data().status, 'completed');
    console.log('PASS: changed source aborts the entire correction');

    for (const [id, alter] of [
      ['stock', async h => h.shop.collection('products').doc('removed').set({stock: 5})],
      ['round', async h => h.shop.collection('cashControl').doc('current').update({sessionId: 'another'})],
      ['debt', async h => h.shop.collection('debts').doc('debt').set({saleId: 'order-one'})],
    ]) {
      const h = await fixture(id); await alter(h); await assert.rejects(h.run(true));
      assert.equal((await h.shop.collection('sales').get()).size, 2);
      assert.equal((await h.shop.collection('accountingCorrections').get()).size, 0);
    }
    console.log('PASS: inventory, changed round and linked debt all reject without partial writes');
  } finally { await db.terminate(); await app.delete(); }
})().catch(e => {console.error(e); process.exitCode = 1;});
