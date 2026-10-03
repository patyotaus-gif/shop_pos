'use strict';

async function sendOwnerLineMessage({ request, db, push, HttpsError }) {
  const { shopId, message } = request.data || {};
  if (!request.auth || request.auth.uid !== shopId || request.auth.token?.staffRole) {
    throw new HttpsError('permission-denied', 'Shop owner required');
  }
  if (typeof shopId !== 'string' || !shopId || shopId.includes('/') ||
      typeof message !== 'string' || !message.trim() || message.length > 5000) {
    throw new HttpsError('invalid-argument', 'Invalid message');
  }
  const snapshot = await db.collection('shops').doc(shopId).collection('settings').doc('shop').get();
  const settings = snapshot.data() || {};
  if (settings.lineNotifyEnabled === false) return { skipped: true, reason: 'LINE notify disabled' };
  if (typeof settings.lineUserId !== 'string' || !/^U[0-9a-fA-F]{32}$/.test(settings.lineUserId)) {
    throw new HttpsError('failed-precondition', 'LINE connection code not configured');
  }
  const success = await push(settings.lineUserId, [{ type: 'text', text: message }]);
  if (!success) throw new HttpsError('unavailable', 'LINE did not accept the message');
  return { success: true };
}

module.exports = { sendOwnerLineMessage };
