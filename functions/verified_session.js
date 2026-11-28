'use strict';

const {onCall: firebaseOnCall, HttpsError} = require('firebase-functions/v2/https');
const {getFirestore, Timestamp} = require('firebase-admin/firestore');

function acceptsToken(token = {}) {
  if (!token) return false;
  const provider = token.firebase?.sign_in_provider;
  // Linking a phone for trial eligibility must not grant a merchant session.
  if (provider === 'phone') return false;
  return token.email_verified === true || provider === 'google.com' || provider === 'apple.com'
    || (provider === 'custom' && token.ownerQuickUnlock === true && ['google.com', 'apple.com'].includes(token.ownerSocialProvider))
    || (provider === 'custom' && token.staffRole === 'cashier' && !!token.staffShopId && !!token.staffId);
}

// Auth-less requests still go through each endpoint's existing authorization.
// Cashier PINs are a separate server-issued identity; individual handlers
// continue to decide their shop, role, and permissions.
function accountOnCall(optionsOrHandler, handler) {
  const action = handler || optionsOrHandler;
  const checked = async (request, ...args) => {
    if (request.auth && !acceptsToken(request.auth.token)) {
      if (request.auth.token?.firebase?.sign_in_provider === 'phone') {
        throw new HttpsError('permission-denied', 'กรุณาเข้าสู่ระบบด้วยอีเมล Google หรือ Apple บัญชีเดิมของเจ้าของร้าน');
      }
      throw new HttpsError('permission-denied', 'กรุณายืนยันอีเมลก่อนใช้งาน โดยเปิดแอป Pokpok รุ่นล่าสุด หรือเข้าสู่ระบบที่ pok-pok.app/subscribe/');
    }
    return action(request, ...args);
  };
  return handler ? firebaseOnCall(optionsOrHandler, checked) : firebaseOnCall(checked);
}

function merchantShopId(request) {
  if (!request.auth) throw new HttpsError('unauthenticated', 'กรุณาเข้าสู่ระบบ');
  const {uid, token} = request.auth;
  return token.staffRole === 'cashier' ? token.staffShopId : uid;
}

async function hasVerifiedPhone(shopId) {
  const contact = await getFirestore().collection('merchantTrialContacts').doc(shopId).get();
  return contact.get('verifiedAt') instanceof Timestamp;
}

async function merchantPhoneStatus(request) {
  const shopId = merchantShopId(request);
  const db = getFirestore();
  if (await hasVerifiedPhone(shopId)) return {state: 'verified'};
  if (request.auth.token.staffRole === 'cashier') return {state: 'required'};
  const shop = await db.collection('shops').doc(shopId).get();
  return {state: shop.exists ? 'required' : 'new'};
}

function onCall(optionsOrHandler, handler) {
  const action = handler || optionsOrHandler;
  const checked = async (request, ...args) => {
    const shopId = merchantShopId(request);
    if (!(await hasVerifiedPhone(shopId))) {
      throw new HttpsError('permission-denied', 'กรุณายืนยันเบอร์มือถือเจ้าของร้านในแอป Pokpok ก่อนเข้าใช้งาน',
        {reason: 'merchant-phone-required'});
    }
    return action(request, ...args);
  };
  return handler ? accountOnCall(optionsOrHandler, checked) : accountOnCall(checked);
}

module.exports = {acceptsToken, onCall, accountOnCall, merchantPhoneStatus};
