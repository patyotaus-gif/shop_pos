// Node tests for functions/tableorder.js (pure table-order helpers).
// Run: node scripts/test_functions_tableorder.mjs
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { effectivePriceOf, sanitizeTableOrderItems } =
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
assert.deepEqual(good[0], { productId: 'a', quantity: 2, notes: 'ไม่เผ็ด' });
assert.deepEqual(good[1], { productId: 'b', quantity: 1 });

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

console.log('✓ functions/tableorder.js tests passed');
