const {test} = require('node:test');
const assert = require('node:assert/strict');
const {fixture} = require('./accounting_fixture.cjs');
const {createWithPickup} = require('./pickup');

test('daily shop sequence survives retries, cancelled orders and Thailand midnight', async () => {
  const f = fixture();
  const create = (id, now, shop = 's') => createWithPickup({db:f.db,
    shopRef:f.db.collection('shops').doc(shop),
    orderRef:f.db.collection('shops').doc(shop).collection('orders').doc(id),
    order:{total:20,finalAmount:20,status:'pendingPayment',requestSignature:id}, now:()=>now});
  const before = Date.parse('2026-10-29T16:59:59Z');
  const results = await Promise.all(['a','b','c'].map(id=>create(id,before)));
  assert.deepEqual(results.map(r=>r.orderNumber), ['20261029-001','20261029-002','20261029-003']);
  assert.equal((await create('a',before+2000)).orderNumber, '20261029-001');
  f.docs.get('shops/s/orders/b').status='cancelled';
  assert.equal((await create('d',before)).orderNumber,'20261029-004');
  assert.equal((await create('e',before+2000)).orderNumber,'20261030-001');
  assert.equal((await create('f',before,'other')).orderNumber,'20261029-001');
});

test('legacy pending QR recovery preserves its amount and does not allocate a new number', async () => {
  const saved = {total:20,finalAmount:20.72,status:'pendingPayment',requestSignature:'old'};
  const f=fixture({'shops/s/orders/old':saved});
  const result=await createWithPickup({db:f.db,shopRef:f.db.collection('shops').doc('s'),
    orderRef:f.db.collection('shops').doc('s').collection('orders').doc('old'),
    order:{...saved,finalAmount:20},now:()=>Date.parse('2026-10-29T00:00:00Z')});
  assert.equal(result.finalAmount,20.72);
  assert.equal(result.orderNumber,null);
  assert.equal([...f.docs.keys()].some(k=>k.includes('orderCounters')),false);
});
