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
