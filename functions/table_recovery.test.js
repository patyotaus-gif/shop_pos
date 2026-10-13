'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {fixture} = require('./accounting_fixture.cjs');
const {HttpsError} = require('firebase-functions/v2/https');
const root = 'shops/shop';
const tablePath = root + '/tables/t';
const request = {auth: {uid: 'shop', token: {}}, data: {shopId: 'shop', tableId: 't'}};
function setup(table, tabs = {}, online = {}) {
  const initial = {[tablePath]: table,
    [root + '/sales/sale']: {total: 70}, [root + '/products/cookie']: {stock: 10},
    [root + '/moneyMovements/sale']: {amount: 70}};
  for (const [id, value] of Object.entries(tabs)) initial[root + '/tableOrders/' + id] = value;
  for (const [id, value] of Object.entries(online)) initial[root + '/orders/' + id] = value;
  const f = fixture(initial);
  return {...f, run: require('./table_recovery').handlers({...f, HttpsError}).reconcile};
}
test('closed old link releases table idempotently without changing financial or order records', async () => {
  const f = setup({status: 'occupied', currentOrderId: 'old'}, {old: {tableId: 't', status: 'closed', saleId: 'sale'}});
  const before = [...f.docs].filter(([p]) => p !== tablePath);
  assert.deepEqual(await f.run(request), {status: 'available', orderId: null});
  await f.run(request);
  assert.equal(f.docs.get(tablePath).currentOrderId, null);
  assert.deepEqual([...f.docs].filter(([p]) => p !== tablePath), before);
});
test('orphan open bill is relinked, never marked paid or available', async () => {
  const f = setup({status: 'available'}, {open: {tableId: 't', status: 'open', items: [{quantity: 2}]}});
  const replies = await Promise.all([f.run(request), f.run(request)]);
  assert.ok(replies.every(r => r.status === 'occupied' && r.orderId === 'open'));
  assert.equal(f.docs.get(root + '/tableOrders/open').status, 'open');
});
test('stale closed link relinks the existing open bill rather than creating a new one', async () => {
  const f = setup({status: 'occupied', currentOrderId: 'old'}, {
    old: {tableId: 't', status: 'closed'}, live: {tableId: 't', status: 'open'}});
  assert.equal((await f.run(request)).orderId, 'live');
});
test('duplicate, missing, cross-table and unknown-status links require review without mutations', async () => {
  for (const f of [
    setup({status: 'occupied'}, {a: {tableId: 't', status: 'open'}, b: {tableId: 't', status: 'open'}}),
    setup({status: 'occupied', currentOrderId: 'missing'}),
    setup({status: 'occupied', currentOrderId: 'other'}, {other: {tableId: 'other', status: 'closed'}}),
    setup({status: 'occupied', currentOrderId: 'bad'}, {bad: {tableId: 't', status: 'unknown'}}),
  ]) {
    const before = structuredClone([...f.docs]);
    await assert.rejects(() => f.run(request), {code: 'failed-precondition'});
    assert.deepEqual([...f.docs], before);
  }
});
test('pending and paid online table work prevents release until completed or cancelled', async () => {
  for (const status of ['pendingPayment', 'paid', 'accepted', 'ready']) {
    const f = setup({status: 'occupied'}, {}, {web: {tableId: 't', status}});
    await assert.rejects(() => f.run(request), {code: 'failed-precondition'});
    assert.equal(f.docs.get(tablePath).status, 'occupied');
  }
  for (const status of ['completed', 'cancelled']) {
    const f = setup({status: 'occupied'}, {}, {web: {tableId: 't', status}});
    assert.equal((await f.run(request)).status, 'available');
  }
});
test('unauthenticated, staff and another owner cannot recover this shop tables', async () => {
  const f = setup({status: 'occupied'});
  for (const auth of [null, {uid: 'other'}, {uid: 'shop', token: {staffRole: 'cashier'}}]) {
    await assert.rejects(() => f.run({...request, auth}), {code: 'permission-denied'});
  }
  assert.equal(f.docs.get(tablePath).status, 'occupied');
});
