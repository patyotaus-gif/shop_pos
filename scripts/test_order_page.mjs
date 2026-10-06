// Node smoke tests for the order-page ES modules (no browser needed).
// Run: node scripts/test_order_page.mjs
import assert from 'node:assert/strict';

const { escHtml, fmtBaht, shopId } = await import('../public/order/js/util.js?v=20261007');
const cartMod = await import('../public/order/js/cart.js?v=20261007');

// ── util.js ──
assert.equal(escHtml('a<b>&"c'), 'a&lt;b&gt;&amp;&quot;c');
assert.equal(fmtBaht(10), '฿10.00');
assert.equal(fmtBaht(1.5), '฿1.50');
assert.equal(shopId, null); // no `location` in Node

// ── cart.js state ──
const { setQty, addOne, getQty, items, count, total, onCartChange } = cartMod;
let changes = 0;
onCartChange(() => changes++);

addOne('p1', { name: 'มาม่า', price: 10, stock: 3 });
assert.equal(getQty('p1'), 1);
addOne('p1', { name: 'มาม่า', price: 10, stock: 3 });
addOne('p1', { name: 'มาม่า', price: 10, stock: 3 });
addOne('p1', { name: 'มาม่า', price: 10, stock: 3 }); // 4th add — clamped
assert.equal(getQty('p1'), 3, 'addOne clamps at stock');

setQty('p2', 5, { name: 'น้ำปลา', price: 25, stock: 2 });
assert.equal(getQty('p2'), 2, 'setQty clamps at stock');

assert.equal(count(), 5);
assert.equal(total(), 3 * 10 + 2 * 25);

setQty('p2', 0);
assert.equal(getQty('p2'), 0);
assert.equal(items().length, 1, 'qty 0 removes the item');

assert.ok(changes >= 5, 'listeners fire on every change');

// ── cart.js line identity (add-ons) ──
const { addLine, lineKey } = cartMod;
setQty('p1', 0); // clear
assert.equal(items().length, 0);

// same product, different option sets → separate lines
addLine({ id: 'd', name: 'ข้าวผัด', price: 60, stock: 10,
  optionIds: ['egg'], modifiers: [{ optionName: 'ไข่ดาว' }], notes: 'ไม่ผัก' }, 1);
addLine({ id: 'd', name: 'ข้าวผัด', price: 50, stock: 10,
  optionIds: [], modifiers: [], notes: '' }, 2);
assert.equal(items().length, 2, 'different options → separate lines');
assert.equal(getQty('d'), 3, 'getQty sums across a product\'s lines');
assert.equal(total(), 60 * 1 + 50 * 2);

// Re-adding the same options AND note merges into the same line.
addLine({ id: 'd', name: 'ข้าวผัด', price: 60, stock: 10, optionIds: ['egg'],
  modifiers: [{ optionName: 'ไข่ดาว' }], notes: 'ไม่ผัก' }, 1);
assert.equal(items().length, 2, 'same options merge');
assert.equal(getQty('d'), 4);

// lineKey order-independent
assert.equal(lineKey('x', ['b', 'a']), lineKey('x', ['a', 'b']));
assert.notEqual(lineKey('x', [], 'ไม่เผ็ด'), lineKey('x', [], 'เผ็ดมาก'));

// stock cap across lines
addLine({ id: 'd', name: 'ข้าวผัด', price: 50, stock: 10, optionIds: [] }, 100);
assert.equal(getQty('d'), 10, 'total product qty capped at stock');

console.log('✓ util.js + cart.js tests passed');

// ── catalog.js promoInfo ──
const { promoInfo } = await import('../public/order/js/catalog.js?v=20261007');

assert.deepEqual(promoInfo(10, 20), { percent: 50, saving: 10 });
assert.deepEqual(promoInfo(1.25, 3), { percent: 58, saving: 1.75 });
assert.equal(promoInfo(10, undefined), null, 'no originalPrice → no promo');
assert.equal(promoInfo(10, 0), null);
assert.equal(promoInfo(20, 20), null, 'equal price → no promo');
assert.equal(promoInfo(25, 20), null, 'originalPrice below price → no promo');
assert.equal(promoInfo(996, 1000), null, 'rounds to 0% → no badge');

console.log('✓ catalog.js promoInfo tests passed');

// ── payment.js — PromptPay payload (moved verbatim; verify it still works) ──
const { crc16, buildPromptPayPayload } = await import('../public/order/js/payment.js?v=20261007');

// CRC-16/CCITT-FALSE known-answer test
assert.equal(crc16('123456789'), '29B1');

// Phone (10 digits) → tag 01, 0066 + drop leading 0
const phone = buildPromptPayPayload('081-234-5678', 100);
assert.ok(phone.startsWith('000201010212'), 'static header + dynamic (amount) type');
assert.ok(phone.includes('0016A000000677010111'), 'PromptPay AID');
assert.ok(phone.includes('01130066812345678'), 'phone proxy value');
assert.ok(phone.includes('5802TH'), 'country TH');
assert.ok(phone.includes('5303764'), 'currency 764');
assert.ok(phone.includes('5406100.00'), 'amount 100.00');
assert.match(phone, /6304[0-9A-F]{4}$/, 'trailing CRC');

// National ID (13 digits) → tag 02
const nid = buildPromptPayPayload('1234567890123', 50);
assert.ok(nid.includes('02131234567890123'), 'national-id proxy');

// Invalid length throws
assert.throws(() => buildPromptPayPayload('12345', 10));

console.log('✓ payment.js PromptPay tests passed');

// ── catalog.js filterByCategory ──
const { filterByCategory } = await import('../public/order/js/catalog.js?v=20261007');
const prods = [
  { id: '1', category: 'เครื่องดื่ม' },
  { id: '2', category: 'ของทานเล่น' },
  { id: '3', category: '' },
];
assert.equal(filterByCategory(prods, 'ทั้งหมด').length, 3);
assert.deepEqual(filterByCategory(prods, 'เครื่องดื่ม').map(p => p.id), ['1']);
assert.deepEqual(filterByCategory(prods, 'ทั่วไป').map(p => p.id), ['3'], 'empty category groups as ทั่วไป');

// ── upsell.js pickUpsell ──
const { pickUpsell } = await import('../public/order/js/upsell.js?v=20261007');
const menu = [
  { id: 'a', stock: 5, pinned: true },
  { id: 'b', stock: 5, originalPrice: 20, price: 10 },
  { id: 'c', stock: 5 },                          // ไม่ปักหมุด ไม่มีโปร → ไม่แนะนำ
  { id: 'd', stock: 0, pinned: true },            // หมด → ไม่แนะนำ
  { id: 'e', stock: 5, pinned: true },
  { id: 'f', stock: 5, originalPrice: 9, price: 5 },
  { id: 'g', stock: 5, pinned: true },
];
const picks = pickUpsell(menu, ['e']);            // e อยู่ในตะกร้าแล้ว
assert.equal(picks.length, 4, 'capped at 4');
assert.ok(!picks.some(p => p.id === 'c' || p.id === 'd' || p.id === 'e'));
assert.ok(picks[0].pinned && picks[1].pinned, 'pinned first');
assert.deepEqual(pickUpsell([{ id: 'x', stock: 3 }], []), [], 'no candidates');

console.log('✓ category filter + upsell picker tests passed');

// Regression: instructions, required choices, aggregate stock and draft reload.
const { clearCart } = cartMod;
clearCart();
addLine({ id: 'food', name: 'ข้าว', price: 50, stock: 3, optionIds: ['egg'], notes: 'ไม่เผ็ด' }, 1);
addLine({ id: 'food', name: 'ข้าว', price: 50, stock: 3, optionIds: ['egg'], notes: 'เผ็ดมาก' }, 1);
assert.equal(items().length, 2);
addOne('food', { name: 'ข้าว', price: 40, stock: 3 });
addOne('food', { name: 'ข้าว', price: 40, stock: 3 });
assert.equal(getQty('food'), 3, 'plain + configured lines share stock cap');
clearCart();
assert.equal(items().length, 0, 'clear includes configured lines');

const { filterProducts, needsOptions } = await import('../public/order/js/catalog.js?v=20261007');
assert.equal(filterProducts([{ name: 'ชาเขียว', category: ' เครื่องดื่ม ' }], 'เครื่องดื่ม', 'ชา เขียว').length, 1);
assert.equal(filterProducts([{ name: 'ชาเขียว', category: 'เครื่องดื่ม' }], 'ทั้งหมด', 'ข้าว').length, 0);
assert.equal(needsOptions({ modifierGroups: [{ required: true }] }), true);
assert.equal(pickUpsell([{ id: 'a', stock: 3, pinned: true, modifierGroups: [{ required: true }] }], []).length, 0);

const { restoreDraft, initCartPersistence, cartStorageKey } = await import('../public/order/js/cart-store.js?v=20261007');
const menuNow = [{ id: 'food', name: 'new name', price: 55, stock: 2,
  modifierGroups: [{ id: 'protein', name: 'เนื้อ', required: true, multiSelect: false,
    options: [{ id: 'egg', name: 'ไข่', priceAdjust: 5 }] }] }];
const draft = (lines, at = 1000) => JSON.stringify({ at, lines });
restoreDraft(draft([{ id: 'food', price: 1, quantity: 9, optionIds: ['egg'], notes: 'ไม่เผ็ด' }]), menuNow, 1001);
assert.equal(count(), 2, 'restore clamps to latest stock');
assert.equal(total(), 120, 'restore reprices from current catalog, not stored price');
assert.equal(items()[0].name, 'new name');
clearCart();
restoreDraft(draft([{ id: 'food', quantity: 1, optionIds: [], notes: '' }]), menuNow, 1001);
restoreDraft(draft([{ id: 'food', quantity: 1, optionIds: ['removed'], notes: '' }]), menuNow, 1001);
restoreDraft(draft([{ id: 'food', quantity: 1, optionIds: ['egg'], notes: '' }]), menuNow, 8000000);
restoreDraft('{broken', menuNow);
assert.equal(count(), 0, 'invalid, obsolete and expired drafts never enter cart');
const store = new Map();
const storage = { getItem: k => store.get(k), setItem: (k,v) => store.set(k,v), removeItem: k => store.delete(k) };
let detach = initCartPersistence({ shop: 's', mode: 'dineIn', table: 't1', products: menuNow, storage });
addLine({ ...menuNow[0], optionIds: ['egg'], notes: 'ไม่เผ็ด' }, 1);
detach();
detach = initCartPersistence({ shop: 's', mode: 'dineIn', table: 't1', products: menuNow, storage });
assert.equal(count(), 1, 'same table draft restored');
clearCart();
assert.equal(store.has(cartStorageKey('s','dineIn','t1')), false, 'sent cart removed from storage');
detach();
assert.notEqual(cartStorageKey('s','dineIn','t1'), cartStorageKey('s','dineIn','t2'));
assert.notEqual(cartStorageKey('s','normal'), cartStorageKey('other','normal'));
assert.doesNotThrow(() => initCartPersistence({ shop:'s', mode:'normal', products:menuNow,
  storage: { getItem(){throw Error('private mode');}, removeItem(){throw Error('private mode');} } }));
console.log('✓ notes, stock, search, required choices and cart persistence regressions passed');
