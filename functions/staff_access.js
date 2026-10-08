const crypto = require('node:crypto');
const {ledgerContext,writeMovement,saleMovement}=require('./money_ledger');
const { HttpsError } = require('firebase-functions/v2/https');
const { priceLine, effectivePriceOf } = require('./tableorder');
const fail = (code, message) => { throw new HttpsError(code, message); };
const idOk = id => typeof id === 'string' && /^[\w-]{1,128}$/.test(id);
const pinOk = pin => typeof pin === 'string' && /^\d{4,8}$/.test(pin);
function hashPin(pin) {
  const salt = crypto.randomBytes(16).toString('hex');
  return { pinSalt: salt, pinHash: crypto.scryptSync(pin, salt, 32).toString('hex') };
}
function matchesPin(pin, data) {
  if (!pinOk(pin)) return false;
  // Older owner apps can still update a plain PIN; migrate it on successful login.
  if (typeof data.pin === 'string' && data.pin) return data.pin === pin;
  if (!data.pinSalt || !/^[a-f0-9]{64}$/.test(data.pinHash || '')) return false;
  return crypto.timingSafeEqual(crypto.scryptSync(pin, data.pinSalt, 32), Buffer.from(data.pinHash, 'hex'));
}
function staffCap(shop) { return shop.tier === 'restaurant' || (!shop.tier && shop.shopType === 'restaurant') ? Infinity : (shop.tier || 'full') === 'full' ? 2 : 0; }
function requireSubscription(shop, now) {
  const until = shop.subscriptionStatus === 'active' ? shop.subscriptionEndsAt : shop.subscriptionStatus === 'trial' ? shop.trialEndsAt : null;
  if (!until?.toDate || until.toDate() <= now) fail('permission-denied', 'แผนร้านหมดอายุ กรุณาติดต่อเจ้าของร้าน');
  if (!staffCap(shop)) fail('permission-denied', 'แผนร้านนี้ไม่รองรับพนักงาน');
}
function publicSale(sale) {
  return { ...sale, createdAt: sale.createdAt.toDate().toISOString(),
    items: sale.items.map(({costPrice, costKnown, ...item}) => ({...item,
      modifiers: (item.modifiers || []).map(({costAdjust, ...m}) => m)})) };
}
function priceCart(lines, products, groups, now) {
  if (!Array.isArray(lines) || !lines.length || lines.length > 50) fail('invalid-argument', 'รายการขายต้องมี 1–50 รายการ');
  return lines.map(line => {
    if (!idOk(line.productId) || !Number.isInteger(line.quantity) || line.quantity < 1 || line.quantity > 99 ||
        !Array.isArray(line.optionIds) || new Set(line.optionIds).size !== line.optionIds.length || line.optionIds.length > 50) fail('invalid-argument', 'รายการสินค้าไม่ถูกต้อง');
    const product = products.get(line.productId);
    if (!product) fail('not-found', 'ไม่พบสินค้า กรุณาโหลดรายการใหม่');
    let priced;
    try { priced = priceLine({...line, notes: typeof line.notes === 'string' ? line.notes.slice(0,200) : ''}, product,
      (product.modifierGroupIds || []).map(id => { const g=groups.get(id); if(!g) throw Error('ตัวเลือกสินค้าถูกเปลี่ยน กรุณาโหลดใหม่'); return {id,...g}; }), now); }
    catch(e) { fail('invalid-argument',e.message); }
    if (!Number.isFinite(priced.unitPrice) || priced.unitPrice < 0) fail('failed-precondition','ราคาสินค้าไม่ถูกต้อง');
    return { productId:line.productId, productName:priced.productName, price:priced.basePrice,
      costPrice:Number(product.costPrice || 0), costKnown:Number(product.costPrice)>0, category:product.category || 'ทั่วไป',
      quantity:line.quantity, subtotal:Math.round(priced.unitPrice*line.quantity*100)/100,
      modifiers:priced.modifiers, ...(priced.notes ? {notes:priced.notes} : {}) };
  });
}
function createStaffAccess({db, auth, FieldValue, Timestamp, now=()=>new Date()}) {
  const shopRef = id => db.collection('shops').doc(id);
  function signed(request) { if(!request.auth) fail('unauthenticated','กรุณาเข้าสู่ระบบ'); return request.auth; }
  async function scope(request) {
    const user=signed(request);
    if(user.token?.staffRole) {
      if(user.token.staffRole!=='cashier'||!idOk(user.token.staffShopId)||!idOk(user.token.staffId)) fail('permission-denied','สิทธิ์ไม่ถูกต้อง');
      const ref=shopRef(user.token.staffShopId);
      const [shop,member]=await Promise.all([ref.get(),ref.collection('staff').doc(user.token.staffId).get()]);
      if(!shop.exists||!member.exists||member.data().active===false||Number(member.data().sessionVersion||0)!==user.token.staffVersion) fail('permission-denied','สิทธิ์พนักงานถูกยกเลิก กรุณาเข้าสู่ระบบใหม่');
      requireSubscription(shop.data(),now());
      return {ref, shop:shop.data(),member:member.data(),user};
    }
    const ref=shopRef(user.uid), shop=await ref.get();
    if(!shop.exists) fail('permission-denied','ไม่พบบัญชีเจ้าของร้าน');
    return {ref,shop:shop.data(),user};
  }
  async function list(request) {
    const ctx=await scope(request);
    const docs=await ctx.ref.collection('staff').get();
    return {staff:docs.docs.filter(d=>d.data().active!==false).map(d=>({id:d.id,name:d.data().name || 'พนักงาน'}))};
  }
  async function manage(request) {
    const user=signed(request);
    if(user.token?.staffRole) fail('permission-denied','เฉพาะเจ้าของร้าน');
    const {id,name,pin,active=true}=request.data || {};
    if(id!==undefined&&!idOk(id)) fail('invalid-argument','รหัสพนักงานไม่ถูกต้อง');
    if(typeof name!=='string'||!name.trim()||name.length>100||typeof active!=='boolean'||(pin && !pinOk(pin))) fail('invalid-argument','ตรวจชื่อและ PIN 4–8 หลัก');
    const shop=shopRef(user.uid),ref=id?shop.collection('staff').doc(id):shop.collection('staff').doc();
    const secret=pin?hashPin(pin):null;
    await db.runTransaction(async tx=>{
      const [s,existing,all]=await Promise.all([tx.get(shop),tx.get(ref),tx.get(shop.collection('staff'))]);
      if(!s.exists) fail('permission-denied','ไม่พบบัญชีเจ้าของร้าน');
      if(!existing.exists&&!secret) fail('invalid-argument','กรุณากำหนด PIN');
      if(id&&!existing.exists) fail('not-found','ไม่พบพนักงาน');
      if(active && all.docs.filter(d=>d.id!==ref.id&&d.data().active!==false).length>=staffCap(s.data())) fail('resource-exhausted','จำนวนพนักงานครบตามแผนแล้ว');
      const previous=existing.data() || {};
      tx.set(ref,{name:name.trim(),role:'cashier',active,createdAt:previous.createdAt || Timestamp.fromDate(now()),
        sessionVersion:Number(previous.sessionVersion||0)+(secret||previous.active!==active?1:0),
        ...(secret?{...secret,pin:FieldValue.delete(),failedAttempts:0,lockedUntil:FieldValue.delete()}:{}),
      },{merge:true});
    });
    return {id:ref.id};
  }
  async function switchSession(request) {
    const ctx=await scope(request);requireSubscription(ctx.shop,now());
    const {staffId,pin}=request.data || {};
    if(!idOk(staffId)||!pinOk(pin)) fail('invalid-argument','กรุณาระบุ PIN 4–8 หลัก');
    const ref=ctx.ref.collection('staff').doc(staffId);
    const result=await db.runTransaction(async tx=>{
      const snap=await tx.get(ref);if(!snap.exists||snap.data().active===false) return {error:'permission-denied'};
      const data=snap.data(),date=now();
      if(data.lockedUntil?.toDate()>date) return {error:'resource-exhausted'};
      if(!matchesPin(pin,data)) {
        const attempts=(data.lockedUntil?.toDate()<=date?0:Number(data.failedAttempts||0))+1;
        tx.update(ref,{failedAttempts:attempts,...(attempts>=5?{lockedUntil:Timestamp.fromDate(new Date(+date+5*60000))}:{})});
        return {error:attempts>=5?'resource-exhausted':'permission-denied'};
      }
      tx.update(ref,{failedAttempts:0,lockedUntil:FieldValue.delete(),...(data.pin?{...hashPin(pin),pin:FieldValue.delete()}:{}),lastLoginAt:Timestamp.fromDate(date)});
      return {version:Number(data.sessionVersion||0)};
    });
    if(result.error) fail(result.error,result.error==='resource-exhausted'?'PIN ผิดหลายครั้ง กรุณารอ 5 นาที':'PIN ไม่ถูกต้องหรือบัญชีถูกปิด');
    const uid='staff_'+crypto.createHash('sha256').update(ctx.ref.id+':'+staffId).digest('hex');
    const token=await auth.createCustomToken(uid,{staffRole:'cashier',staffShopId:ctx.ref.id,staffId,staffVersion:result.version});
    return {token};
  }
  async function workspace(request) {
    const ctx=await scope(request);if(!ctx.member) fail('permission-denied','ใช้สำหรับโหมดพนักงาน');
    const [products,groups,settings]=await Promise.all([ctx.ref.collection('products').get(),ctx.ref.collection('modifierGroups').get(),ctx.ref.collection('settings').doc('shop').get()]);
    const cfg=settings.data() || {};
    return {staffName:ctx.member.name,shop:{name:ctx.shop.name,email:'',tier:ctx.shop.tier||'full',shopType:ctx.shop.shopType||'retail',
      subscriptionStatus:ctx.shop.subscriptionStatus,trialEndsAt:ctx.shop.trialEndsAt?.toDate().toISOString()||null,
      subscriptionEndsAt:ctx.shop.subscriptionEndsAt?.toDate().toISOString()||null},
      settings:Object.fromEntries(['name','taxId','address','promptpayId','promptpayName'].map(k=>[k,cfg[k]||''])),
      products:products.docs.map(d=>{const p=d.data();return {id:d.id,name:p.name||'',barcode:p.barcode||'',price:effectivePriceOf(p,now()),stock:p.stock||0,
        category:p.category||'ทั่วไป',imageUrl:p.imageUrl||'',stockMode:p.stockMode||'count',modifierGroupIds:p.modifierGroupIds||[]};}),
      groups:groups.docs.map(d=>{const g=d.data();return {id:d.id,name:g.name,required:g.required===true,multiSelect:g.multiSelect===true,
        options:(g.options||[]).map(o=>({id:o.id,name:o.name,priceAdjust:Number(o.priceAdjust||0)}))};})};
  }
  async function checkout(request) {
    const ctx=await scope(request);if(!ctx.member) fail('permission-denied','ใช้สำหรับโหมดพนักงาน');
    const {requestId,items,paid,paymentMethod,expectedTotal,salesChannel}=request.data||{};
    if(salesChannel!==undefined&&!['storefront','dineIn','takeaway','lineMan','grab','otherDelivery'].includes(salesChannel)) fail('invalid-argument','ช่องทางขายไม่ถูกต้อง');
    if(!idOk(requestId)||requestId.length<10||!['cash','transfer','qr'].includes(paymentMethod)||!Number.isFinite(paid)||paid<0||paid>1e9||!Number.isFinite(expectedTotal)||expectedTotal<0||expectedTotal>1e9) fail('invalid-argument','ข้อมูลชำระเงินไม่ถูกต้อง');
    if(request.data.discount || request.data.isDebt) fail('permission-denied','ส่วนลดและขายเชื่อให้เจ้าของร้านดำเนินการ');
    if(!Array.isArray(items)||!items.length||items.length>50||items.some(i=>!idOk(i.productId))) fail('invalid-argument','รายการสินค้าไม่ถูกต้อง');
    const digest=crypto.createHash('sha256').update(JSON.stringify({items,paid,paymentMethod,expectedTotal,...(salesChannel?{salesChannel}:{})})).digest('hex');
    const ref=ctx.ref.collection('sales').doc(requestId);
    return db.runTransaction(async tx=>{
      const [prior,member,shop]=await Promise.all([tx.get(ref),tx.get(ctx.ref.collection('staff').doc(ctx.user.token.staffId)),tx.get(ctx.ref)]);
      if(!member.exists||member.data().active===false||Number(member.data().sessionVersion||0)!==ctx.user.token.staffVersion) fail('permission-denied','สิทธิ์พนักงานถูกยกเลิก');
      requireSubscription(shop.data(),now());
      if(prior.exists) {
        if(prior.data().staffUid!==ctx.user.uid||prior.data().requestDigest!==digest) fail('already-exists','รหัสรายการซ้ำ กรุณาติดต่อเจ้าของร้าน');
        return publicSale({id:ref.id,...prior.data()});
      }
      const ids=[...new Set(items.map(i=>i.productId))],products=new Map(),groups=new Map();
      for(const id of ids) {const p=await tx.get(ctx.ref.collection('products').doc(id));if(p.exists)products.set(id,p.data());}
      for(const id of new Set([...products.values()].flatMap(p=>p.modifierGroupIds||[]))) {const g=await tx.get(ctx.ref.collection('modifierGroups').doc(id));if(g.exists)groups.set(id,g.data());}
      const priced=priceCart(items,products,groups,now());
      const total=Math.round(priced.reduce((s,i)=>s+i.subtotal,0)*100)/100;
      if(Math.abs(total-expectedTotal)>0.009) fail('failed-precondition','ราคาสินค้าเปลี่ยน กรุณาติดต่อเจ้าของร้านก่อนรับเงินเพิ่ม');
      if(paymentMethod==='cash'&&paid<total) fail('invalid-argument','จำนวนเงินรับไม่พอ');
      const quantities=new Map();for(const i of priced) quantities.set(i.productId,(quantities.get(i.productId)||0)+i.quantity);
      const reserved=(await tx.get(ctx.ref.collection('inventoryControl').doc('online'))).data() || {};
      for(const [id,q] of quantities)if(products.get(id).stockMode!=='recipe'&&Number(products.get(id).stock||0)-Number(reserved.products?.[id]||0)<q)fail('failed-precondition','สต็อกไม่พอหรือถูกจองออนไลน์ กรุณาติดต่อเจ้าของร้าน');
      const usage=require('./inventory').computeUsage(priced,Object.fromEntries(products),Object.fromEntries(groups)),ingredientUpdates=[];
      for(const [id,qty] of Object.entries(usage)){
        const ref=ctx.ref.collection('ingredients').doc(id),ing=(await tx.get(ref)).data();
        const held=Number(reserved.ingredients?.[id]||0);
        if(held>0 && Number(ing?.stock||0)-qty+1e-9<held)fail('failed-precondition','วัตถุดิบถูกจองออนไลน์ กรุณาติดต่อเจ้าของร้าน');
        if(ing)ingredientUpdates.push({ref,qty});
      }
      // Separate prefix/counter from owner devices, whose local timezone may differ.
      const counter=ctx.ref.collection('counters').doc('staffReceipt'),count=await tx.get(counter);
      const parts=new Intl.DateTimeFormat('en-CA',{timeZone:'Asia/Bangkok',year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(now());
      const datePart=key=>parts.find(p=>p.type===key).value;
      const day=String((Number(datePart('year'))+543)%100).padStart(2,'0')+datePart('month')+datePart('day');
      const seq=count.data()?.day===day?Number(count.data().seq||0)+1:1;
      const sale={items:priced,total,discount:0,paid:paymentMethod==='cash'?paid:total,change:paymentMethod==='cash'?Math.round((paid-total)*100)/100:0,
        paymentMethod,...(salesChannel?{salesChannel}:{}),isDebt:false,isRefunded:false,createdAt:Timestamp.fromDate(now()),staffName:member.data().name,staffId:ctx.user.token.staffId,
        staffUid:ctx.user.uid,requestDigest:digest,receiptNo:`S-${day}-${String(seq).padStart(3,'0')}`};
      const context=await ledgerContext(tx,ctx.ref);
      sale.accountingVersion=1;
      sale.ingredientsDeducted=true;
      sale.ingredientUsage=Object.fromEntries(ingredientUpdates.map(u=>[u.ref.id,u.qty]));
      sale.stockDeducted=Object.fromEntries([...quantities].filter(([id])=>products.get(id).stockMode!=='recipe'));
      tx.set(ref,sale);tx.set(counter,{day,seq});
      for(const u of ingredientUpdates)tx.update(u.ref,{stock:FieldValue.increment(-u.qty)});
      writeMovement(tx,ctx.ref,context,'sale-'+ref.id,{...saleMovement(sale,ctx.user.uid),saleId:ref.id},FieldValue);
      for(const [id,q] of quantities)if(products.get(id).stockMode!=='recipe')tx.update(ctx.ref.collection('products').doc(id),{stock:FieldValue.increment(-q)});
      return publicSale({id:ref.id,...sale});
    });
  }
  return {list,manage,switchSession,workspace,checkout};
}
module.exports={createStaffAccess,hashPin,matchesPin,staffCap,priceCart,publicSale};
