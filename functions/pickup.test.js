const { test } = require('node:test');
const assert = require('node:assert/strict');
const { fixture } = require('./accounting_fixture.cjs');
const { slots, availability, createWithPickup } = require('./pickup');
const now = Date.parse('2026-10-07T02:00:00Z'); // Wed 09:00 Thailand.
const settings = { enabled: true, openMinute: 540, closeMinute: 1080, prepMinutes: 30, slotMinutes: 15, capacity: 1, weekdays: [3] };
function setup(raw = settings) {
  const f = fixture({ 'shops/s/settings/shop': { pickup: structuredClone(raw) } });
  const shopRef = f.db.collection('shops').doc('s');
  const create = (id, requestedSlot, extra = {}) => createWithPickup({ db: f.db, shopRef,
    orderRef: shopRef.collection('orders').doc(id), requestedSlot, pickupMode: 'scheduled', now: () => now,
    order: { status: 'pendingPayment', total: 50, finalAmount: 50.01, requestSignature: id, ...extra } });
  return { ...f, shopRef, create };
}
test('Thailand clock: prep cutoff, closed weekday, past and seven-day horizon', () => {
  const options = slots(settings, now);
  assert.equal(options[0].start, '2026-10-07T02:30:00.000Z');
  assert.equal(options[0].label, '07/10/2026 09:30–09:45 น.');
  assert.ok(options.every(s => s.start.startsWith('2026-10-07') && Date.parse(s.end) <= Date.parse('2026-10-07T11:00:00Z')));
  assert.deepEqual(slots({ ...settings, enabled: false }, now), []);
  assert.deepEqual(slots({ ...settings, closeMinute: 500 }, now), []);
  assert.deepEqual(slots({ ...settings, weekdays: [] }, now), []);
});
test('concurrent requests reserve last slot only once; cancelled order restores capacity', async () => {
  const f = setup(), slot = slots(settings, now)[0];
  const result = await Promise.allSettled([f.create('a', slot.id), f.create('b', slot.id)]);
  assert.equal(result.filter(r => r.status === 'fulfilled').length, 1);
  assert.equal(f.docs.has('shops/s/orders/b'), false);
  assert.equal((await availability(f.shopRef, settings, now)).slots.some(s => s.id === slot.id), false);
  f.docs.get('shops/s/orders/a').status = 'cancelled';
  await f.create('b', slot.id);
  assert.equal(f.docs.get('shops/s/orders/b').pickupLabel, slot.label);
  assert.equal(f.docs.get('shops/s/orders/b').paidAt, undefined);
  assert.equal([...f.docs.keys()].some(p => /sales|moneyMovements|cashSessions/.test(p)), false);
});
test('retry returns existing order without double reservation or overwriting totals', async () => {
  const f = setup(), slot = slots(settings, now)[0];
  await f.create('a', slot.id);
  const retry = await f.create('a', slot.id, { total: 999, finalAmount: 999.01 });
  assert.equal(retry.total, 50);
  assert.equal(f.docs.get('shops/s/pickupSlots/control').revision, 1);
  await assert.rejects(f.create('a', slot.id, { requestSignature: 'different' }));
});
test('reject stale, disabled, paused and dine-in scheduling, without creating orders', async () => {
  const f = setup(), slot = slots(settings, now)[0];
  await assert.rejects(f.create('past', String(now)));
  await assert.rejects(f.create('table', slot.id, { tableId: 't' }));
  f.docs.get('shops/s/settings/shop').ordersClosed = true;
  await assert.rejects(f.create('paused', slot.id));
  f.docs.get('shops/s/settings/shop').ordersClosed = false;
  f.docs.get('shops/s/settings/shop').pickup.enabled = false;
  await assert.rejects(f.create('disabled', slot.id));
  await f.create('asap', undefined);
  assert.equal(f.docs.get('shops/s/orders/asap').pickupMode, 'asap');
});
test('changing opening time/slot length cannot hide overlapping existing reservations', async () => {
  const original = { ...settings, slotMinutes: 60 };
  const f = setup(original), old = slots(original, now)[0];
  await f.create('old', old.id);
  const changed = { ...settings, openMinute: 545 };
  f.docs.get('shops/s/settings/shop').pickup = changed;
  const inside = slots(changed, now).find(s => Number(s.id) > Number(old.id) && Date.parse(s.start) < Date.parse(old.end));
  assert.ok(inside);
  await assert.rejects(f.create('new', inside.id), /เต็ม/);
  assert.equal((await availability(f.shopRef, changed, now)).slots.some(s => s.id === inside.id), false);
});
