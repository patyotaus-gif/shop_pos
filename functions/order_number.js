'use strict';

// Allocated with the order in one transaction. Never use this display number
// for authorization, document IDs, or payment idempotency.
async function prepare(tx, shopRef, now = Date.now()) {
  const date = new Date(now + 7 * 60 * 60 * 1000).toISOString().slice(0, 10).replaceAll('-', '');
  const ref = shopRef.collection('orderCounters').doc(date);
  const prior = (await tx.get(ref)).data()?.last ?? 0;
  if (!Number.isSafeInteger(prior) || prior < 0 || prior >= Number.MAX_SAFE_INTEGER - 1)
    throw Error('Invalid order sequence');
  const next = prior + 1;
  return {number: `${date}-${String(next).padStart(3, '0')}`,
    write: () => tx.set(ref, {last: next})};
}
module.exports = {prepare};
