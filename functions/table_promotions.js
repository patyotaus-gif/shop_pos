'use strict';
const {createHash, randomUUID} = require('node:crypto');
const stock = require('./stock_quantity');
const bundles = require('./bundles');
const gifts = require('./buy_get');
const coupons = require('./coupons');
const ledger = require('./money_ledger');
const hash = value => createHash('sha256').update(JSON.stringify(value)).digest('hex');
const unit = i => Number(i.price) + (i.modifiers || []).reduce((s,m)=>s+Number(m.priceAdjust||0),0);
const paidLines = order => order.items.filter(i=>!i.isGift);
const signature = order => hash(paidLines(order).map(i=>[i.id,i.productId,i.quantity,unit(i),i.notes||'',i.modifiers||[]]));
function handlers({db,FieldValue,HttpsError,now=()=>new Date()}) {
  const fail = message => {throw new HttpsError('failed-precondition',message);};
  async function inventory(tx,shop,items) {
    const products={},groups={},quantities={};
    for(const i of items) {
      if(!require('./order_accounting').validId(i.productId)||!stock.valid(i.quantity,true)||i.quantity<=0)fail('จำนวนสินค้าไม่ถูกต้อง');
      quantities[i.productId]=stock.round((quantities[i.productId]||0)+i.quantity);
    }
    const reserved=(await tx.get(shop.collection('inventoryControl').doc('online'))).data()||{};
    const allocations={};
    for(const [id,qty] of Object.entries(quantities)) {
      const p=(await tx.get(shop.collection('products').doc(id))).data();
      if(!p)fail('สินค้าในบิลถูกลบ กรุณาตรวจสอบ');
      if(p.stockMode==='recipe'&&!(p.recipe||[]).some(r=>r.ingredientId&&r.qty>0))fail('สูตรวัตถุดิบไม่ครบ');
      products[id]=p;
      if(!stock.valid(qty,p.isWeighed===true))fail('จำนวนสินค้าไม่ถูกต้อง');
      if(p.stockMode!=='recipe') {
        if(stock.available(p)-Number(reserved.products?.[id]||0)+1e-9<qty)fail('สินค้าไม่พอหรือถูกจองออนไลน์');
        allocations[id]=stock.allocate(p,qty);
      }
    }
    for(const id of new Set(Object.values(products).flatMap(p=>p.modifierGroupIds||[]))) {
      const g=(await tx.get(shop.collection('modifierGroups').doc(id))).data();
      if(g)groups[id]=g;
    }
    for(const i of items) for(const m of i.modifiers||[]) {
      if(!(groups[m.groupId]?.options||[]).some(o=>o.id===m.optionId))fail('ตัวเลือกเสริมเปลี่ยน กรุณาตรวจสอบวัตถุดิบก่อนปิดบิล');
    }
    const usage=require('./inventory').computeUsage(items,products,groups);
    for(const [id,qty] of Object.entries(usage)) {
      const ingredient=(await tx.get(shop.collection('ingredients').doc(id))).data();
      if(!ingredient||Number(ingredient.stock||0)-Number(reserved.ingredients?.[id]||0)+1e-9<qty)fail('วัตถุดิบไม่พอหรือถูกจองออนไลน์');
    }
    return {products,quantities,allocations,usage};
  }
  async function preview(tx,shop,order,code,{keepPreparedGifts=false,reason='',actor=''}={}) {
    const lines=paidLines(order);
    if(!lines.length)fail('ไม่มีรายการสินค้า');
    if(lines.some(i=>!Number.isFinite(unit(i))||unit(i)<0))fail('ราคาสินค้าไม่ถูกต้อง');
    const prices=new Map(),ambiguous=new Set();
    for(const i of lines) {
      if(!i.modifiers?.length) {
        if(prices.has(i.productId)&&prices.get(i.productId)!==i.price)ambiguous.add(i.productId);
        prices.set(i.productId,i.price);
      }
    }
    // An open table retains the price agreed when ordering, even if the menu changes.
    const get=async ref=>{
      const snap=await tx.get(ref),data=snap.data();
      if(data&&ref.path.includes('/products/')&&prices.has(ref.id))return {data:()=>({...data,price:prices.get(ref.id),salePrice:null,...(ambiguous.has(ref.id)?{isWeighed:true}:{})})};
      return snap;
    };
    const unchanged=order.tablePromotion?.signature===signature(order);
    const bundleQuote=unchanged?order.tablePromotion.bundles:await bundles.quote(shop,lines,get,+now());
    const buyGet=unchanged?structuredClone(order.tablePromotion.buyGet):await gifts.quote(shop,lines,r=>tx.get(r),+now());
    const subtotalMinor=lines.reduce((s,i)=>s+ledger.minor(unit(i)*i.quantity),0);
    const bundleDiscount=bundles.discountMinor(bundleQuote);
    let coupon=null;
    if(code) {
      if(!coupons.validCode(code))fail('โค้ดส่วนลดไม่ถูกต้อง');
      coupon=coupons.quote((await tx.get(shop.collection('coupons').doc(code))).data(),subtotalMinor-bundleDiscount,+now());
    }
    const existing=order.items.filter(i=>i.isGift),nextGifts=[];
    const retainedGifts=[...(order.tablePromotion?.retainedGifts||[])];
    for(const i of existing.filter(i=>i.kitchenStatus!=='pending')) {
      const expected=buyGet.find(g=>g.promotionId===i.promotionId&&g.productId===i.productId);
      const sent=existing.filter(g=>g.promotionId===i.promotionId&&g.productId===i.productId&&g.kitchenStatus!=='pending').reduce((s,g)=>s+g.quantity,0);
      if(!expected||sent>expected.quantity) {
        const retained=retainedGifts.find(g=>g.promotionId===i.promotionId&&g.productId===i.productId&&g.quantity>=sent);
        if(!retained&&!keepPreparedGifts)fail('ของแถมส่งครัวแล้ว แต่รายการใหม่ไม่ครบเงื่อนไข เลือกคงของแถมพร้อมระบุเหตุผล หรือเพิ่มสินค้ากลับให้ครบเงื่อนไข');
        if(!retained)retainedGifts.push({promotionId:i.promotionId,productId:i.productId,quantity:sent,reason,actor,at:now().toISOString()});
        if(expected)expected.quantity=sent;
        else buyGet.push({...order.tablePromotion.buyGet.find(g=>g.promotionId===i.promotionId&&g.productId===i.productId),quantity:sent});
      }
    }
    for(const g of buyGet) {
      const product=(await tx.get(shop.collection('products').doc(g.productId))).data();
      const delivered=existing.filter(i=>i.promotionId===g.promotionId&&i.productId===g.productId&&i.kitchenStatus!=='pending');
      nextGifts.push(...delivered);
      const remaining=g.quantity-delivered.reduce((s,i)=>s+i.quantity,0);
      if(remaining) {
        const pending=existing.find(i=>i.promotionId===g.promotionId&&i.productId===g.productId&&i.kitchenStatus==='pending');
        nextGifts.push({id:pending?.id||'gift-'+randomUUID(),productId:g.productId,productName:'ของแถม: '+g.productName,
          price:0,costPrice:Number(product.costPrice||0),costKnown:Number(product.costPrice)>0,category:product.category||'ทั่วไป',
          unit:product.unit||'ชิ้น',quantity:remaining,isGift:true,promotionId:g.promotionId,kitchenStatus:'pending'});
      }
    }
    const settings=(await tx.get(shop.collection('settings').doc('shop'))).data()||{};
    const serviceChargePercent=Number(settings.serviceChargePercent||0);
    if(!Number.isFinite(serviceChargePercent)||serviceChargePercent<0||serviceChargePercent>100)fail('ค่าบริการไม่ถูกต้อง');
    const discountMinor=bundleDiscount+(coupon?.discountMinor||0);
    const serviceMinor=Math.round((subtotalMinor-discountMinor)*serviceChargePercent/100);
    const data={signature:signature(order),lines:lines.map(i=>({id:i.id,productId:i.productId,quantity:i.quantity,unitPrice:unit(i)})),bundles:bundleQuote,buyGet,coupon,subtotalMinor,discountMinor,
      bundleDiscountMinor:bundleDiscount,serviceChargePercent,serviceMinor,totalMinor:subtotalMinor-discountMinor+serviceMinor,
      ...(retainedGifts.length?{retainedGifts}:{})};
    data.revision=hash(data);
    const items=[...lines,...nextGifts];
    await inventory(tx,shop,items);
    return {data,items};
  }
  return async request=>{
    const shopId=require('./order_accounting').owner(request,HttpsError),raw=request.data||{};
    if(!require('./order_accounting').validId(raw.orderId)||!['preview','apply','sync','send','close'].includes(raw.action))throw new HttpsError('invalid-argument','คำสั่งไม่ถูกต้อง');
    const shop=db.collection('shops').doc(shopId),ref=shop.collection('tableOrders').doc(raw.orderId);
    try {return await db.runTransaction(async tx=>{
      const order=(await tx.get(ref)).data();
      if(!order)fail('ไม่พบบิลโต๊ะ');
      if(raw.action==='close'&&order.status==='closed'&&order.saleId)return {saleId:order.saleId};
      if(order.status!=='open')fail('บิลนี้ปิดหรือยกเลิกแล้ว');
      if(!Array.isArray(order.items)||order.items.length>200)fail('รายการสินค้าไม่ถูกต้อง');
      order.items=order.items.map((i,n)=>({...i,id:i.id||`legacy-${n}`,kitchenStatus:i.kitchenStatus||'pending'}));
      for(const saved of order.tablePromotion?.giftLines||[]) {
        const current=order.items.find(i=>i.id===saved.id);
        if(!current||!current.isGift||current.productId!==saved.productId||current.promotionId!==saved.promotionId||
          current.quantity!==saved.quantity||unit(current)!==0)fail('ข้อมูลของแถมถูกเปลี่ยน กรุณาตรวจสอบรายการและใช้แอพรุ่นล่าสุดก่อนคิดเงิน');
      }
      const tableRef=shop.collection('tables').doc(order.tableId),table=(await tx.get(tableRef)).data();
      if(table?.currentOrderId!==raw.orderId)fail('โต๊ะเปลี่ยนบิลแล้ว');
      if(raw.action==='sync'||raw.action==='send') {
        const saved=order.tablePromotion;
        const code=Object.hasOwn(raw,'couponCode')?coupons.codeOf(raw.couponCode):saved?.coupon?.code||'';
        const keepPreparedGifts=raw.keepPreparedGifts===true;
        const reason=typeof raw.reason==='string'?raw.reason.trim():'';
        if(keepPreparedGifts&&(!reason||reason.length>500||raw.revision!==saved?.revision))fail('กรุณาตรวจรายการและระบุเหตุผลที่คงของแถม');
        const settings=(await tx.get(shop.collection('settings').doc('shop'))).data()||{};
        let data,items;
        // Preserve agreed bundle/gift terms when merely reopening an unchanged tab.
        if(saved?.signature===signature(order)&&code===(saved.coupon?.code||'')&&
          Number(settings.serviceChargePercent||0)===saved.serviceChargePercent) {
          data=saved;items=order.items;
          await inventory(tx,shop,items);
        } else ({data,items}=await preview(tx,shop,order,code,{keepPreparedGifts,reason,actor:request.auth.uid}));
        // Check validity before displaying the payment sheet. Claim only at close.
        await coupons.reserve(tx,shop,{total:(data.subtotalMinor-data.bundleDiscountMinor)/100,
          couponCode:data.coupon?.code,couponQuote:data.coupon},+now());
        if(raw.action==='send')items=items.map(i=>i.kitchenStatus==='pending'?{...i,kitchenStatus:'sent',sentToKitchenAt:now()}:i);
        data.giftLines=items.filter(i=>i.isGift).map(i=>({id:i.id,productId:i.productId,promotionId:i.promotionId,quantity:i.quantity}));
        // Do not create a stream/write loop for already-current quotes.
        if(data!==saved||raw.action==='send')tx.update(ref,{items,tablePromotion:data});
        return {promotion:data};
      }
      if(raw.action!=='close') {
        const {data,items}=await preview(tx,shop,order,coupons.codeOf(raw.couponCode));
        if(raw.action==='apply') {
          if(raw.revision!==data.revision)fail('รายการหรือโปรโมชั่นเปลี่ยน กรุณาตรวจใหม่');
          data.giftLines=items.filter(i=>i.isGift).map(i=>({id:i.id,productId:i.productId,promotionId:i.promotionId,quantity:i.quantity}));
          tx.update(ref,{items,tablePromotion:data});
        }
        return {promotion:data};
      }
      const p=order.tablePromotion;
      if(!p||p.revision!==raw.revision||p.signature!==signature(order))fail('รายการเปลี่ยน กรุณาตรวจโปรโมชั่นก่อนรับเงิน');
      if(!['cash','transfer','qr'].includes(raw.paymentMethod)||!Number.isFinite(raw.paid)||raw.paid<0||raw.paid>1e9||!Number.isInteger(raw.splitCount)||raw.splitCount<1||raw.splitCount>100)fail('ข้อมูลชำระเงินไม่ถูกต้อง');
      if(raw.expectedTotalMinor!==p.totalMinor||(raw.paymentMethod==='cash'&&ledger.minor(raw.paid)<p.totalMinor))fail('ยอดรับเงินไม่ตรงกับบิล');
      const giftItems=order.items.filter(i=>i.isGift);
      for(const g of p.buyGet) {
        const lines=giftItems.filter(i=>i.promotionId===g.promotionId&&i.productId===g.productId);
        if(lines.reduce((s,i)=>s+i.quantity,0)!==g.quantity)fail('จำนวนของแถมไม่ตรง กรุณาตรวจใหม่');
      }
      if(giftItems.some(i=>unit(i)!==0||!p.buyGet.some(g=>g.promotionId===i.promotionId&&g.productId===i.productId)))fail('รายการของแถมไม่ถูกต้อง');
      if(giftItems.some(i=>i.kitchenStatus==='pending'))fail('กรุณาส่งของแถมเข้าครัวก่อนปิดบิล');
      const coupon=await coupons.reserve(tx,shop,{total:(p.subtotalMinor-p.bundleDiscountMinor)/100,
        couponCode:p.coupon?.code,couponQuote:p.coupon},+now());
      const inv=await inventory(tx,shop,order.items);
      const context=await ledger.ledgerContext(tx,shop);
      const settings=(await tx.get(shop.collection('settings').doc('shop'))).data()||{};
      if(Number(settings.serviceChargePercent||0)!==p.serviceChargePercent)fail('ค่าบริการเปลี่ยน กรุณาตรวจยอดใหม่');
      const saleRef=shop.collection('sales').doc('table-'+raw.orderId);
      if((await tx.get(saleRef)).exists)fail('พบบิลขายเดิม กรุณาตรวจสถานะโต๊ะ');
      const date=now(),parts=new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Bangkok',year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(date);
      const part=k=>parts.find(p=>p.type===k).value;
      const day=String((Number(part('year'))+543)%100).padStart(2,'0')+part('month')+part('day');
      const counter=shop.collection('counters').doc('tableReceipt'),count=(await tx.get(counter)).data();
      const seq=count?.day===day?Number(count.seq||0)+1:1;
      const sale={items:order.items.map(i=>({productId:i.productId,productName:String(i.productName||''),price:i.price,quantity:i.quantity,
        costPrice:Number(i.costPrice||0),...(i.costKnown!=null?{costKnown:i.costKnown}:{}),category:i.category||'ทั่วไป',
        modifiers:i.modifiers||[],unit:i.unit||'ชิ้น',isWeighed:i.isWeighed===true,subtotal:ledger.minor(unit(i)*i.quantity)/100,
        ...(i.isGift?{isGift:true,promotionId:i.promotionId}:{})})),
        total:p.totalMinor/100,discount:p.discountMinor/100,bundleDiscount:p.bundleDiscountMinor/100,bundles:p.bundles,buyGet:p.buyGet,
        ...(p.coupon?{coupon:p.coupon}:{}),...(p.retainedGifts?{retainedGifts:p.retainedGifts}:{}),serviceCharge:p.serviceMinor/100,paid:raw.paymentMethod==='cash'?raw.paid:p.totalMinor/100,
        change:raw.paymentMethod==='cash'?(ledger.minor(raw.paid)-p.totalMinor)/100:0,paymentMethod:raw.paymentMethod,
        salesChannel:'dineIn',tableName:order.tableName,customerName:'โต๊ะ '+order.tableName,splitCount:raw.splitCount,
        createdAt:date,receiptNo:`T-${day}-${String(seq).padStart(3,'0')}`,receiptProfile:require('./receipt_profile').receiptProfile(settings),
        accountingVersion:1,isDebt:false,isRefunded:false,ingredientsDeducted:true,ingredientUsage:inv.usage,
        stockDeducted:Object.fromEntries(Object.keys(inv.allocations).map(id=>[id,inv.quantities[id]])),
        stockLotsDeducted:Object.fromEntries(Object.entries(inv.allocations).map(([id,a])=>[id,a.used]))};
      tx.create(saleRef,sale);tx.set(counter,{day,seq});coupon?.write();
      for(const [id,a] of Object.entries(inv.allocations))stock.write(tx,shop.collection('products').doc(id),inv.products[id],a,{id:'sale-'+saleRef.id,referenceId:saleRef.id,actor:request.auth.uid},FieldValue);
      for(const [id,qty] of Object.entries(inv.usage))tx.update(shop.collection('ingredients').doc(id),{stock:FieldValue.increment(-qty)});
      ledger.writeMovement(tx,shop,context,'sale-'+saleRef.id,{...ledger.saleMovement(sale,request.auth.uid),saleId:saleRef.id},FieldValue);
      tx.update(ref,{status:'closed',closedAt:date,saleId:saleRef.id});
      tx.update(tableRef,{status:'available',currentOrderId:null});
      return {saleId:saleRef.id};
    });} catch(e) {
      if(e instanceof HttpsError)throw e;
      if(e.couponError||e.buyGetError||e.bundleError)throw new HttpsError('failed-precondition',e.message);
      throw e;
    }
  };
}
module.exports={handlers,signature};
