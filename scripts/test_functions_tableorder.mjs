// Node tests for functions/tableorder.js (pure table-order helpers).
// Run: node scripts/test_functions_tableorder.mjs
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { effectivePriceOf, sanitizeTableOrderItems, priceLine } =
  require('../functions/tableorder.js');

const now = new Date('2026-07-09T12:00:00Z');

// ── effectivePriceOf — mirrors Dart Product.effectivePrice ──
assert.equal(effectivePriceOf({ price: 20 }, now), 20);
assert.equal(
  effectivePriceOf({ price: 20, salePrice: 10 }, now), 10,
  'sale without expiry');
assert.equal(
  effectivePriceOf({ price: 20, salePrice: 10,
    saleUntil: { toDate: () => new Date('2026-07-10T00:00:00Z') } }, now),
  10, 'active sale (Timestamp-like)');
assert.equal(
  effectivePriceOf({ price: 20, salePrice: 10,
    saleUntil: { toDate: () => new Date('2026-07-01T00:00:00Z') } }, now),
  20, 'expired sale');
assert.equal(effectivePriceOf({ price: 20, salePrice: 0 }, now), 20, 'zero sale ignored');
assert.equal(effectivePriceOf({ price: 20, salePrice: 25 }, now), 20, 'sale >= price ignored');

// ── sanitizeTableOrderItems ──
const good = sanitizeTableOrderItems([
  { productId: 'a', quantity: 2, notes: ' ไม่เผ็ด ' },
  { productId: 'b', quantity: 1 },
]);
assert.equal(good.length, 2);
assert.deepEqual(good[0], { productId: 'a', quantity: 2, optionIds: [], notes: 'ไม่เผ็ด' });
assert.deepEqual(good[1], { productId: 'b', quantity: 1, optionIds: [] });

// optionIds carried + sanitized (non-strings dropped, trimmed)
assert.deepEqual(
  sanitizeTableOrderItems([{ productId: 'a', quantity: 1, optionIds: [' o1 ', 2, 'o2'] }])[0].optionIds,
  ['o1', 'o2']);

assert.deepEqual(
  sanitizeTableOrderItems([{ productId: 'a', quantity: 500 }])[0].quantity,
  99, 'qty clamped to 99');

assert.throws(() => sanitizeTableOrderItems([]), /รายการ/);
assert.throws(() => sanitizeTableOrderItems('x'), /รายการ/);
assert.throws(
  () => sanitizeTableOrderItems([{ productId: '', quantity: 1 }]), /สินค้า/);
assert.throws(
  () => sanitizeTableOrderItems([{ productId: 'a', quantity: 0 }]), /จำนวน/);
assert.throws(
  () => sanitizeTableOrderItems([{ productId: 'a', quantity: 1.5 }]), /จำนวน/);
assert.throws(
  () => sanitizeTableOrderItems(
    Array.from({ length: 21 }, (_, i) => ({ productId: `p${i}`, quantity: 1 }))),
  /20/, 'more than 20 lines rejected');

// notes longer than 200 chars trimmed
const longNote = sanitizeTableOrderItems(
  [{ productId: 'a', quantity: 1, notes: 'x'.repeat(500) }]);
assert.equal(longNote[0].notes.length, 200);

// ── priceLine — server-side modifier pricing/validation ──
const product = { name: 'ข้าวผัด', price: 50 };
const groups = [
  { id: 'g1', name: 'ความเผ็ด', required: true, multiSelect: false,
    options: [ { id: 's0', name: 'ไม่เผ็ด', priceAdjust: 0 },
               { id: 's2', name: 'เผ็ดมาก', priceAdjust: 0 } ] },
  { id: 'g2', name: 'เพิ่มเติม', required: false, multiSelect: true,
    options: [ { id: 'egg', name: 'ไข่ดาว', priceAdjust: 10 },
               { id: 'norice', name: 'ไม่เอาข้าว', priceAdjust: -5 } ] },
];

// happy path: required picked + one add-on
const line = priceLine(
  { productId: 'p', quantity: 2, optionIds: ['s2', 'egg'], notes: 'ด่วน' },
  product, groups, now);
assert.equal(line.basePrice, 50);
assert.equal(line.unitPrice, 60, 'base 50 + egg 10');
assert.equal(line.quantity, 2);
assert.equal(line.notes, 'ด่วน');
assert.equal(line.modifiers.length, 2);
assert.deepEqual(
  line.modifiers.map((m) => m.optionId).sort(), ['egg', 's2']);

// negative adjust supported, unit price floored at 0
assert.equal(
  priceLine({ productId: 'p', quantity: 1, optionIds: ['s0', 'norice'] },
    { name: 'x', price: 3 }, groups, now).unitPrice, 0, 'floored at 0');

// sale price honored as base
assert.equal(
  priceLine({ productId: 'p', quantity: 1, optionIds: ['s0'] },
    { name: 'x', price: 50, salePrice: 40 }, groups, now).unitPrice, 40);

// unknown option → throw
assert.throws(
  () => priceLine({ productId: 'p', quantity: 1, optionIds: ['nope'] },
    product, groups, now), /ตัวเลือกไม่ถูกต้อง/);

// required group unmet → throw
assert.throws(
  () => priceLine({ productId: 'p', quantity: 1, optionIds: [] },
    product, groups, now), /ความเผ็ด/);

// radio group with 2 picks → throw
assert.throws(
  () => priceLine({ productId: 'p', quantity: 1, optionIds: ['s0', 's2'] },
    product, groups, now), /ความเผ็ด/);

// no groups + no options → plain line, base price
assert.equal(
  priceLine({ productId: 'p', quantity: 1, optionIds: [] },
    { name: 'น้ำเปล่า', price: 15 }, [], now).unitPrice, 15);

console.log('✓ functions/tableorder.js tests passed');
