'use strict';
const { randomBytes, createHash, timingSafeEqual } = require('node:crypto');
const hash = value => createHash('sha256').update(value).digest('hex');
const validId = id => typeof id === 'string' && /^[a-zA-Z0-9_-]{1,128}$/.test(id);
// These documents are server-only. Never accept a shop ID as proof of ownership.
function handlers({ db, HttpsError, now = Date.now }) {
  function owner(request) {
    const shopId = request.data?.shopId;
    if (!validId(shopId) || request.auth?.uid !== shopId || request.auth?.token?.staffRole) {
      throw new HttpsError('permission-denied', 'Shop owner required');
    }
    return shopId;
  }
  const linkRef = id => db.collection('lineLinkChallenges').doc(id);
  async function start(request) {
    const shopId = owner(request), token = randomBytes(32).toString('hex');
    const issuedAt = now(), expiresAt = issuedAt + 10 * 60 * 1000;
    await db.runTransaction(async tx => {
      const shop = await tx.get(db.collection('shops').doc(shopId));
      const prior = (await tx.get(linkRef(shopId))).data();
      if (!shop.exists) throw new HttpsError('not-found', 'Shop not found');
      if (prior && issuedAt - prior.issuedAt < 30000) throw new HttpsError('resource-exhausted', 'Please wait before creating another link');
      tx.set(linkRef(shopId), { tokenHash: hash(token), issuedAt, expiresAt, consumed: false });
    });
    const message = `connect:${shopId}:${token}`;
    return { expiresAt, url: `https://line.me/R/oaMessage/%40403teltq/?${encodeURIComponent(message)}` };
  }
  async function status(request) {
    const shopId = owner(request);
    const data = (await linkRef(shopId).get()).data();
    return { status: !data ? 'none' : data.consumed ? 'connected' : data.expiresAt <= now() ? 'expired' : 'waiting' };
  }
  async function cancel(request) {
    const shopId = owner(request);
    await db.runTransaction(async tx => {
      const ref = linkRef(shopId), data = (await tx.get(ref)).data();
      if (data && !data.consumed) tx.update(ref, { expiresAt: 0 });
    });
    return { success: true };
  }
  // Called only after verifying LINE's webhook signature; bind one-to-one chats only.
  async function consume({ text, userId, sourceType }) {
    const match = /^connect:([a-zA-Z0-9_-]{1,128}):([0-9a-f]{64})$/.exec(text);
    if (!match || sourceType !== 'user' || !/^U[0-9a-f]{32}$/i.test(userId || '')) return false;
    const [, shopId, token] = match;
    return db.runTransaction(async tx => {
      const ref = linkRef(shopId), data = (await tx.get(ref)).data();
      if (!data || data.consumed || data.expiresAt <= now() ||
          !timingSafeEqual(Buffer.from(hash(token)), Buffer.from(data.tokenHash))) return false;
      tx.set(db.collection('shops').doc(shopId).collection('settings').doc('shop'),
        { lineUserId: userId, lineNotifyEnabled: true }, { merge: true });
      tx.update(ref, { consumed: true, connectedAt: now() });
      return true;
    });
  }
  return { start, status, cancel, consume };
}
module.exports = { handlers };
