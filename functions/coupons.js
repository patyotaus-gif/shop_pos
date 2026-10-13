'use strict';
const codeOf = value => typeof value === 'string' ? value.trim().toUpperCase() : '';
const validCode = code => /^[A-Z0-9_-]{3,24}$/.test(code);
const fail = message => { throw Object.assign(Error('คูปอง: ' + message), {couponError:true}); };
const time = value => value?.toMillis?.() ?? (value instanceof Date ? value.getTime() : value);
function validateConfig(raw, now = Date.now()) {
  const code = codeOf(raw.code);
  if (!validCode(code)) fail('ใช้ A-Z ตัวเลข ขีดกลาง หรือขีดล่าง 3–24 ตัว');
  if (!['fixed','percent'].includes(raw.kind)) fail('ประเภทส่วนลดไม่ถูกต้อง');
  if (!Number.isInteger(raw.value) || raw.value <= 0 || raw.value > (raw.kind === 'percent' ? 99 : 10000000)) fail('จำนวนส่วนลดไม่ถูกต้อง');
  if (!Number.isInteger(raw.minSubtotalMinor) || raw.minSubtotalMinor < 0 || raw.minSubtotalMinor > 100000000) fail('ยอดขั้นต่ำไม่ถูกต้อง');
  if (!Number.isInteger(raw.maxUses) || raw.maxUses < 1 || raw.maxUses > 100000) fail('จำนวนสิทธิ์ต้องอยู่ระหว่าง 1–100000');
  if (!Number.isSafeInteger(raw.endsAt) || raw.endsAt <= now || raw.endsAt > now + 366 * 86400000) fail('วันหมดอายุต้องอยู่ภายในหนึ่งปี');
  return {code,kind:raw.kind,value:raw.value,minSubtotalMinor:raw.minSubtotalMinor,maxUses:raw.maxUses,endsAt:new Date(raw.endsAt),active:true,claimed:0};
}
function quote(coupon, subtotalMinor, now = Date.now()) {
  if (!coupon || coupon.active !== true) fail('โค้ดนี้ไม่มีหรือปิดใช้งานแล้ว');
  if (!Number.isFinite(time(coupon.endsAt)) || time(coupon.endsAt) <= now) fail('โค้ดหมดอายุแล้ว');
  if (!Number.isSafeInteger(subtotalMinor) || subtotalMinor < 2000 || subtotalMinor > 100000000) fail('ยอดสินค้าไม่ถูกต้อง');
  if (subtotalMinor < coupon.minSubtotalMinor) fail(`ยอดขั้นต่ำ ${(coupon.minSubtotalMinor/100).toFixed(2)} บาท`);
  if (!Number.isInteger(coupon.claimed) || coupon.claimed < 0 || coupon.claimed >= coupon.maxUses) fail('สิทธิ์ครบแล้ว');
  const discountMinor = coupon.kind === 'percent' ? Math.round(subtotalMinor * coupon.value / 100) : coupon.value;
  if (!Number.isSafeInteger(discountMinor) || discountMinor <= 0 || subtotalMinor - discountMinor < 2000) fail('ยอดหลังลดต้องไม่น้อยกว่า 20 บาท');
  return {code:coupon.code,subtotalMinor,discountMinor,totalMinor:subtotalMinor-discountMinor};
}
async function reserve(tx, shop, order, now) {
  if (!order.couponCode) return null;
  if (!validCode(order.couponCode)) fail('โค้ดไม่ถูกต้อง');
  const ref = shop.collection('coupons').doc(order.couponCode);
  const coupon = (await tx.get(ref)).data();
  const q = quote(coupon, Math.round(order.total * 100), now);
  if (order.couponQuote?.subtotalMinor !== q.subtotalMinor || order.couponQuote?.discountMinor !== q.discountMinor) fail('ยอดเปลี่ยนแล้ว กรุณาตรวจโค้ดอีกครั้ง');
  return {quote:q, write:() => tx.update(ref,{claimed:coupon.claimed+1})};
}
async function prepareRelease(tx, shop, order) {
  if (!order.coupon?.code) return () => {};
  const ref = shop.collection('coupons').doc(order.coupon.code), coupon = (await tx.get(ref)).data();
  if (!coupon || !Number.isInteger(coupon.claimed) || coupon.claimed < 1) fail('ไม่พบสิทธิ์ที่จองไว้ กรุณาติดต่อผู้ดูแล');
  return () => tx.update(ref,{claimed:coupon.claimed-1});
}
function manage({db,FieldValue,HttpsError}) {
  return async request => {
    const shopId = require('./order_accounting').owner(request,HttpsError);
    const raw = request.data || {}, code = codeOf(raw.code);
    try {
      if (!validCode(code)) fail('โค้ดไม่ถูกต้อง');
      const ref = db.collection('shops').doc(shopId).collection('coupons').doc(code);
      if (raw.action === 'create') {
        const config = validateConfig(raw);
        await db.runTransaction(async tx => {
          if ((await tx.get(ref)).exists) fail('มีโค้ดนี้แล้ว กรุณาใช้ชื่ออื่น');
          tx.create(ref,{...config,createdAt:FieldValue.serverTimestamp()});
        });
      } else if (raw.action === 'toggle' && typeof raw.active === 'boolean') {
        await db.runTransaction(async tx => {
          if (!(await tx.get(ref)).exists) fail('ไม่พบโค้ด');
          tx.update(ref,{active:raw.active});
        });
      } else fail('คำสั่งไม่ถูกต้อง');
      return {success:true};
    } catch(e) {
      if (e.couponError) throw new HttpsError('failed-precondition',e.message);
      throw new HttpsError('unavailable','บันทึกคูปองไม่สำเร็จ กรุณาลองใหม่');
    }
  };
}
module.exports = {codeOf,validCode,validateConfig,quote,reserve,prepareRelease,manage};
