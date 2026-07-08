// PromptPay EMVCo QR payload builder — shared by /order (customer orders)
// and /subscribe (subscription renewal). Moved verbatim from
// /order/js/payment.js; mirrors lib/utils/promptpay_qr.dart.
function tlv(tag, value) {
  return tag + String(value.length).padStart(2, '0') + value;
}
export function crc16(data) {
  let crc = 0xFFFF;
  for (let i = 0; i < data.length; i++) {
    crc ^= data.charCodeAt(i) << 8;
    for (let b = 0; b < 8; b++) {
      crc = (crc & 0x8000) ? ((crc << 1) ^ 0x1021) : (crc << 1);
      crc &= 0xFFFF;
    }
  }
  return crc.toString(16).toUpperCase().padStart(4, '0');
}
export function buildPromptPayPayload(rawId, amount) {
  const digits = String(rawId).replace(/\D/g, '');
  let tag, value;
  if (digits.length === 10)      { tag = '01'; value = '0066' + digits.substring(1); }
  else if (digits.length === 13) { tag = '02'; value = digits; }
  else if (digits.length === 15) { tag = '03'; value = digits; }
  else throw new Error('Invalid PromptPay ID length: ' + digits.length);

  let pp = '';
  pp += tlv('00', '01');
  pp += tlv('01', amount != null ? '12' : '11');
  pp += tlv('29', tlv('00', 'A000000677010111') + tlv(tag, value));
  pp += tlv('58', 'TH');
  pp += tlv('53', '764');
  if (amount != null) pp += tlv('54', Number(amount).toFixed(2));
  pp += '6304' + crc16(pp + '6304');
  return pp;
}
