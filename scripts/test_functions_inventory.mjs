// Node tests for functions/inventory.js (weighted-average purchase math +
// per-sale ingredient usage). Run: node scripts/test_functions_inventory.mjs
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { applyPurchase, computeUsage } = require('../functions/inventory.js');

// ── applyPurchase — weighted average ──
// 10 units @ avg 4 + buy 10 for ฿60 (=6/unit) → 20 units @ avg 5
assert.deepEqual(applyPurchase(10, 4, 10, 60), { stock: 20, avgCost: 5 });
// zero starting stock → avg = totalPrice/qty
assert.deepEqual(applyPurchase(0, 0, 30, 120), { stock: 30, avgCost: 4 });
// NEGATIVE starting stock (recount signal) → treat like zero for costing
assert.deepEqual(applyPurchase(-5, 4, 30, 120), { stock: 25, avgCost: 4 });
// fractional units
const fr = applyPurchase(0.5, 100, 1.5, 120);
assert.equal(fr.stock, 2);
assert.ok(Math.abs(fr.avgCost - (0.5 * 100 + 120) / 2) < 1e-9);

// ── computeUsage ──
const productsById = {
  padthai: {
    stockMode: 'recipe',
    recipe: [
      { ingredientId: 'noodle', qty: 120 },   // กรัม/จาน
      { ingredientId: 'egg', qty: 1 },
    ],
  },
  water: { stockMode: 'count' },              // นับสต็อกเอง — ไม่ตัดวัตถุดิบ
  oldproduct: {},                              // ไม่มี stockMode (ร้านเก่า) = count
};
const groupsById = {
  g1: {
    options: [
      { id: 'friedegg', ingredientUsage: [{ ingredientId: 'egg', qty: 1 }] },
      { id: 'spicy' },                         // ไม่ผูกวัตถุดิบ
    ],
  },
};

// 2 จานผัดไทย + เพิ่มไข่ดาว (per unit) + น้ำ 3 ขวด
const usage = computeUsage(
  [
    {
      productId: 'padthai', quantity: 2,
      modifiers: [{ groupId: 'g1', optionId: 'friedegg' }],
    },
    { productId: 'water', quantity: 3 },
    { productId: 'padthai', quantity: 1, modifiers: [{ groupId: 'g1', optionId: 'spicy' }] },
  ],
  productsById,
  groupsById,
);
// noodle: 120×2 + 120×1 = 360 · egg: (recipe 1 + friedegg 1)×2 + recipe 1×1 = 5
assert.deepEqual(usage, { noodle: 360, egg: 5 });

// count-mode only → empty usage
assert.deepEqual(computeUsage([{ productId: 'water', quantity: 5 }], productsById, groupsById), {});

// unknown product / unknown group / unknown option → tolerated silently
assert.deepEqual(
  computeUsage(
    [
      { productId: 'ghost', quantity: 1 },
      { productId: 'padthai', quantity: 1, modifiers: [{ groupId: 'nope', optionId: 'x' }] },
    ],
    productsById, groupsById),
  { noodle: 120, egg: 1 });

// modifiers on a count-mode product still deduct their usage (topping on a
// counted item)
assert.deepEqual(
  computeUsage(
    [{ productId: 'water', quantity: 2, modifiers: [{ groupId: 'g1', optionId: 'friedegg' }] }],
    productsById, groupsById),
  { egg: 2 });

console.log('✓ functions/inventory.js tests passed');
