'use strict';
// Snapshot issuer and a shop-declared single VAT-inclusive rate at checkout.
// Keep behavior aligned with lib/models/receipt_profile.dart.
function receiptProfile(data = {}) {
  const text = v => typeof v === 'string' ? v.trim() : '';
  const name = text(data.name), address = text(data.address), taxId = text(data.taxId);
  const rate = data.receiptVatRate ?? 7;
  const validRate = Number.isFinite(rate) && rate > 0 && rate <= 100 &&
    Math.abs(rate * 100 - Math.round(rate * 100)) < 0.000001;
  return {name: name || 'ร้านของชำ', address, taxId,
    branch: text(data.branch), phone: text(data.phone), website: text(data.website), logoUrl: text(data.logoUrl),
    vatEnabled: data.receiptVatEnabled === true && !!name && !!address && /^\d{13}$/.test(taxId) && validRate,
    vatRate: validRate ? rate : 7};
}
module.exports = {receiptProfile};
