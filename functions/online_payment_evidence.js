'use strict';
const {minor} = require('./money_ledger');

function requiresGatewayVerification(order) {
  return order.paymentMethod === 'stripe' || order.paymentMethod === 'omise' ||
    !!order.stripeSessionId || !!order.omise;
}

// Internal server interface only. The caller MUST retrieve the charge using the
// pinned merchant account's key; never pass customer/webhook JSON as evidence.
// No customer endpoint currently accepts this object.
function verifyOmisePayment({order, shopId, orderId, payment}) {
  const binding = order.omise;
  const charge = payment?.charge;
  if (order.paymentMethod !== 'omise' || !binding || binding.mode !== 'live' ||
      typeof binding.merchantId !== 'string' || !binding.merchantId ||
      typeof binding.chargeId !== 'string' || !/^chrg_[a-z0-9_]+$/.test(binding.chargeId) ||
      payment?.merchantId !== binding.merchantId || charge?.id !== binding.chargeId ||
      charge?.object !== 'charge' || charge?.livemode !== true ||
      charge?.metadata?.pokpokShopId !== shopId || charge?.metadata?.pokpokOrderId !== orderId) {
    throw new Error('Omise merchant, order or live payment evidence mismatch');
  }
  if (charge.status !== 'successful' || charge.paid !== true || charge.captured !== true ||
      charge.reversed === true || charge.refunded_amount !== 0 ||
      String(charge.currency).toUpperCase() !== 'THB' || !Number.isSafeInteger(charge.amount) ||
      charge.amount <= 0 || charge.amount !== minor(order.total) ||
      minor(order.finalAmount ?? order.total) !== charge.amount) {
    throw new Error('Omise payment amount or settlement mismatch');
  }
  return {chargeId:charge.id, merchantId:binding.merchantId, amountMinor:charge.amount};
}

module.exports = {requiresGatewayVerification, verifyOmisePayment};
