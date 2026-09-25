const { HttpsError } = require('firebase-functions/v2/https');
const tiers = ['solo', 'lite', 'full', 'restaurant'];
const cycles = ['monthly', 'yearly'];
function createChangePlan({ db, assertFounder, FieldValue }) {
  return async request => {
    assertFounder(request);
    const { shopId, tier, billingCycle, locations, expected, requestId, reason } = request.data || {};
    if (typeof shopId !== 'string' || !shopId || shopId.includes('/') ||
        !tiers.includes(tier) || !cycles.includes(billingCycle) ||
        !Number.isInteger(locations) || locations < 1 || locations > 10000 ||
        typeof requestId !== 'string' || !/^[a-zA-Z0-9-]{10,80}$/.test(requestId) ||
        typeof reason !== 'string' || !reason.trim() || reason.length > 500 ||
        !expected || !tiers.includes(expected.tier) || !cycles.includes(expected.plan) ||
        !Number.isInteger(expected.locations)) {
      throw new HttpsError('invalid-argument', 'กรุณาตรวจแพ็กเกจ รอบบิล จำนวนสาขา และเหตุผล');
    }
    const ref = db.collection('shops').doc(shopId);
    const audit = ref.collection('planChanges').doc(requestId);
    return db.runTransaction(async tx => {
      const [snapshot, prior] = await Promise.all([tx.get(ref), tx.get(audit)]);
      if (prior.exists) {
        const p = prior.data();
        if (p.actor !== request.auth.uid || p.after.tier !== tier || p.after.plan !== billingCycle ||
            p.after.locations !== locations || p.reason !== reason.trim()) {
          throw new HttpsError('already-exists', 'คำขอซ้ำมีข้อมูลต่างกัน กรุณาเปิดหน้าร้านใหม่');
        }
        return { ok: true, replayed: true };
      }
      if (!snapshot.exists) throw new HttpsError('not-found', 'ไม่พบร้านค้า');
      const data = snapshot.data();
      const before = { tier: data.tier || (data.shopType === 'restaurant' ? 'restaurant' : 'full'),
        plan: data.plan || 'monthly', locations: data.locations || 1 };
      if (Object.keys(before).some(k => before[k] !== expected[k])) {
        throw new HttpsError('failed-precondition', 'แผนถูกเปลี่ยนแล้ว กรุณาปิดหน้านี้และเปิดร้านใหม่ก่อนแก้ไข');
      }
      const after = { tier, plan: billingCycle, locations };
      tx.update(ref, { ...after, shopType: tier === 'restaurant' ? 'restaurant' : 'retail' });
      tx.set(audit, { actor: request.auth.uid, before, after, reason: reason.trim(),
        createdAt: FieldValue.serverTimestamp() });
      // This changes entitlements only: no renewal, charge, or Stripe contract edit.
      return { ok: true };
    });
  };
}
module.exports = { createChangePlan };
