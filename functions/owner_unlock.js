'use strict';
const crypto = require('node:crypto');
const {promisify} = require('node:util');
const {HttpsError} = require('firebase-functions/v2/https');
const scrypt = promisify(crypto.scrypt);
const hash = value => crypto.createHash('sha256').update(value).digest('hex');
const hex = (value, length) => typeof value === 'string' && new RegExp(`^[a-f0-9]{${length}}$`).test(value);
const pinOK = value => typeof value === 'string' && /^[0-9]{6,8}$/.test(value);
const fail = (code, message) => { throw new HttpsError(code, message); };
const denied = () => fail('permission-denied', 'PIN ไม่ถูกต้อง หรือการเข้าใช้งานด่วนหมดอายุ กรุณาใช้บัญชีเจ้าของร้าน');

// Only salted PIN digests and a digest of the device's random secret live here.
// This top-level collection is default-denied by Firestore rules.
exports.createOwnerUnlock = ({db, auth, Timestamp, now = () => Date.now()}) => {
  const root = uid => db.collection('ownerUnlockDevices').doc(uid);
  function owner(request, recent = false) {
    const user = request.auth;
    if (!user) fail('unauthenticated', 'กรุณาเข้าสู่ระบบเจ้าของร้าน');
    if (user.uid.startsWith('staff_') || user.token?.staffRole) denied();
    if (recent && (user.token?.ownerQuickUnlock === true ||
        user.token?.firebase?.sign_in_provider === 'custom' ||
        !Number.isFinite(user.token?.auth_time) ||
        now() / 1000 - user.token.auth_time > 600 ||
        user.token.auth_time > now() / 1000 + 60)) {
      fail('failed-precondition', 'กรุณาเข้าสู่ระบบด้วยอีเมล / Google / Apple ใหม่ก่อนตั้ง PIN เจ้าของ (ภายใน 10 นาที)');
    }
    return user.uid;
  }
  async function account(uid) {
    let user;
    try { user = await auth.getUser(uid); } catch (_) { denied(); }
    if (user.disabled || user.multiFactor?.enrolledFactors?.length) denied();
    return user;
  }
  function device(data, withPin = true) {
    if (!hex(data?.deviceId, 32) || !hex(data?.secret, 64) || (withPin && !pinOK(data?.pin))) {
      fail('invalid-argument', 'กรุณาระบุ PIN เจ้าของ 6–8 หลัก');
    }
  }
  async function setup(request) {
    const uid = owner(request, true), data = request.data;
    device(data);
    const user = await account(uid);
    if (!(await db.collection('shops').doc(uid).get()).exists) denied();
    const salt = crypto.randomBytes(16).toString('hex');
    const digest = (await scrypt(data.pin, salt, 64)).toString('hex');
    await root(uid).collection('devices').doc(data.deviceId).set({
      secretHash: hash(data.secret), salt, pinHash: digest, failedAttempts: 0,
      lockedUntil: null, createdAt: Timestamp.fromMillis(now()),
      expiresAt: Timestamp.fromMillis(now() + 90 * 86400000),
      authValidAfter: user.tokensValidAfterTime || '',
    });
    return {ok: true};
  }
  async function unlock(request) {
    const data = request.data;
    device(data);
    const session = request.auth;
    if (!session) fail('unauthenticated', 'กรุณาเข้าสู่ระบบด้วยบัญชีเจ้าของร้าน');
    let uid = session.uid;
    if (session.token?.staffRole || uid.startsWith('staff_')) {
      const {staffRole, staffShopId, staffId, staffVersion} = session.token || {};
      if (staffRole !== 'cashier' || typeof staffShopId !== 'string' || !staffShopId || staffShopId.includes('/') ||
          typeof staffId !== 'string' || !staffId || staffId.includes('/')) denied();
      const staff = await db.collection('shops').doc(staffShopId).collection('staff').doc(staffId).get();
      if (!staff.exists || staff.data().active === false || Number(staff.data().sessionVersion || 0) !== staffVersion) denied();
      uid = staffShopId;
    }
    // Never accept a caller-supplied owner UID/shop ID.
    const user = await account(uid);
    const ref = root(uid).collection('devices').doc(data.deviceId);
    const result = await db.runTransaction(async tx => {
      const snap = await tx.get(ref), stored = snap.data();
      if (!stored || stored.secretHash !== hash(data.secret) ||
          stored.expiresAt.toMillis() <= now() || stored.authValidAfter !== (user.tokensValidAfterTime || '')) return 'denied';
      if (stored.lockedUntil?.toMillis() > now()) return 'locked';
      const digest = await scrypt(data.pin, stored.salt, 64);
      if (!crypto.timingSafeEqual(digest, Buffer.from(stored.pinHash, 'hex'))) {
        const attempts = (stored.lockedUntil ? 0 : stored.failedAttempts || 0) + 1;
        tx.update(ref, {failedAttempts: attempts,
          lockedUntil: attempts >= 5 ? Timestamp.fromMillis(now() + 15 * 60000) : null});
        return attempts >= 5 ? 'locked' : 'denied';
      }
      tx.update(ref, {failedAttempts: 0, lockedUntil: null, lastUsedAt: Timestamp.fromMillis(now())});
      return 'ok';
    });
    if (result === 'locked') fail('resource-exhausted', 'PIN ผิดหลายครั้ง กรุณารอ 15 นาที หรือใช้บัญชีเจ้าของร้าน');
    if (result !== 'ok') denied();
    // Recheck account revocation/disablement before issuing a new owner session.
    const latest = await account(uid);
    if (latest.tokensValidAfterTime !== user.tokensValidAfterTime) denied();
    return {token: await auth.createCustomToken(uid, {ownerQuickUnlock: true})};
  }
  async function disable(request) {
    const uid = owner(request);
    if (!hex(request.data?.deviceId, 32)) fail('invalid-argument', 'ไม่พบเครื่องที่ตั้งค่าไว้');
    await root(uid).collection('devices').doc(request.data.deviceId).delete();
    return {ok: true};
  }
  return {setup, unlock, disable};
};
