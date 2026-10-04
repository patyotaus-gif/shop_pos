const { test } = require('node:test');
const assert = require('node:assert/strict');
const { buildAnalysis, windowFor, allocate, promptData } = require('./analytics');
const { handlers, daysOf } = require('./sales_assistant');
const now = new Date('2026-09-07T06:00:00Z');
const item = (id = 'a', extras = {}) => ({ productId: id, productName: id, price: 100, costPrice: 40,
  quantity: 1, subtotal: 100, category: 'อาหาร', ...extras });
const sale = (id, extras = {}) => ({ id, createdAt: new Date('2026-09-03T08:00:00Z'), total: 100,
  discount: 0, items: [item()], ...extras });
const report = (sales, extras = {}) => buildAnalysis({ sales, days: 7, now, ...extras });
test('calendar windows exclude today and honor Thai midnight', () => {
  const w = windowFor(7, 'Asia/Bangkok', now);
  assert.equal(w.from.toISOString(), '2026-08-23T17:00:00.000Z');
  assert.equal(w.to.toISOString(), '2026-09-06T17:00:00.000Z');
  const r = report([sale('today', { createdAt: now }), sale('end', { createdAt: new Date('2026-09-06T16:59:59Z') })]);
  assert.equal(r.current.net, 100); assert.equal(r.today.net, 100);
});
test('Sydney DST compares calendar days, not fixed 24-hour offsets', () => {
  const w = windowFor(7, 'Australia/Sydney', new Date('2026-10-06T02:00:00Z'));
  assert.equal(w.currentFrom.toISOString(), '2026-09-28T14:00:00.000Z');
  assert.equal(w.to.toISOString(), '2026-10-05T13:00:00.000Z');
});
test('bill discount, service, refund and allocated product profit reconcile', () => {
  const r = report([sale('a', { items: [item('a'), item('b', { costPrice: 20 })], total: 190, discount: 20, serviceCharge: 10 }),
    sale('refund', { total: 90, discount: 10, isRefunded: true })]);
  assert.equal(r.current.gross, 310); assert.equal(r.current.discount, 30);
  assert.equal(r.current.refunds, 90); assert.equal(r.current.net, 190);
  assert.equal(r.current.grossProfit, 120); assert.equal(r.current.service, 10);
  assert.equal(r.current.products.reduce((s, p) => s + p.net, 0), 180);
  assert.equal(r.current.sources.length, 2); assert.equal(r.current.count, 1);
});
test('cent allocation never loses a cent and is deterministic', () => {
  assert.deepEqual(allocate(1, [100, 100, 100]), [1, 0, 0]);
  assert.deepEqual(allocate(100, [0, 1, 2]), [0, 33, 67]);
});
test('missing/zero costs and add-ons prevent full-profit claims', () => {
  for (const missing of [{ costPrice: 0 }, { costKnown: false }, { modifiers: [{ priceAdjust: 0 }] }]) {
    const r = report([sale('mixed', { total: 200, items: [item(), item('b', missing)] })]);
    assert.equal(r.current.grossProfit, null); assert.equal(r.current.costCoverage, 50);
    assert.equal(r.current.partialProfit, 60);
  }
  assert.equal(report([sale('zero', { items: [item('a', { costPrice: 0, costKnown: true })] })]).current.grossProfit, 100);
});
test('historical snapshot cost and category survive catalogue changes', () => {
  const r = report([sale('legacy', { items: [item('a', { category: undefined, costPrice: 12 })] })]);
  assert.equal(r.current.grossProfit, 88); assert.equal(r.current.unknownCategory, 1);
});
test('prior-only products contribute to sales decline', () => {
  const r = report([sale('old', { createdAt: new Date('2026-08-27T08:00:00Z') })]);
  assert.equal(r.change, -100); assert.equal(r.changePercent, -100);
  assert.equal(r.productChanges[0].difference, -100);
});
test('no baseline and empty stores have no invented percentage or margin', () => {
  const r = report([]); assert.equal(r.changePercent, null); assert.equal(r.current.grossProfit, null);
  assert.equal(r.current.daily.length, 7); assert.equal(r.current.daily.reduce((s, d) => s + d.net, 0), 0);
});
test('unlinked paid orders are flagged, never silently added to sale revenue', () => {
  const orders = [sale('linked', { status: 'paid', paidAt: new Date('2026-09-03T08:00:00Z') }),
    sale('pp', { status: 'completed', finalAmount: 100.25 }), sale('pending', { status: 'pendingPayment' }),
    sale('cancel', { status: 'cancelled' }), sale('stripe', { status: 'paid', stripeSessionId: 'session' })];
  const r = report([sale('s', { orderId: 'linked' })], { orders });
  assert.equal(r.current.net, 100); assert.equal(r.current.count, 1); assert.equal(r.current.adjustment, 0);
  assert.equal(r.unlinkedPaidOrderCount, 2);
  assert.equal(r.current.estimatedPaidAt, 0);
});
test('refund belongs to original sale cohort even if refunded later', () => {
  const r = report([sale('ref', { createdAt: new Date('2026-08-27T08:00:00Z'), isRefunded: true, refundedAt: now })]);
  assert.equal(r.previous.refunds, 100); assert.equal(r.current.refunds, 0);
});
test('malformed lines are excluded with a visible quality count', () => {
  const r = report([sale('bad', { items: [item('a', { quantity: -1 })] })]);
  assert.equal(r.current.invalid, 1); assert.equal(r.current.net, 0);
});
test('model receives deterministic numbers without customer data or receipt details', () => {
  const r = report([sale('id-secret', { customerName: 'PRIVATE NAME', customerPhone: 'PRIVATE PHONE' })]);
  const prompt = JSON.stringify(promptData(r));
  assert.ok(!prompt.includes('PRIVATE')); assert.ok(!prompt.includes('id-secret'));
  assert.ok(prompt.includes('grossProfit'));
});
test('all callable endpoints reject anonymous callers before database access', async () => {
  const h = handlers({ db: { collection() { throw Error('database touched'); } } });
  for (const endpoint of ['getSalesAnalysis', 'saveAnalysisContext', 'aiChat']) {
    await assert.rejects(async () => h[endpoint]({ data: {} }), e => e.code === 'unauthenticated');
  }
});
test('invalid windows are rejected rather than silently changed', () => {
  assert.throws(() => daysOf({ days: 365 }), e => e.code === 'invalid-argument');
});
test('recorded add-on costs are included once in gross profit', () => {
  const r = report([sale('egg', { total: 115, items: [item('dish', {
    subtotal: 115, modifiers: [{ priceAdjust: 15, costAdjust: 5 }],
  })] })]);
  assert.equal(r.current.grossProfit, 70);
  assert.equal(r.current.sources[0].items[0].cost, 45);
});
test('web modifier pricing snapshots cost without changing the selling price', () => {
  const { priceLine } = require('./tableorder');
  const line = priceLine({ quantity: 1, optionIds: ['egg'] }, { name: 'rice', price: 50 },
    [{ id: 'g', name: 'extra', options: [{ id: 'egg', name: 'egg', priceAdjust: 10, costAdjust: 3 }] }], now);
  assert.equal(line.unitPrice, 60); assert.equal(line.modifiers[0].costAdjust, 3);
  const tableBase = line.unitPrice - line.modifiers.reduce((s, m) => s + m.priceAdjust, 0);
  assert.equal(tableBase + line.modifiers[0].priceAdjust, 60);
});
