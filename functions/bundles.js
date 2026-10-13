'use strict';
const {randomUUID}=require('node:crypto');
const {effectivePriceOf}=require('./tableorder');
const validId=require('./customer_order').validId;
const fail=message=>{throw Object.assign(Error('ชุดสินค้า: '+message),{bundleError:true});};
const millis=v=>v?.toMillis?.() ?? (v instanceof Date?+v:v);
const refOf=shop=>shop.collection('promotionSettings').doc('bundles');
function config(raw,now=Date.now()) {
  if(typeof raw.name!=='string'||!raw.name.trim()||raw.name.trim().length>80)fail('ระบุชื่อชุดไม่เกิน 80 ตัวอักษร');
  if(!Array.isArray(raw.components)||raw.components.length<2||raw.components.length>10)fail('เลือกสินค้า 2–10 ชนิด');
  const ids=new Set();
  for(const c of raw.components) {
    if(!validId(c.productId)||ids.has(c.productId)||!Number.isInteger(c.quantity)||c.quantity<1||c.quantity>99)fail('สินค้า/จำนวนไม่ถูกต้องหรือซ้ำกัน');
    ids.add(c.productId);
  }
  if(!Number.isInteger(raw.maxSets)||raw.maxSets<1||raw.maxSets>10||raw.components.some(c=>c.quantity*raw.maxSets>99))fail('สูงสุด 10 ชุด และสินค้าแต่ละชนิดรวมไม่เกิน 99 ชิ้น');
  if(!Number.isSafeInteger(raw.priceMinor)||raw.priceMinor<1||raw.priceMinor>100000000)fail('ราคาชุดไม่ถูกต้อง');
  if(!Number.isSafeInteger(raw.endsAt)||raw.endsAt<=now||raw.endsAt>now+366*86400000)fail('กำหนดวันสิ้นสุดภายในหนึ่งปี');
  return {name:raw.name.trim(),components:raw.components.map(c=>({productId:c.productId,quantity:c.quantity})).sort((a,b)=>a.productId.localeCompare(b.productId)),
    maxSets:raw.maxSets,priceMinor:raw.priceMinor,endsAt:new Date(raw.endsAt),active:true};
}
function eligible(p) {
  return p && !p.isWeighed && !(p.modifierGroupIds||[]).length &&
    (p.stockMode!=='recipe'||(p.recipe||[]).some(r=>validId(r.ingredientId)&&r.qty>0));
}
function noOverlap(all,now=Date.now()) {
  const seen=new Set();
  for(const b of all.filter(b=>b.active&&millis(b.endsAt)>now)) for(const c of b.components) {
    if(seen.has(c.productId))fail('สินค้าซ้ำกับชุดที่เปิดใช้อยู่ กรุณาปิดชุดเดิมก่อน');
    seen.add(c.productId);
  }
}
async function quote(shop,items,get=r=>r.get(),now=Date.now()) {
  const all=(await get(refOf(shop))).data()?.bundles||[];
  const counts=new Map();
  for(const i of items) {
    if(i.isGift||i.modifiers?.length||i.optionIds?.length)continue;
    if(!validId(i.productId)||!require('./stock_quantity').valid(i.quantity,true))fail('รายการสินค้าไม่ถูกต้อง');
    counts.set(i.productId,(counts.get(i.productId)||0)+i.quantity);
  }
  noOverlap(all,now);
  const result=[];
  for(const b of [...all].sort((a,b)=>a.id.localeCompare(b.id))) {
    if(!b.active||millis(b.endsAt)<=now)continue;
    const sets=Math.min(b.maxSets,...b.components.map(c=>Math.floor((counts.get(c.productId)||0)/c.quantity)));
    if(!sets)continue;
    const components=[];
    for(const c of b.components) {
      const p=(await get(shop.collection('products').doc(c.productId))).data();
      if(!eligible(p))break;
      const unitPriceMinor=Math.round(effectivePriceOf(p,new Date(now))*100);
      if(!Number.isSafeInteger(unitPriceMinor)||unitPriceMinor<0)fail('ราคาสินค้าไม่ถูกต้อง');
      components.push({...c,unitPriceMinor});
    }
    if(components.length!==b.components.length)continue;
    const saving=components.reduce((s,c)=>s+c.unitPriceMinor*c.quantity,0)-b.priceMinor;
    // Never increase a customer's price when individual promotions are cheaper.
    if(saving<=0)continue;
    result.push({id:b.id,revision:b.revision,name:b.name,sets,priceMinor:b.priceMinor,discountMinor:saving*sets,components});
  }
  return result;
}
const discountMinor=list=>(list||[]).reduce((s,b)=>s+b.discountMinor,0);
const fingerprint=list=>JSON.stringify((list||[]).map(b=>[b.id,b.revision,b.name,b.sets,b.priceMinor,b.discountMinor,
  (b.components||[]).map(c=>[c.productId,c.quantity,c.unitPriceMinor])]));
async function catalog(shop,get=r=>r.get(),now=Date.now()) {
  const saved=(await get(refOf(shop))).data()?.bundles||[];
  const active=saved.filter(b=>b.active&&millis(b.endsAt)>now);
  const cart=active.flatMap(b=>b.components);
  const quoted=await quote(shop,cart,get,now);
  return quoted.map(b=>({id:b.id,name:b.name,priceMinor:b.priceMinor,
    maxSets:active.find(c=>c.id===b.id).maxSets,
    components:b.components.map(c=>({productId:c.productId,quantity:c.quantity}))}));
}
async function apply(tx,shop,order,now) {
  const bundles=await quote(shop,order.items,r=>tx.get(r),now);
  if(fingerprint(bundles)!==fingerprint(order.bundleQuote))fail('โปรโมชั่นหรือราคาเปลี่ยน กรุณาตรวจชุดสินค้าอีกครั้ง');
  const next={...order};delete next.bundleQuote;
  if(bundles.length) {
    const cut=discountMinor(bundles),subtotal=Math.round(order.total*100),final=Math.round(order.finalAmount*100);
    if(subtotal-cut<1)fail('ยอดหลังส่วนลดไม่ถูกต้อง');
    Object.assign(next,{bundles,bundleDiscount:cut/100,subtotal:subtotal/100,discount:cut/100,total:(subtotal-cut)/100,finalAmount:(final-cut)/100});
  }
  return next;
}
function validateOrder(order) {
  if(!order.bundles?.length)return 0;
  const counts=new Map(),prices=new Map();
  for(const i of order.items.filter(i=>!i.isGift&&!i.modifiers?.length)) {
    counts.set(i.productId,(counts.get(i.productId)||0)+i.quantity);
    prices.set(i.productId,Math.round(i.price*100));
  }
  for(const b of order.bundles) {
    if(!Number.isInteger(b.sets)||b.sets<1||!Number.isSafeInteger(b.priceMinor)||b.priceMinor<1||!Array.isArray(b.components)||b.components.length<2)throw Error('Bundle accounting mismatch');
    let full=0;
    for(const c of b.components) {
      if(!Number.isInteger(c.quantity)||c.quantity<1||prices.get(c.productId)!==c.unitPriceMinor||(counts.get(c.productId)||0)<c.quantity*b.sets)throw Error('Bundle component mismatch');
      counts.set(c.productId,counts.get(c.productId)-c.quantity*b.sets);
      full+=c.unitPriceMinor*c.quantity;
    }
    if(b.discountMinor!==(full-b.priceMinor)*b.sets||b.discountMinor<=0)throw Error('Bundle discount mismatch');
  }
  const cut=discountMinor(order.bundles);
  if(Math.round(order.bundleDiscount*100)!==cut)throw Error('Bundle accounting mismatch');
  const subtotal=order.items.reduce((s,i)=>s+Math.round(i.price*i.quantity*100),0);
  if(Math.round(order.total*100)!==subtotal-cut-(order.coupon?.discountMinor||0))throw Error('Bundle total mismatch');
  return cut;
}
function manage({db,FieldValue,HttpsError}) {
  return async request=>{
    const shopId=require('./order_accounting').owner(request,HttpsError),raw=request.data||{},shop=db.collection('shops').doc(shopId);
    try {
      const id=raw.id||randomUUID();if(!validId(id))fail('รหัสชุดไม่ถูกต้อง');
      await db.runTransaction(async tx=>{
        const ref=refOf(shop),all=(await tx.get(ref)).data()?.bundles||[],old=all.find(b=>b.id===id);
        let next;
        if(raw.action==='save')next={...config(raw),id,revision:randomUUID()};
        else if(raw.action==='toggle'&&old&&typeof raw.active==='boolean')next={...old,active:raw.active,revision:randomUUID()};
        else if(raw.action==='delete'&&old)next=null;
        else fail('ไม่พบชุดหรือคำสั่งไม่ถูกต้อง');
        if(next?.active) {
          if(millis(next.endsAt)<=Date.now())fail('ชุดหมดอายุ กรุณาตั้งวันสิ้นสุดใหม่');
          let full=0;
          for(const c of next.components) {
            const p=(await tx.get(shop.collection('products').doc(c.productId))).data();
            if(!eligible(p))fail('เลือกสินค้าที่ไม่มีตัวเลือกเสริมและมีสูตรวัตถุดิบครบ');
            c.productName=String(p.name||'');
            full+=Math.round(effectivePriceOf(p,new Date())*100)*c.quantity;
          }
          if(next.priceMinor>=full)fail('ราคาชุดต้องต่ำกว่าราคารวมสินค้า');
        }
        const updated=all.filter(b=>b.id!==id);if(next)updated.push(next);
        if(updated.length>20)fail('เก็บได้สูงสุด 20 ชุด กรุณาลบชุดที่ไม่ใช้');
        noOverlap(updated);
        tx.set(ref,{bundles:updated,updatedAt:FieldValue.serverTimestamp()});
      });
      return {success:true,id};
    } catch(e) {throw new HttpsError(e.bundleError?'failed-precondition':'unavailable',e.bundleError?e.message:'บันทึกชุดสินค้าไม่สำเร็จ');}
  };
}
module.exports={config,quote,apply,validateOrder,manage,discountMinor,fingerprint,noOverlap,catalog};
