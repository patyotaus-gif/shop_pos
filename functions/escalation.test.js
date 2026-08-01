// Plain node:assert test — this repo has no jest/mocha. Run directly:
//   node functions/escalation.test.js
const assert = require("node:assert/strict");
const {
  ESCALATION_THRESHOLD_MS,
  needsEscalation,
  selectEscalationCandidates,
} = require("./escalation");

const NOW = Date.parse("2026-08-01T12:00:00Z");

function order(overrides) {
  return {
    status: "paid",
    paidAtMs: NOW - ESCALATION_THRESHOLD_MS,
    escalatedAt: null,
    ...overrides,
  };
}

// Paid exactly at the threshold, never escalated → escalate.
assert.equal(
  needsEscalation(order({}), NOW),
  true,
  "order paid exactly 5 min ago should escalate"
);

// Staff confirms at 4:59 — still under threshold, no escalation yet.
assert.equal(
  needsEscalation(order({ paidAtMs: NOW - ESCALATION_THRESHOLD_MS + 1000 }), NOW),
  false,
  "order paid 4:59 ago should not escalate yet"
);

// Already escalated — no-op regardless of elapsed time.
assert.equal(
  needsEscalation(order({ escalatedAt: NOW - 1000 }), NOW),
  false,
  "already-escalated order should be skipped"
);

// Any non-paid status (e.g. cancelled before hitting the threshold) is excluded.
assert.equal(
  needsEscalation(order({ status: "cancelled" }), NOW),
  false,
  "non-paid status should never escalate"
);

// Defensive: an order with no paidAt should never escalate.
assert.equal(
  needsEscalation(order({ paidAtMs: undefined }), NOW),
  false,
  "order with no paidAt should not escalate"
);

// selectEscalationCandidates filters a mixed batch down to just the due one.
const dueOrder = order({});
const notDueOrder = order({ paidAtMs: NOW - 60000 });
const alreadyDone = order({ escalatedAt: NOW - 1000 });
assert.deepEqual(
  selectEscalationCandidates([dueOrder, notDueOrder, alreadyDone], NOW),
  [dueOrder],
  "selectEscalationCandidates should return only the due order"
);

console.log("escalation.test.js: all assertions passed");
