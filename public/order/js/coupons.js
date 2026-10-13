import {apiFetch, shopId, fmtBaht} from './util.js?v=20261013stock';
import {items, total, onCartChange} from './cart.js?v=20261013stock';
import {promotionTotal, refreshGifts} from './buy-get.js?v=20261013stock';

let applied = null;
let revision = 0;
const input = () => document.getElementById('couponCode');
const orderItems = () => items().map(i => ({productId:i.id,quantity:i.quantity,optionIds:i.optionIds || [],...(i.notes ? {notes:i.notes} : {})}));
const fingerprint = () => JSON.stringify(orderItems());
function invalidate(message = '') {
  revision++;
  applied = null;
  document.getElementById('couponStatus').textContent = message;
  document.getElementById('modalTotal').textContent = fmtBaht(promotionTotal());
}
export function couponPayload() {
  const code = input().value.trim().toUpperCase();
  if (!code) return {};
  if (!applied || applied.code !== code || applied.cart !== fingerprint()) throw Error('กรุณากดตรวจโค้ดส่วนลดก่อนชำระเงิน');
  return {couponCode:code,couponQuote:{subtotalMinor:applied.subtotalMinor,discountMinor:applied.discountMinor}};
}
export function initCoupons() {
  document.addEventListener('promotionsChanged',()=>invalidate(input().value.trim() ? 'ตรวจโปรโมชั่นแล้ว กรุณาตรวจโค้ดอีกครั้ง' : ''));
  input().addEventListener('input', () => invalidate());
  onCartChange(() => invalidate(input().value.trim() ? 'ตะกร้าเปลี่ยนแล้ว กรุณาตรวจโค้ดอีกครั้ง' : ''));
  document.getElementById('couponClear').addEventListener('click', () => {input().value=''; invalidate();});
  document.getElementById('couponApply').addEventListener('click', async () => {
    await refreshGifts();
    invalidate();
    const code = input().value.trim().toUpperCase();
    const current = revision, cart = fingerprint(), button = document.getElementById('couponApply');
    if (!/^[A-Z0-9_-]{3,24}$/.test(code)) {
      document.getElementById('couponStatus').textContent = 'กรุณาระบุโค้ด 3–24 ตัว (A-Z ตัวเลข - _)'; return;
    }
    button.disabled = true;
    document.getElementById('couponStatus').textContent = 'กำลังตรวจโค้ด…';
    try {
      const response = await apiFetch('/api/createPromptPayOrder',{method:'POST',headers:{'Content-Type':'application/json'},
        body:JSON.stringify({shopId,action:'quoteCoupon',couponCode:code,items:orderItems()})});
      const data = await response.json();
      if (revision !== current || cart !== fingerprint()) return;
      if (!response.ok) throw Error(data.error || 'ตรวจคูปองไม่สำเร็จ กรุณาลองใหม่');
      applied = {...data,cart};
      document.getElementById('couponStatus').textContent = `ใช้ ${code} ลด ${fmtBaht(data.discountMinor/100)} จากยอดสินค้า ${fmtBaht(data.subtotalMinor/100)} • จองสิทธิ์เมื่อสร้างออเดอร์`;
      document.getElementById('modalTotal').textContent = fmtBaht(data.totalMinor/100);
    } catch(error) {
      if (revision === current) invalidate(error.message || 'ตรวจคูปองไม่สำเร็จ กรุณาลองใหม่');
    } finally {button.disabled = false;}
  });
}
