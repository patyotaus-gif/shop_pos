'use strict';

const {createHash, randomInt} = require('node:crypto');
const {HttpsError} = require('firebase-functions/v2/https');
const {Timestamp} = require('firebase-admin/firestore');

const trialLengthMs = 60 * 24 * 60 * 60 * 1000;
const policyVersion = '2026-11-28';
const referralAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';

function trialDetails(data) {
  const {name, tier, shopType, locations, marketingOptIn} = data || {};
  if (typeof name !== 'string' || !name.trim() || name.trim().length > 120 ||
      !['solo', 'lite', 'full'].includes(tier) || !['retail', 'restaurant'].includes(shopType) ||
      !Number.isInteger(locations) || locations < 1 || locations > 10000) {
    throw new HttpsError('invalid-argument', 'กรุณาตรวจชื่อร้าน ประเภทร้าน จำนวนสาขา และแพ็กเกจ');
  }
  if (data.policyVersion !== policyVersion || typeof marketingOptIn !== 'boolean') {
    throw new HttpsError('failed-precondition', 'กรุณาตรวจเงื่อนไขและนโยบายความเป็นส่วนตัวก่อนเริ่มทดลอง');
  }
  return {name: name.trim(), tier, shopType, reportedBranchCount: locations, marketingOptIn};
}

async function verifiedTrialPhone(auth, proof, ownerUid, now) {
  const retry = () => new HttpsError('failed-precondition', 'กรุณายืนยันเบอร์โทรศัพท์ด้วย OTP อีกครั้ง',
    {reason: 'phone-proof-required'});
  if (typeof proof !== 'string' || !proof || proof.length > 16384) throw retry();
  let identity, account;
  try {
    identity = await auth.verifyIdToken(proof, true);
    const age = now() / 1000 - identity.auth_time;
    if (identity.uid === ownerUid || identity.firebase?.sign_in_provider !== 'phone' ||
        !Number.isFinite(age) || age < -60 || age > 30 * 60 ||
        !/^\+[1-9]\d{6,14}$/.test(identity.phone_number || '')) throw retry();
    account = await auth.getUser(identity.uid);
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    if (['auth/argument-error', 'auth/invalid-argument', 'auth/invalid-id-token', 'auth/id-token-expired',
      'auth/id-token-revoked', 'auth/user-disabled', 'auth/user-not-found'].includes(error.code)) throw retry();
    throw new HttpsError('unavailable', 'ตรวจสอบรหัสยืนยันไม่ได้ กรุณาลองอีกครั้ง');
  }
  if (account.disabled || account.email || account.phoneNumber !== identity.phone_number ||
      !account.providerData.length || account.providerData.some(p => p.providerId !== 'phone')) throw retry();
  return account.phoneNumber;
}

async function requirePrimaryOwner(auth, request) {
  if (!request.auth) throw new HttpsError('unauthenticated', 'กรุณาเข้าสู่ระบบด้วยบัญชีเจ้าของร้าน');
  const {uid, token} = request.auth;
  const provider = token.firebase?.sign_in_provider;
  if (request.data?.ownerUid !== uid || uid.startsWith('staff_') || token.staffRole || token.ownerQuickUnlock ||
      !['password', 'google.com', 'apple.com'].includes(provider)) {
    throw new HttpsError('permission-denied', 'กรุณาเข้าสู่ระบบด้วยบัญชีเจ้าของร้าน');
  }
  const owner = await auth.getUser(uid);
  const social = owner.providerData.find(p => p.providerId === provider &&
    ['google.com', 'apple.com'].includes(p.providerId));
  const trustedSocial = social && (owner.email
    ? social.email?.toLowerCase() === owner.email.toLowerCase()
    : owner.providerData.every(p => ['google.com', 'apple.com', 'phone'].includes(p.providerId)));
  if (owner.disabled || (!trustedSocial && !(owner.email && owner.emailVerified))) {
    throw new HttpsError('permission-denied', 'กรุณายืนยันอีเมลของเจ้าของร้าน');
  }
  return owner;
}

function activateMerchantTrial({db, auth, now = Date.now}) {
  return async request => {
    const owner = await requirePrimaryOwner(auth, request);
    const uid = owner.uid;
    const shop = db.collection('shops').doc(uid);
    if ((await shop.get()).exists) return {created: false};
    const details = trialDetails(request.data);
    const phone = await verifiedTrialPhone(auth, request.data.phoneProof, uid, now);
    // The phone-only Firebase identity is separate from the signed-in owner.
    // Only the owner can read their private contact record.
    const contact = db.collection('merchantTrialContacts').doc(uid);
    const phoneKey = createHash('sha256').update(phone).digest('hex');
    const phoneClaim = db.collection('merchantTrialPhones').doc(phoneKey);
    const ownerClaim = db.collection('merchantTrialOwners').doc(uid);
    return db.runTransaction(async tx => {
      const [existing, priorPhone, priorOwner] = await tx.getAll(shop, phoneClaim, ownerClaim);
      if (existing.exists) return {created: false};
      if (priorPhone.exists || priorOwner.exists) {
        throw new HttpsError('already-exists', 'สิทธิ์ทดลองนี้เคยเริ่มแล้ว หากเป็นคนละกิจการ กรุณาขอให้ทีมติดต่อกลับ');
      }
      const start = Timestamp.now();
      const trialEndsAt = Timestamp.fromMillis(start.toMillis() + trialLengthMs);
      const referralCode = Array.from({length: 6}, () => referralAlphabet[randomInt(referralAlphabet.length)]).join('');
      const {marketingOptIn, ...profile} = details;
      tx.create(shop, {
        // locations is the number of billed locations. Survey answers do not
        // authorize purchasing additional locations.
        ...profile, email: owner.email || '', locations: 1, plan: 'monthly', subscriptionStatus: 'trial',
        trialEndsAt, subscriptionEndsAt: null, createdAt: start, referralCode,
        consent: {policyVersion, acceptedAt: start, marketingOptIn},
      });
      tx.create(phoneClaim, {ownerId: uid, createdAt: start});
      tx.create(ownerClaim, {createdAt: start, trialEndsAt});
      tx.create(contact, {phoneNumber: phone, verifiedAt: start});
      return {created: true};
    });
  };
}

// Completing OTP for a shop created by an older client never starts a trial
// or changes the existing shop, subscription, or primary sign-in provider.
function verifyMerchantPhone({db, auth, now = Date.now}) {
  return async request => {
    const {uid} = await requirePrimaryOwner(auth, request);
    const shop = db.collection('shops').doc(uid);
    const contact = db.collection('merchantTrialContacts').doc(uid);
    const phone = await verifiedTrialPhone(auth, request.data.phoneProof, uid, now);
    const claim = db.collection('merchantTrialPhones').doc(createHash('sha256').update(phone).digest('hex'));
    return db.runTransaction(async tx => {
      const [existing, saved, prior] = await tx.getAll(shop, contact, claim);
      if (!existing.exists) throw new HttpsError('failed-precondition', 'กรุณาเปิดร้านให้เสร็จก่อน');
      if (!(saved.get('verifiedAt') instanceof Timestamp)) {
        const at = Timestamp.now();
        tx.set(contact, {phoneNumber: phone, verifiedAt: at}, {merge: true});
        // A shared contact for existing businesses cannot issue a new trial.
        if (!prior.exists) tx.create(claim, {ownerId: uid, createdAt: at});
      }
      return {verified: true};
    });
  };
}

module.exports = {activateMerchantTrial, verifyMerchantPhone};
