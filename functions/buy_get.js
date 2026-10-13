'use strict';
const {randomUUID} = require('node:crypto');
const validId = require('./customer_order').validId;
const fail = message => {throw Object.assign(Error('ซื้อแถม: ' + message), {buyGetError:true});};
const millis = value => value?.toMillis?.() ?? (value instanceof Date ? value.getTime() : value);
function config(raw, now=Date.now()) {
  if (!validId(raw.buyProductId) || !validId(raw.giftProductId)) fail('กรุณาเลือกสินค้า');
  for (const key of ['buyQuantity','giftQuantity','maxSets']) {
    if (!Number.isInteger(raw[key]) || raw[key]<1 || raw[key]>(key==='maxSets'?10:99)) fail('จำนวนสินค้า/ชุดไม่ถูกต้อง');
  }
  if (raw.giftQuantity*raw.maxSets>99) fail('ของแถมรวมต้องไม่เกิน 99 ชิ้นต่อออเดอร์');
  if (!Number.isSafeInteger(raw.endsAt) || raw.endsAt<=now || raw.endsAt>now+366*86400000) fail('วันสิ้นสุดต้องอยู่ภายในหนึ่งปี');
  return {buyProductId:raw.buyProductId,giftProductId:raw.giftProductId,buyQuantity:raw.buyQuantity,
    giftQuantity:raw.giftQuantity,maxSets:raw.maxSets,endsAt:new Date(raw.endsAt),active:true};
}
function giftAllowed(product) {
  if (!product) fail('ไม่พบสินค้าแถม');
  if (product.isWeighed) fail('สินค้าแถมต้องเป็นสินค้านับชิ้น');
  // Automatic gifts have no choices. Never bypass required preparation options.
  if ((product.modifierGroupIds || []).length) fail('สินค้าแถมต้องไม่มีตัวเลือกเสริม ให้สร้างสินค้าสูตรที่แน่นอนก่อน');
  if (product.stockMode==='recipe' && !(product.recipe || []).some(r=>validId(r.ingredientId) && r.qty>0)) fail('สินค้าแถมยังไม่มีสูตรวัตถุดิบ');
}
async function quote(shop, items, get=ref=>ref.get(), now=Date.now()) {
  const counts=new Map();
  for (const item of items) {
    if (!validId(item.productId) || !require('./stock_quantity').valid(item.quantity,true) || item.isGift) fail('รายการซื้อไม่ถูกต้อง');
    counts.set(item.productId,(counts.get(item.productId)||0)+item.quantity);
  }
  const gifts=[];
  for (const [id,quantity] of [...counts].sort(([a],[b])=>a.localeCompare(b))) {
    const promotion=(await get(shop.collection('buyGetPromotions').doc(id))).data();
    if (!promotion || !promotion.active || millis(promotion.endsAt)<=now) continue;
    const sets=Math.min(Math.floor(quantity/promotion.buyQuantity),promotion.maxSets);
    if (!sets) continue;
    const product=(await get(shop.collection('products').doc(promotion.giftProductId))).data();
    giftAllowed(product);
    gifts.push({promotionId:id,revision:promotion.revision,productId:promotion.giftProductId,
      productName:String(product.name || ''),quantity:sets*promotion.giftQuantity});
  }
  return gifts;
}
const fingerprint = gifts => JSON.stringify((gifts || []).map(g=>[g.promotionId,g.revision,g.productId,g.productName,g.quantity]));
async function apply(tx,shop,order,now) {
  const gifts=await quote(shop,order.items,ref=>tx.get(ref),now);
  if (fingerprint(gifts)!==fingerprint(order.buyGetQuote)) fail('โปรโมชั่นเปลี่ยนแล้ว กรุณาตรวจของแถมอีกครั้ง');
  const giftItems=[];
  for (const gift of gifts) {
    const product=(await tx.get(shop.collection('products').doc(gift.productId))).data();
    giftAllowed(product);
    giftItems.push({productId:gift.productId,productName:'ของแถม: '+gift.productName,quantity:gift.quantity,
      price:0,costPrice:Number(product.costPrice || 0),costKnown:Number(product.costPrice)>0,
      category:String(product.category || 'ทั่วไป'),isGift:true,promotionId:gift.promotionId});
  }
  const next={...order,items:[...order.items,...giftItems]};
  delete next.buyGetQuote;
  if (gifts.length) next.buyGet=gifts;
  return next;
}
function validateOrder(order) {
  const gifts=order.items.filter(i=>i.isGift);
  if (!order.buyGet && !gifts.length) return;
  if (!Array.isArray(order.buyGet) || order.buyGet.length!==gifts.length) throw Error('Gift accounting mismatch');
  for (let i=0;i<gifts.length;i++) {
    const item=gifts[i], expected=order.buyGet[i];
    if (item.productId!==expected.productId || item.promotionId!==expected.promotionId ||
        item.quantity!==expected.quantity || item.price!==0 || item.modifiers?.length) throw Error('Gift accounting mismatch');
  }
}
function manage({db,FieldValue,HttpsError}) {
  return async request=>{
    const shopId=require('./order_accounting').owner(request,HttpsError),raw=request.data || {};
    try {
      if (!validId(raw.buyProductId)) fail('กรุณาเลือกสินค้าที่ซื้อ');
      const shop=db.collection('shops').doc(shopId), ref=shop.collection('buyGetPromotions').doc(raw.buyProductId);
      if (raw.action==='save') {
        const next=config(raw);
        await db.runTransaction(async tx=>{
          const buy=(await tx.get(shop.collection('products').doc(next.buyProductId))).data();
          const gift=(await tx.get(shop.collection('products').doc(next.giftProductId))).data();
          if (!buy) fail('ไม่พบสินค้าที่ซื้อ');
          giftAllowed(gift);
          tx.set(ref,{...next,buyName:String(buy.name || ''),giftName:String(gift.name || ''),
            revision:randomUUID(),updatedAt:FieldValue.serverTimestamp()});
        });
      } else if (raw.action==='toggle' && typeof raw.active==='boolean') {
        await db.runTransaction(async tx=>{
          const saved=(await tx.get(ref)).data();
          if (!saved) fail('ไม่พบโปรโมชั่น');
          if (raw.active) {
            if (millis(saved.endsAt)<=Date.now()) fail('โปรโมชั่นหมดอายุ กรุณาตั้งวันสิ้นสุดใหม่');
            giftAllowed((await tx.get(shop.collection('products').doc(saved.giftProductId))).data());
          }
          tx.update(ref,{active:raw.active,revision:randomUUID(),updatedAt:FieldValue.serverTimestamp()});
        });
      } else fail('คำสั่งไม่ถูกต้อง');
      return {success:true};
    } catch(error) {
      throw new HttpsError(error.buyGetError?'failed-precondition':'unavailable',error.buyGetError?error.message:'บันทึกโปรซื้อแถมไม่สำเร็จ กรุณาลองใหม่');
    }
  };
}
module.exports={config,quote,apply,validateOrder,manage,fingerprint};
