// Pure staleness filter for Feature B (escalate unconfirmed paid orders).
// Kept dependency-free from Firestore so it's directly unit-testable —
// see escalation.test.js. Callers convert Firestore Timestamps to plain
// millisecond numbers before calling in.
const ESCALATION_THRESHOLD_MS = 5 * 60 * 1000;

/**
 * @param {{status: string, paidAtMs: number|null|undefined, escalatedAt: any}} order
 * @param {number} nowMs
 * @param {number} [thresholdMs]
 * @returns {boolean}
 */
function needsEscalation(order, nowMs, thresholdMs = ESCALATION_THRESHOLD_MS) {
  if (order.status !== "paid") return false;
  if (order.escalatedAt) return false;
  if (typeof order.paidAtMs !== "number") return false;
  return nowMs - order.paidAtMs >= thresholdMs;
}

/**
 * @param {Array<{status: string, paidAtMs: number|null|undefined, escalatedAt: any}>} orders
 * @param {number} nowMs
 * @param {number} [thresholdMs]
 */
function selectEscalationCandidates(orders, nowMs, thresholdMs = ESCALATION_THRESHOLD_MS) {
  return orders.filter((o) => needsEscalation(o, nowMs, thresholdMs));
}

module.exports = { ESCALATION_THRESHOLD_MS, needsEscalation, selectEscalationCandidates };
