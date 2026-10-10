'use strict';
// Operator-only maintenance; never exported as a callable or run on import.
// Use only after the owner confirms the exact manifest is test data with no
// real payment. Originals are archived atomically, not rewritten as refunds.
const crypto = require('node:crypto');
const assert = require('node:assert/strict');
const {inspectMovementRows} = require('../functions/cash_integrity');

function fingerprint(value) {
  const normalize = v => Array.isArray(v) ? v.map(normalize) : v && typeof v === 'object'
    ? Object.fromEntries(Object.keys(v).sort().map(k => [k, normalize(v[k])])) : v;
  return crypto.createHash('sha256').update(JSON.stringify(normalize(JSON.parse(JSON.stringify(value))))).digest('hex');
}
function validId(id) { return typeof id === 'string' && /^[\w-]{1,150}$/.test(id); }

async function archiveTestOrders({db, FieldValue, manifest, apply = false}) {
  const {shopId, correctionId, sessionId, entries, totalMinor, reason, operator, confirmedBy} = manifest;
  assert(validId(shopId) && validId(correctionId) && validId(sessionId));
  assert.equal(confirmedBy, shopId, 'Owner confirmation required');
  assert(typeof reason === 'string' && reason.trim().length > 10);
  assert(typeof operator === 'string' && operator.trim());
  assert.equal(manifest.actualMoneyReceivedMinor, 0);
  assert(Array.isArray(entries) && entries.length > 0 && entries.length <= 50);
  assert.equal(new Set(entries.map(e => e.orderId)).size, entries.length);
  assert(entries.every(e => validId(e.orderId) && Number.isSafeInteger(e.amountMinor) && e.amountMinor > 0 && /^[a-f0-9]{64}$/.test(e.fingerprint)));
  assert.equal(entries.reduce((n, e) => n + e.amountMinor, 0), totalMinor);
  const manifestHash = fingerprint(manifest);
  const shop = db.collection('shops').doc(shopId);
  const auditRef = shop.collection('accountingCorrections').doc(correctionId);
  return db.runTransaction(async tx => {
    const audit = await tx.get(auditRef);
    if (audit.exists) {
      assert.equal(audit.data().manifestHash, manifestHash, 'Correction ID already used');
      return {alreadyApplied: true, count: entries.length, totalMinor, manifestHash};
    }
    const controlRef = shop.collection('cashControl').doc('current');
    const control = await tx.get(controlRef);
    assert.equal(control.data()?.sessionId, sessionId, 'Round changed; recheck before proceeding');
    const session = await tx.get(shop.collection('cashSessions').doc(sessionId));
    assert.equal(session.data()?.status, 'open');
    const records = [];
    for (const e of entries) {
      const orderRef = shop.collection('orders').doc(e.orderId);
      const saleRef = shop.collection('sales').doc('order-' + e.orderId);
      const movementRef = shop.collection('moneyMovements').doc('sale-' + saleRef.id);
      const [order, sale, movement, linkedSales, linkedMovements, debts, priorArchive] = await Promise.all([
        tx.get(orderRef), tx.get(saleRef), tx.get(movementRef),
        tx.get(shop.collection('sales').where('orderId', '==', e.orderId).limit(2)),
        tx.get(shop.collection('moneyMovements').where('saleId', '==', saleRef.id).limit(2)),
        tx.get(shop.collection('debts').where('saleId', '==', saleRef.id).limit(1)),
        tx.get(auditRef.collection('records').doc(e.orderId)),
      ]);
      assert(order.exists && sale.exists && movement.exists, 'Missing source');
      assert(!priorArchive.exists && debts.empty);
      assert.equal(linkedSales.size, 1); assert.equal(linkedMovements.size, 1);
      const originals = {order: order.data(), sale: sale.data(), movement: movement.data()};
      assert.equal(fingerprint(originals), e.fingerprint, 'Source changed: ' + e.orderId);
      const {order: o, sale: s, movement: m} = originals;
      assert.equal(o.status, 'completed'); assert.equal(o.saleId, saleRef.id);
      assert.equal(s.orderId, e.orderId);
      assert(!s.isDebt && !s.isRefunded && !s.refundedAt && !s.customerId);
      assert(!s.stripePaymentIntentId && !o.stripeSessionId && !o.inventoryReservation);
      assert.deepEqual(s.stockDeducted, {});
      assert.equal(Object.keys(s.ingredientUsage || {}).length, 0);
      assert.equal(m.kind, 'sale'); assert.equal(m.method, 'qr');
      assert.equal(m.sessionId, null); assert.equal(m.needsReconciliation, true);
      assert.equal(m.amountMinor, e.amountMinor); assert.equal(m.salesMinor, e.amountMinor);
      assert.equal(m.debtMinor, 0); assert.equal(m.refundMinor || 0, 0);
      assert.deepEqual(await inspectMovementRows(tx, shop, [movement]), []);
      // This narrow repair cannot guess inventory or loyalty adjustments.
      // Reject if a product still exists (including pending ingredient triggers).
      for (const id of new Set((s.items || []).map(i => i.productId))) {
        assert(validId(id));
        assert(!(await tx.get(shop.collection('products').doc(id))).exists, 'Inventory requires separate review');
      }
      records.push({e, orderRef, saleRef, movementRef, originals});
    }
    if (apply) {
      const at = FieldValue.serverTimestamp();
      tx.create(auditRef, {schemaVersion: 1, kind: 'archiveConfirmedTestOrders', manifestHash,
        manifest, createdAt: at, actualMoneyReceivedMinor: 0, actualRefundMinor: 0,
        count: entries.length, excludedTestAmountMinor: totalMinor});
      for (const r of records) {
        tx.create(auditRef.collection('records').doc(r.e.orderId), {
          ...r.originals, sourceFingerprint: r.e.fingerprint,
          sourcePaths: [r.orderRef.path, r.saleRef.path, r.movementRef.path], archivedAt: at,
        });
        tx.update(r.orderRef, {status: 'cancelled', cancelReason: reason, statusUpdatedAt: at,
          statusUpdatedBy: confirmedBy, isTestOrder: true,
          accountingCorrectionId: correctionId, archivedSaleId: r.saleRef.id,
          saleId: FieldValue.delete(), paidAt: FieldValue.delete(),
          paymentRef: FieldValue.delete(), autoConfirmed: false});
        // Full originals above stay in Firestore. Removing only these active
        // projections keeps older app reports correct without invented refunds.
        tx.delete(r.saleRef); tx.delete(r.movementRef);
      }
      tx.update(controlRef, {revision: FieldValue.increment(1)});
    }
    return {alreadyApplied: false, applied: apply, count: entries.length, totalMinor, manifestHash};
  });
}
module.exports = {archiveTestOrders, fingerprint};
