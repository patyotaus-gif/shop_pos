// Run only against the local demo emulator; never change a production shop.
const assert = require('node:assert/strict');
const {randomUUID} = require('node:crypto');
const {initializeApp, deleteApp} = require('firebase-admin/app'), firestoreSdk = require('firebase-admin/firestore');
const {HttpsError} = require('firebase-functions/v2/https');
(async () => {
  assert.match(process.env.FIRESTORE_EMULATOR_HOST || '', /^(127\.0\.0\.1|localhost):\d+$/);
  const app = initializeApp({projectId: 'demo-pokpok-admin'}, 'table-recovery-tests');
  const db = firestoreSdk.getFirestore(app), FieldValue = firestoreSdk.FieldValue;
  const shopId = 'table-recovery-' + randomUUID(), shop = db.collection('shops').doc(shopId);
  const ref = shop.collection('tables').doc('one');
  const tab = shop.collection('tableOrders').doc('old');
  const req = {auth: {uid: shopId, token: {}}, data: {shopId, tableId: 'one'}};
  const run = require('./table_recovery').handlers({db, FieldValue, HttpsError}).reconcile;
  try {
    await shop.set({name: 'isolated table recovery test'});
    await ref.set({status: 'occupied', currentOrderId: 'old'});
    await tab.set({status: 'closed', tableId: 'one', saleId: 'sale'});
    await shop.collection('sales').doc('sale').set({total: 70});
    await Promise.all(Array.from({length: 5}, () => run(req)));
    assert.equal((await ref.get()).data().status, 'available');
    assert.equal((await tab.get()).data().status, 'closed');

    // A QR/POS writer also locks the table document. Recovery must not erase
    // the concurrent new order, whichever transaction wins first.
    await ref.update({status: 'occupied', currentOrderId: 'old'});
    const next = shop.collection('tableOrders').doc('next');
    await Promise.all([run(req), db.runTransaction(async tx => {
      await tx.get(ref);
      tx.set(next, {tableId: 'one', status: 'open', items: [{quantity: 1}]});
      tx.update(ref, {status: 'occupied', currentOrderId: 'next'});
    })]);
    assert.equal((await ref.get()).data().currentOrderId, 'next');
    assert.equal((await ref.get()).data().status, 'occupied');
    // Lost pointer: repair finds the open bill through a transactional query.
    await ref.update({currentOrderId: null});
    assert.equal((await run(req)).orderId, 'next');
    await next.update({status: 'closed'});
    const web = shop.collection('orders').doc('web');
    await web.set({tableId: 'one', status: 'ready'});
    await assert.rejects(() => run(req), {code: 'failed-precondition'});
    await web.update({status: 'completed'});
    assert.equal((await run(req)).status, 'available');
    assert.equal((await shop.collection('sales').get()).size, 1);
    assert.equal((await shop.collection('sales').doc('sale').get()).data().total, 70);
    assert.equal((await shop.collection('moneyMovements').get()).size, 0);
    console.log('PASS table recovery: replay, concurrent QR writer, orphan link, online work guard, unchanged money');
  } finally {
    await db.recursiveDelete(shop);
    await deleteApp(app);
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
