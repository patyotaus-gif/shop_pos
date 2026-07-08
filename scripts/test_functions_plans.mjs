// Node tests for functions/plans.js (pure plan-catalog helpers).
// Run: node scripts/test_functions_plans.mjs
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { DEFAULT_TIERS, resolvePlanConfig, monthlyRevenueBaht, validateTiers } =
  require('../functions/plans.js');

// ── DEFAULT_TIERS shape (matches the legacy hardcoded PLANS) ──
assert.equal(DEFAULT_TIERS.solo.monthly.amount, 19900);
assert.equal(DEFAULT_TIERS.solo.yearly.amount, 199000);
assert.equal(DEFAULT_TIERS.restaurant.perLocation, true);
assert.equal(DEFAULT_TIERS.full.featured, true);
for (const key of ['solo', 'lite', 'full', 'restaurant']) {
  assert.equal(DEFAULT_TIERS[key].enabled, true);
  assert.equal(DEFAULT_TIERS[key].monthly.days, 30);
  assert.equal(DEFAULT_TIERS[key].yearly.days, 365);
  assert.ok(DEFAULT_TIERS[key].name.length > 0);
}

// ── resolvePlanConfig ──
const solo = resolvePlanConfig(DEFAULT_TIERS, 'solo', 'monthly');
assert.deepEqual(solo, { amount: 19900, days: 30, label: 'Pokpok Solo รายเดือน' });
const fullY = resolvePlanConfig(DEFAULT_TIERS, 'full', 'yearly');
assert.deepEqual(fullY, { amount: 599000, days: 365, label: 'Pokpok Full รายปี' });
// Legacy fallbacks: unknown tier → full; unknown cycle → monthly
assert.equal(resolvePlanConfig(DEFAULT_TIERS, 'nope', 'monthly').amount, 59900);
assert.equal(resolvePlanConfig(DEFAULT_TIERS, 'solo', 'weekly').days, 30);

// ── monthlyRevenueBaht ──
assert.equal(monthlyRevenueBaht(DEFAULT_TIERS, 'full', 'monthly', 1), 599);
assert.ok(Math.abs(monthlyRevenueBaht(DEFAULT_TIERS, 'full', 'yearly', 1) - 5990 / 12) < 1e-9);
assert.equal(monthlyRevenueBaht(DEFAULT_TIERS, 'restaurant', 'monthly', 2), 2398);
assert.equal(monthlyRevenueBaht(DEFAULT_TIERS, 'solo', 'monthly', 5), 199, 'non-perLocation ignores locations');

// ── validateTiers: happy path, sanitization ──
const goodInput = JSON.parse(JSON.stringify(DEFAULT_TIERS));
goodInput.solo.monthly.amount = 24900;
goodInput.solo.name = 'Solo Plus';
goodInput.solo.monthly.days = 9999;          // client may not change days
goodInput.solo.junkField = 'ignore me';      // unknown keys stripped
const clean = validateTiers(goodInput);
assert.equal(clean.solo.monthly.amount, 24900);
assert.equal(clean.solo.name, 'Solo Plus');
assert.equal(clean.solo.monthly.days, 30, 'days forced back to 30');
assert.equal(clean.solo.junkField, undefined, 'unknown keys stripped');
assert.equal(clean.restaurant.perLocation, true, 'perLocation preserved from defaults');
assert.equal(clean.lite.perLocation, undefined, 'perLocation only on restaurant');

// ── validateTiers: rejections ──
const broken = () => JSON.parse(JSON.stringify(DEFAULT_TIERS));
let bad;

bad = broken(); delete bad.full;
assert.throws(() => validateTiers(bad), /full/);

bad = broken(); bad.solo.monthly.amount = 0;
assert.throws(() => validateTiers(bad), /solo/);

bad = broken(); bad.lite.yearly.amount = -5;
assert.throws(() => validateTiers(bad), /lite/);

bad = broken(); bad.full.monthly.amount = 123.45; // must be integer satang
assert.throws(() => validateTiers(bad), /full/);

bad = broken(); bad.solo.name = '';
assert.throws(() => validateTiers(bad), /solo/);

bad = broken(); bad.hacker = { name: 'X', enabled: true, monthly: { amount: 1 }, yearly: { amount: 1 } };
assert.throws(() => validateTiers(bad), /hacker|ไม่รู้จัก/);

assert.throws(() => validateTiers(null));
assert.throws(() => validateTiers('str'));

console.log('✓ functions/plans.js tests passed');
