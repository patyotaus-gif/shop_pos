'use strict';

const {createHash} = require('node:crypto');
const {HttpsError} = require('firebase-functions/v2/https');

function field(value, max, label, optional = false) {
  const text = typeof value === 'string' ? value.trim().normalize('NFC') : '';
  if ((!optional && !text) || text.length > max) {
    throw new HttpsError('invalid-argument', 'กรุณาตรวจ' + label);
  }
  return text;
}

function shopTerms(shop) {
  const planStatus = shop.get('subscriptionStatus') || 'trial';
  const end = shop.get(planStatus === 'trial' ? 'trialEndsAt' : 'subscriptionEndsAt');
  return {planStatus, endsAtMs: end?.toMillis() ?? null};
}

function summary(doc) {
  const {shopName, ownerEmail, termsAtSubmission, name, address, note, status, revision, reason, previousReason, updatedAt} = doc.data();
  return {id: doc.id, shopName, ownerEmail, termsAtSubmission, name, address, note, status, revision, reason,
    previousReason: previousReason || '', updatedAtMs: updatedAt.toMillis()};
}

function handlers({db, FieldValue, assertFounder}) {
  const requests = db.collection('branchRequests');
  async function owner(request) {
    const uid = request.auth?.uid;
    const data = request.data || {};
    if (!uid || request.auth.token.staffRole || uid !== data.shopId) {
      throw new HttpsError('permission-denied', 'เฉพาะเจ้าของร้านเท่านั้น');
    }
    const shop = db.collection('shops').doc(uid);
    if (data.action === 'list') {
      const [parent, rows] = await Promise.all([shop.get(), requests.where('shopId', '==', uid).get()]);
      if (!parent.exists) throw new HttpsError('not-found', 'ไม่พบร้านค้า');
      return {shopName: parent.get('name') || '', ...shopTerms(parent),
        items: rows.docs.map(summary).sort((a, b) => b.updatedAtMs - a.updatedAtMs)};
    }
    if (data.action !== 'submit' || !Number.isSafeInteger(data.revision) || data.revision < 0) {
      throw new HttpsError('invalid-argument', 'ข้อมูลคำขอไม่ถูกต้อง');
    }
    const name = field(data.name, 100, 'ชื่อสาขา');
    const address = field(data.address, 400, 'ที่ตั้งสาขา');
    const note = field(data.note, 500, 'ข้อมูลเพิ่มเติม', true);
    const nameKey = name.normalize('NFKC').toLowerCase().replace(/\s+/gu, ' ');
    const id = createHash('sha256').update(JSON.stringify([uid, nameKey])).digest('hex');
    const ref = requests.doc(id);
    return db.runTransaction(async tx => {
      const [parent, current] = await tx.getAll(shop, ref);
      if (!parent.exists) throw new HttpsError('not-found', 'ไม่พบร้านค้า');
      const prior = current.data();
      const revision = data.revision + 1;
      if (prior?.revision === revision && prior.address === address && prior.note === note) return {id};
      if (prior && (!['moreInfo', 'declined'].includes(prior.status) || prior.revision !== data.revision)) {
        throw new HttpsError('failed-precondition', 'มีคำขอชื่อนี้แล้ว กรุณาตรวจสถานะคำขอเดิม');
      }
      if (!prior && data.revision !== 0) throw new HttpsError('not-found', 'ไม่พบคำขอเดิม');
      const at = FieldValue.serverTimestamp();
      tx.set(ref, {shopId: uid, shopName: parent.get('name') || '', ownerEmail: request.auth.token.email || '',
        termsAtSubmission: shopTerms(parent),
        name, address, note, status: 'pending', revision, reason: '', previousReason: prior?.reason || '',
        pendingSince: at, updatedAt: at});
      tx.create(ref.collection('events').doc('submit-' + revision),
        {actor: uid, action: 'submit', name, address, note, at});
      return {id};
    });
  }

  async function admin(request) {
    assertFounder(request);
    const data = request.data || {};
    if (data.action === 'list') {
      const pending = await requests.orderBy('pendingSince').limit(50).get();
      return {items: pending.docs.map(summary)};
    }
    if (!['approved', 'moreInfo', 'declined'].includes(data.action) ||
        typeof data.id !== 'string' || !/^[a-f0-9]{64}$/.test(data.id) ||
        !Number.isSafeInteger(data.revision) || data.revision < 1) {
      throw new HttpsError('invalid-argument', 'ข้อมูลผลพิจารณาไม่ถูกต้อง');
    }
    const reason = field(data.reason, 500, 'เหตุผลสำหรับเจ้าของร้าน');
    const ref = requests.doc(data.id);
    return db.runTransaction(async tx => {
      const current = await tx.get(ref);
      if (!current.exists) throw new HttpsError('not-found', 'ไม่พบคำขอ');
      const r = current.data();
      if (r.revision === data.revision && r.status === data.action && r.reason === reason &&
          r.reviewedBy === request.auth.uid) return {id: ref.id};
      if (r.status !== 'pending' || r.revision !== data.revision) {
        throw new HttpsError('failed-precondition', 'คำขอนี้มีการเปลี่ยนแปลง กรุณาโหลดอีกครั้ง');
      }
      const shop = db.collection('shops').doc(r.shopId);
      if (!(await tx.get(shop)).exists) throw new HttpsError('not-found', 'ไม่พบร้านค้าต้นสังกัด');
      const at = FieldValue.serverTimestamp();
      if (data.action === 'approved') {
        // This registration inherits the parent shop's entitlement. Billing and POS data stay with the parent.
        tx.create(shop.collection('branches').doc(ref.id), {name: r.name, address: r.address, registeredAt: at});
      }
      tx.update(ref, {status: data.action, reason, reviewedBy: request.auth.uid,
        updatedAt: at, pendingSince: FieldValue.delete()});
      tx.create(ref.collection('events').doc('review-' + r.revision),
        {actor: request.auth.uid, action: data.action, reason, at});
      return {id: ref.id};
    });
  }
  return {owner, admin};
}

module.exports = {handlers};
