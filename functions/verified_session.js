'use strict';

const {onCall: firebaseOnCall, HttpsError} = require('firebase-functions/v2/https');

function acceptsToken(token = {}) {
  const provider = token.firebase?.sign_in_provider;
  return token.email_verified === true || provider === 'google.com' || provider === 'apple.com'
    || (provider === 'custom' && token.ownerQuickUnlock === true && ['google.com', 'apple.com'].includes(token.ownerSocialProvider))
    || (provider === 'custom' && token.staffRole === 'cashier' && !!token.staffShopId && !!token.staffId);
}

// Auth-less requests still go through each endpoint's existing authorization.
// Cashier PINs are a separate server-issued identity; individual handlers
// continue to decide their shop, role, and permissions.
function onCall(optionsOrHandler, handler) {
  const action = handler || optionsOrHandler;
  const checked = async (request, ...args) => {
    if (request.auth && !acceptsToken(request.auth.token)) {
      throw new HttpsError('permission-denied', 'กรุณายืนยันอีเมลก่อนใช้งาน โดยเปิดแอป Pokpok รุ่นล่าสุด หรือเข้าสู่ระบบที่ pok-pok.app/subscribe/');
    }
    return action(request, ...args);
  };
  return handler ? firebaseOnCall(optionsOrHandler, checked) : firebaseOnCall(checked);
}

module.exports = {acceptsToken, onCall};
