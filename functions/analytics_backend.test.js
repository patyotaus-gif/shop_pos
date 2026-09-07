const { test } = require('node:test');
const assert = require('node:assert/strict');
const { handlers } = require('./sales_assistant');
function database() {
  const yesterday = new Date(Date.now() - 2 * 86400000);
  const docs = new Map([
    ['shops/owner', { subscriptionStatus: 'active', subscriptionEndsAt: { toDate: () => new Date(Date.now() + 86400000) } }],
    ['shops/owner/settings/analysis', { timeZone: 'Asia/Bangkok', openWeekdays: [1] }],
    ['shops/owner/sales/bill', { createdAt: yesterday, total: 80, items: [{ productId: 'rice', productName: 'rice', quantity: 1, subtotal: 80, costPrice: 30 }] }],
    ['shops/other/sales/private', { createdAt: yesterday, total: 999999 }],
  ]);
  const accesses = [];
  const value = v => v?.toDate ? +v.toDate() : v instanceof Date ? +v : v;
  function ref(path, filters = [], max = Infinity) {
    return { path, id: path.split('/').at(-1),
      collection: c => ref(`${path}/${c}`), doc: d => ref(`${path}/${d}`),
      where: (f, op, v) => ref(path, [...filters, [f, op, v]], max), limit: n => ref(path, filters, n),
      get: async () => {
        accesses.push(path);
        if (path.split('/').length % 2 === 0) return { exists: docs.has(path), data: () => docs.get(path) };
        const found = [...docs].filter(([p, d]) => p.startsWith(`${path}/`) && p.split('/').length === path.split('/').length + 1 &&
          filters.every(([f, op, v]) => d[f] != null && (op === '>=' ? value(d[f]) >= value(v) : value(d[f]) <= value(v)))).slice(0, max)
          .map(([p, d]) => ({ id: p.split('/').at(-1), data: () => d }));
        return { size: found.length, docs: found };
      },
      set: async (d, options) => docs.set(path, options?.merge ? { ...docs.get(path), ...d } : d),
    };
  }
  let queue = Promise.resolve();
  const db = { collection: c => ref(c), runTransaction: action => {
    const pending = queue.then(() => action({ get: r => r.get(), set: (r, d, o) => r.set(d, o), delete: r => docs.delete(r.path) }));
    queue = pending.catch(() => {}); return pending;
  }, batch: () => {
    const writes = []; return { set: (r, d) => writes.push(() => r.set(d)), commit: () => Promise.all(writes.map(w => w())) };
  } };
  return { db, docs, accesses };
}
test('report ignores forged shop ID and loads only authenticated owner data', async () => {
  const f = database(); const h = handlers({ db: f.db });
  const r = await h.getSalesAnalysis({ auth: { uid: 'owner' }, data: { shopId: 'other', days: 7 } });
  assert.equal(r.current.net, 80);
  assert.ok(f.accesses.every(p => p.startsWith('shops/owner')));
  assert.equal(r.current.sources[0].id, 'bill');
});
test('AI uses server-calculated evidence, not forged client context, and returns that evidence', async () => {
  const f = database(); const h = handlers({ db: f.db, apiKey: () => 'test-key', model: 'test' });
  const original = global.fetch; let body;
  global.fetch = async (_, options) => { body = JSON.parse(options.body); return { ok: true, json: async () => ({ candidates: [{ content: { parts: [{ text: 'ยอดสุทธิ 80 บาท' }] } }] }) }; };
  try {
    const r = await h.aiChat({ auth: { uid: 'owner' }, data: { days: 7, shopContext: 'FORGED 999999', history: [{ role: 'user', content: 'สรุปยอด' }] } });
    assert.equal(r.analysis.current.net, 80); assert.equal(r.usage.dailyCount, 1);
    assert.ok(!JSON.stringify(body).includes('FORGED'));
    assert.ok(JSON.stringify(body).includes('grossProfit'));
  } finally { global.fetch = original; }
});
test('provider failure releases reserved quota and returns actionable error', async () => {
  const f = database(); const h = handlers({ db: f.db, apiKey: () => 'test', model: 'test' });
  const original = global.fetch; global.fetch = async () => { throw Error('network error'); };
  try {
    await assert.rejects(h.aiChat({ auth: { uid: 'owner' }, data: { days: 7, history: [{ role: 'user', content: 'สรุป' }] } }), e => e.code === 'unavailable');
    const usage = [...f.docs].find(([p]) => p.includes('/aiUsage/'));
    assert.equal(usage[1].count, 0);
  } finally { global.fetch = original; }
});
test('manual context validation and retry use a stable ID; system events cannot be deleted', async () => {
  const f = database(); const h = handlers({ db: f.db });
  const request = { auth: { uid: 'owner' }, data: { id: 'stable-event-123', type: 'closed', startDay: '2026-09-01', endDay: '2026-09-02', note: 'ปิดซ่อมร้าน' } };
  await h.saveAnalysisContext(request); await h.saveAnalysisContext(request);
  assert.equal([...f.docs.keys()].filter(p => p.includes('/analyticsEvents/')).length, 1);
  await assert.rejects(h.saveAnalysisContext({ ...request, data: { ...request.data, startDay: '2026-02-31' } }), e => e.code === 'invalid-argument');
  f.docs.set('shops/owner/analyticsEvents/auto-1', { source: 'system' });
  await assert.rejects(h.saveAnalysisContext({ auth: request.auth, data: { deleteId: 'auto-1' } }), e => e.code === 'permission-denied');
});
test('product events are idempotent and distinguish restock from stockout', async () => {
  const f = database(); const h = handlers({ db: f.db });
  const event = { id: 'event-1', params: { shopId: 'owner', productId: 'p' }, data: {
    before: { data: () => ({ name: 'rice', stock: 2 }) },
    after: { data: () => ({ name: 'rice', stock: 0 }), updateTime: new Date() },
  } };
  await h.recordProductAnalytics(event); await h.recordProductAnalytics(event);
  const events = [...f.docs].filter(([p]) => p.includes('/analyticsEvents/'));
  assert.equal(events.length, 1); assert.equal(events[0][1].type, 'stockout');
});
