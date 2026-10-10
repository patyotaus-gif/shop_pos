'use strict';
const assert = require('node:assert/strict');
const admin = require('../functions/node_modules/firebase-admin');
const {cancelTestTables} = require('./cancel_test_tables.cjs');
const {fingerprint} = require('./archive_test_orders.cjs');
const {inspectClose} = require('../functions/cash_integrity');
const {summarizeMovements} = require('../functions/money_ledger');
(async () => {
  assert(process.env.FIRESTORE_EMULATOR_HOST, 'Emulator required');
  const app = admin.initializeApp({projectId: 'demo-pokpok-admin'}, 'test-table-cancel');
  const db = app.firestore(), FieldValue = admin.firestore.FieldValue;
  async function fixture(id) {
    const shopId = 'cancel-test-tables-' + id, shop = db.doc('shops/' + shopId);
    const now = admin.firestore.Timestamp.now();
    await shop.collection('cashControl').doc('current').set({sessionId: 'round', revision: 1});
    await shop.collection('cashSessions').doc('round').set({status: 'open', accountingVersion: 1,
      openedAt: now, accountingStartAt: now, openingFloat: 400});
    await shop.collection('products').doc('product').set({stock: 10});
    const entries = [];
    for (const orderId of ['one', 'two']) {
      const originals = {order: {status: 'open', openedAt: now, tableId: orderId, tableName: orderId,
        items: orderId === 'one' ? [{productId: 'product', quantity: 2, price: 10, kitchenStatus: 'ready'}] : []},
        table: {name: orderId, status: 'occupied', currentOrderId: orderId}};
      await shop.collection('tableOrders').doc(orderId).set(originals.order);
      await shop.collection('tables').doc(orderId).set(originals.table);
      entries.push({orderId, tableId: orderId, fingerprint: fingerprint(originals)});
    }
    const manifest = {shopId, sessionId: 'round', correctionId: 'repair', confirmedBy: shopId,
      actualMoneyReceivedMinor: 0, reason: 'Owner confirmed both table bills are tests', entries};
    return {shop, manifest, run: apply => cancelTestTables({db, FieldValue, manifest, apply})};
  }
  try {
    const f = await fixture('success');
    await f.run(false);
    assert.equal((await f.shop.collection('tableOrders').doc('one').get()).data().status, 'open');
    const results = await Promise.all([f.run(true), f.run(true)]);
    assert.equal(results.filter(r => r.alreadyApplied).length, 1);
    const archives = await f.shop.collection('accountingCorrections').doc('repair').collection('records').get();
    assert.equal(archives.size, 2);
    for (const e of f.manifest.entries) {
      const a = archives.docs.find(d => d.id === e.orderId).data();
      assert.equal(fingerprint({order: a.order, table: a.table}), e.fingerprint);
      const order = (await f.shop.collection('tableOrders').doc(e.orderId).get()).data();
      assert.equal(order.status, 'cancelled'); assert.equal(order.consumedPreparedItems, false);
      assert.deepEqual(order.items, a.order.items);
      const table = (await f.shop.collection('tables').doc(e.tableId).get()).data();
      assert.equal(table.status, 'available'); assert.equal(table.currentOrderId, undefined);
    }
    for (const col of ['sales', 'moneyMovements', 'inventoryWaste']) assert.equal((await f.shop.collection(col).get()).size, 0);
    assert.equal((await f.shop.collection('products').doc('product').get()).data().stock, 10);
    const session = (await f.shop.collection('cashSessions').doc('round').get()).data();
    const check = await db.runTransaction(tx => inspectClose(tx, f.shop, 'round', session, []), {readOnly: true});
    assert.deepEqual(check.issues, []); assert.equal(session.status, 'open');
    assert.equal(summarizeMovements([], session.openingFloat).expectedCash, 400);
    console.log('PASS: dry-run, concurrent replay, originals, freed tables, no stock/waste/money changes, close readiness');
    for (const [id, alter] of [
      ['changed', f => f.shop.collection('tableOrders').doc('two').update({items: [{quantity: 3}]})],
      ['newtab', f => f.shop.collection('tables').doc('two').update({currentOrderId: 'new-order'})],
      ['paid', f => f.shop.collection('sales').doc('table-two').set({total: 20})],
    ]) {
      const f = await fixture(id); await alter(f); await assert.rejects(f.run(true));
      assert.equal((await f.shop.collection('tableOrders').doc('one').get()).data().status, 'open');
      assert.equal((await f.shop.collection('accountingCorrections').get()).size, 0);
    }
    console.log('PASS: changed items, replaced table link and recorded sale abort all changes');
  } finally {await db.terminate(); await app.delete();}
})().catch(e => {console.error(e); process.exitCode = 1;});
