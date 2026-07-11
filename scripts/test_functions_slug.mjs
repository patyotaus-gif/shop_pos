// Node tests for functions/slug.js (pure slug normalize/validate).
// Run: node scripts/test_functions_slug.mjs
import assert from 'node:assert/strict';
import { createRequire } from 'node:module';

const require = createRequire(import.meta.url);
const { normalizeSlug, validateSlug } = require('../functions/slug.js');

// ── normalizeSlug ──
assert.equal(normalizeSlug('Somtam Jay Lek'), 'somtam-jay-lek');
assert.equal(normalizeSlug('  MyShop  '), 'myshop');
assert.equal(normalizeSlug('a__b   c'), 'a-b-c', 'runs of space/underscore → single -');
assert.equal(normalizeSlug('café-ร้าน!!'), 'caf', 'non-ascii + punctuation stripped');
assert.equal(normalizeSlug('--lead--trail--'), 'lead-trail', 'trim + collapse hyphens');
assert.equal(normalizeSlug('UPPER123'), 'upper123');
assert.equal(normalizeSlug('***'), '', 'all-invalid → empty');

// ── validateSlug ──
assert.equal(validateSlug('somtam-jay'), 'somtam-jay');
assert.equal(validateSlug('abc'), 'abc', 'min length 3');
assert.equal(validateSlug('a'.repeat(30)), 'a'.repeat(30), 'max length 30');

assert.throws(() => validateSlug('ab'), /3/, 'too short');
assert.throws(() => validateSlug('a'.repeat(31)), /30/, 'too long');
assert.throws(() => validateSlug(''), /3/, 'empty');
for (const w of ['order', 'api', 'app', 'r', 'admin', 'subscribe', 'blog']) {
  assert.throws(() => validateSlug(w), /สงวน|ใช้ไม่ได้/, `reserved: ${w}`);
}

// end-to-end: normalize then validate
assert.equal(validateSlug(normalizeSlug('My Shop 99')), 'my-shop-99');

console.log('✓ functions/slug.js tests passed');
