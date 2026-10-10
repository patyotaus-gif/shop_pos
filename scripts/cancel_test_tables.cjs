'use strict';
// Operator-only, owner-confirmed test-data repair. No network or writes on import.
const assert = require('node:assert/strict');
const {fingerprint} = require('./archive_test_orders.cjs');
const idOK = id => typeof id === 'string' && /^[\w-]{1,150}$/.test(id);

async function cancelTestTables({db, FieldValue, manifest, apply = false}) {
  const {shopId, sessionId, correctionId, confirmedBy, reason, entries} = manifest;
  assert(idOK(shopId) && idOK(sessionId) && idOK(correctionId));
  assert.equal(confirmedBy, shopId);
  assert.equal(manifest.actualMoneyReceivedMinor, 0);
  assert(typeof reason === 'string' && reason.trim().length > 10);
  assert(Array.isArray(entries) && entries.length > 0 && entries.length <= 20);
  assert.equal(new Set(entries.map(e => e.orderId)).size, entries.length);
  assert.equal(new Set(entries.map(e => e.tableId)).size, entries.length);
  assert(entries.every(e => idOK(e.orderId) && idOK(e.tableId) && /^[a-f0-9]{64}$/.test(e.fingerprint)));
  const shop = db.collection('shops').doc(shopId);
  const auditRef = shop.collection('accountingCorrections').doc(correctionId);
  const manifestHash = fingerprint(manifest);
  return db.runTransaction(async tx => {
    const audit = await tx.get(auditRef);
    if (audit.exists) {
      assert.equal(audit.data().manifestHash, manifestHash, 'Correction manifest changed');
      return {alreadyApplied: true, count: entries.length, manifestHash};
    }
    const controlRef = shop.collection('cashControl').doc('current');
    const control = await tx.get(controlRef);
    assert.equal(control.data()?.sessionId, sessionId, 'Round changed');
    assert.equal((await tx.get(shop.collection('cashSessions').doc(sessionId))).data()?.status, 'open');
    const records = [];
    for (const e of entries) {
      const orderRef = shop.collection('tableOrders').doc(e.orderId);
      const tableRef = shop.collection('tables').doc(e.tableId);
      const saleId = 'table-' + e.orderId;
      const [order, table, sale, movement, waste] = await Promise.all([
        tx.get(orderRef), tx.get(tableRef), tx.get(shop.collection('sales').doc(saleId)),
        tx.get(shop.collection('moneyMovements').doc('sale-' + saleId)),
        tx.get(shop.collection('inventoryWaste').doc(saleId)),
      ]);
      assert(order.exists && table.exists, 'Missing table/order');
      const originals = {order: order.data(), table: table.data()};
      assert.equal(fingerprint(originals), e.fingerprint, 'Source changed');
      assert.equal(originals.order.status, 'open');
      assert.equal(originals.order.tableId, e.tableId);
      assert(!originals.order.saleId && !originals.order.paidAt && !originals.order.closedAt);
      assert(!originals.order.stockDeducted && !originals.order.ingredientsDeducted);
      assert.equal(originals.table.currentOrderId, e.orderId);
      assert.equal(originals.table.status, 'occupied');
      assert(!sale.exists && !movement.exists && !waste.exists, 'Financial or inventory record requires review');
      records.push({e, orderRef, tableRef, originals});
    }
    if (apply) {
      const at = FieldValue.serverTimestamp();
      tx.create(auditRef, {schemaVersion: 1, kind: 'cancelConfirmedTestTables', manifest,
        manifestHash, createdAt: at, count: entries.length, actualMoneyReceivedMinor: 0, actualRefundMinor: 0});
      for (const r of records) {
        tx.create(auditRef.collection('records').doc(r.e.orderId), {...r.originals,
          sourceFingerprint: r.e.fingerprint, sourcePaths: [r.orderRef.path, r.tableRef.path], archivedAt: at});
        tx.update(r.orderRef, {status: 'cancelled', closedAt: at, cancelReason: reason,
          consumedPreparedItems: false, isTestOrder: true, cancelledBy: confirmedBy, accountingCorrectionId: correctionId});
        tx.update(r.tableRef, {status: 'available', currentOrderId: FieldValue.delete()});
      }
      tx.update(controlRef, {revision: FieldValue.increment(1)});
    }
    return {alreadyApplied: false, applied: apply, count: entries.length, manifestHash};
  });
}
module.exports = {cancelTestTables};
