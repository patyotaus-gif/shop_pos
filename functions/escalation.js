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

// Tenant-isolation guard for the `collectionGroup("orders")` query in
// escalateUnconfirmedOrders. `orders` also exists at
// suppliers/{supplierId}/orders (B2B marketplace dual-write copy) —
// collectionGroup matches both. MarketplaceOrderStatus has no "paid" value
// today, but this guards the path shape anyway so escalation never touches
// a non-shop order doc, no matter how the schema evolves.
//
// @param {string} path - a Firestore document path, e.g. doc.ref.path
// @returns {boolean} true only for shops/{shopId}/orders/{orderId}
function isShopOrderPath(path) {
  const parts = path.split("/");
  return parts.length === 4 && parts[0] === "shops" && parts[2] === "orders";
}

module.exports = {
  ESCALATION_THRESHOLD_MS,
  needsEscalation,
  selectEscalationCandidates,
  isShopOrderPath,
};
