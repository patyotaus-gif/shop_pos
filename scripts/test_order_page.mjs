// Node smoke tests for the order-page ES modules (no browser needed).
// Run: node scripts/test_order_page.mjs
import assert from 'node:assert/strict';

const { escHtml, fmtBaht, shopId } = await import('../public/order/js/util.js');
const cartMod = await import('../public/order/js/cart.js');

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

console.log('✓ util.js + cart.js tests passed');

// ── catalog.js promoInfo ──
const { promoInfo } = await import('../public/order/js/catalog.js');

assert.deepEqual(promoInfo(10, 20), { percent: 50, saving: 10 });
assert.deepEqual(promoInfo(1.25, 3), { percent: 58, saving: 1.75 });
assert.equal(promoInfo(10, undefined), null, 'no originalPrice → no promo');
assert.equal(promoInfo(10, 0), null);
assert.equal(promoInfo(20, 20), null, 'equal price → no promo');
assert.equal(promoInfo(25, 20), null, 'originalPrice below price → no promo');
assert.equal(promoInfo(996, 1000), null, 'rounds to 0% → no badge');

console.log('✓ catalog.js promoInfo tests passed');

// ── payment.js — PromptPay payload (moved verbatim; verify it still works) ──
const { crc16, buildPromptPayPayload } = await import('../public/order/js/payment.js');

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
const { filterByCategory } = await import('../public/order/js/catalog.js');
const prods = [
  { id: '1', category: 'เครื่องดื่ม' },
  { id: '2', category: 'ของทานเล่น' },
  { id: '3', category: '' },
];
assert.equal(filterByCategory(prods, 'ทั้งหมด').length, 3);
assert.deepEqual(filterByCategory(prods, 'เครื่องดื่ม').map(p => p.id), ['1']);
assert.deepEqual(filterByCategory(prods, 'ทั่วไป').map(p => p.id), ['3'], 'empty category groups as ทั่วไป');

// ── upsell.js pickUpsell ──
const { pickUpsell } = await import('../public/order/js/upsell.js');
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
