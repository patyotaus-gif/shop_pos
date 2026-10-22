'use strict';
const {owner, validId} = require('./order_accounting');
const {runTransaction} = require('./transaction_retry');

// Recover only table links. Never settle/cancel orders, stock, or money here.
function handlers({db, FieldValue, HttpsError}) {
  return {reconcile: async request => {
    const shopId = owner(request, HttpsError);
    const {tableId} = request.data;
    if (!validId(tableId)) throw new HttpsError('invalid-argument', 'Invalid table');
    const shop = db.collection('shops').doc(shopId);
    const tableRef = shop.collection('tables').doc(tableId);
    return runTransaction(db, async tx => {
      const tableSnap = await tx.get(tableRef);
      if (!tableSnap.exists) throw new HttpsError('not-found', 'ไม่พบโต๊ะนี้');
      const table = tableSnap.data();
      const tabs = await tx.get(shop.collection('tableOrders')
        .where('tableId', '==', tableId).where('status', '==', 'open').limit(2));
      if (tabs.size > 1) throw new HttpsError('failed-precondition',
        'พบหลายบิลเปิดในโต๊ะเดียวกัน กรุณาติดต่อทีมงานตรวจบิลก่อนคืนโต๊ะว่าง');
      const link = table.currentOrderId;
      if (link != null) {
        if (!validId(link)) throw new HttpsError('failed-precondition', 'รหัสบิลโต๊ะไม่ถูกต้อง กรุณาติดต่อทีมงาน');
        const linked = await tx.get(shop.collection('tableOrders').doc(link));
        if (!linked.exists || linked.data().tableId !== tableId ||
            !['open', 'closed', 'cancelled'].includes(linked.data().status)) {
          throw new HttpsError('failed-precondition',
            'ยังตรวจสอบบิลเดิมของโต๊ะไม่ได้ กรุณาติดต่อทีมงานก่อนคืนโต๊ะว่าง');
        }
      }
      const openId = tabs.empty ? null : tabs.docs[0].id;
      if (!openId) {
        const online = await tx.get(shop.collection('orders')
          .where('tableId', '==', tableId)
          .where('status', 'in', ['pendingPayment', 'paid', 'accepted', 'ready']).limit(1));
        if (!online.empty) throw new HttpsError('failed-precondition',
          'ยังมีออเดอร์ของโต๊ะนี้ กรุณาจัดการให้เสร็จหรือยกเลิกในหน้าออเดอร์ก่อนคืนโต๊ะว่าง');
      }
      const status = openId ? 'occupied' : 'available';
      if (table.status !== status || (link ?? null) !== openId) {
        tx.update(tableRef, {status, currentOrderId: openId,
          stateReconciledAt: FieldValue.serverTimestamp(),
          stateReconciledBy: request.auth.uid});
      }
      return {status, orderId: openId};
    });
  }};
}
module.exports = {handlers};
