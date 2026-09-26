const crypto = require('node:crypto');
const { HttpsError } = require('firebase-functions/v2/https');
const { priceCart, staffCap } = require('./staff_access');
const { effectivePriceOf } = require('./tableorder');
const fail = (code, message) => { throw new HttpsError(code, message); };
const validId = v => typeof v === 'string' && /^[\w-]{10,128}$/.test(v);

function createOfflineSales({db, Timestamp, FieldValue, now = () => new Date()}) {
  function identity(request) {
    if (!request.auth) fail('unauthenticated', 'กรุณาเข้าสู่ระบบเพื่อซิงก์บิล');
    const {uid, token = {}} = request.auth;
    if (token.staffRole && (token.staffRole !== 'cashier' || !token.staffShopId || !token.staffId)) fail('permission-denied', 'สิทธิ์ไม่ถูกต้อง');
    return {uid, token, shop: db.collection('shops').doc(token.staffRole ? token.staffShopId : uid)};
  }
  async function prepare(request) {
    const ctx = identity(request), shop = (await ctx.shop.get()).data();
    const end = shop?.subscriptionStatus === 'active' ? shop.subscriptionEndsAt : shop?.subscriptionStatus === 'trial' ? shop.trialEndsAt : null;
    const issued = now(), expires = new Date(Math.min(+issued + 12*3600000, end?.toMillis() || 0));
    if (+expires <= +issued) fail('permission-denied', 'แผนร้านหมดอายุ');
    let member;
    if (ctx.token.staffRole) {
      member = (await ctx.shop.collection('staff').doc(ctx.token.staffId).get()).data();
      if (!member || member.active === false || Number(member.sessionVersion || 0) !== ctx.token.staffVersion || !staffCap(shop)) fail('permission-denied', 'สิทธิ์พนักงานถูกยกเลิก');
    }
    const [ps, gs, settings] = await Promise.all([ctx.shop.collection('products').get(), ctx.shop.collection('modifierGroups').get(), ctx.shop.collection('settings').doc('shop').get()]);
    const products = ps.docs.map(d => {
      const p = d.data();
      return {id:d.id, name:p.name || '', barcode:p.barcode || '', price:effectivePriceOf(p,issued), stock:Number(p.stock || 0), stockMode:p.stockMode || 'count', category:p.category || 'ทั่วไป', modifierGroupIds:p.modifierGroupIds || [], costPrice:Number(p.costPrice || 0)};
    });
    const groups = gs.docs.map(d => ({id:d.id, ...d.data()}));
    // Snapshot is server-owned and immutable: later price edits never erase a paid bill.
    const id = crypto.randomUUID(), secret = crypto.randomBytes(32).toString('hex');
    const permit = {uid:ctx.uid, shopId:ctx.shop.id, staffId:ctx.token.staffId || null, staffVersion:ctx.token.staffVersion ?? null,
      name:member?.name || 'เจ้าของร้าน', issuedAt:Timestamp.fromDate(issued), expiresAt:Timestamp.fromDate(expires), products, groups,
      secretHash:crypto.createHash('sha256').update(secret).digest('hex')};
    if (Buffer.byteLength(JSON.stringify(permit)) > 800000) fail('resource-exhausted', 'ข้อมูลสินค้าสำหรับออฟไลน์เกินขนาดที่รองรับ');
    await ctx.shop.collection('offlinePermits').doc(id).create(permit);
    const cfg=settings.data() || {};
    return {id,secret,uid:ctx.uid,shopId:ctx.shop.id,name:permit.name,shopName:shop.name || '',issuedAt:issued.toISOString(),expiresAt:expires.toISOString(),
      products:products.map(({costPrice,...p})=>p), groups:groups.map(g=>({id:g.id,name:g.name,required:g.required===true,multiSelect:g.multiSelect===true,
        options:(g.options||[]).map(o=>({id:o.id,name:o.name,priceAdjust:Number(o.priceAdjust||0)}))})),
      settings:{name:cfg.name || shop.name || '',address:cfg.address || '',taxId:cfg.taxId || ''}};
  }
  async function sync(request) {
    const ctx=identity(request), data=request.data || {};
    if (!validId(data.permitId) || !validId(data.id) || typeof data.secret !== 'string' || data.secret.length !== 64) fail('invalid-argument','ข้อมูลบิลไม่ถูกต้อง');
    const permitRef=ctx.shop.collection('offlinePermits').doc(data.permitId), saleRef=ctx.shop.collection('sales').doc(data.id);
    return db.runTransaction(async tx=>{
      const [permitDoc,prior]=await Promise.all([tx.get(permitRef),tx.get(saleRef)]);
      const p=permitDoc.data();
      if (!p || p.secretHash !== crypto.createHash('sha256').update(data.secret).digest('hex') || (ctx.uid!==p.uid && ctx.uid!==ctx.shop.id)) fail('permission-denied','สิทธิ์ซิงก์ไม่ถูกต้อง');
      const sold=new Date(data.createdAt);
      if (!Number.isFinite(+sold) || +sold < p.issuedAt.toMillis()-60000 || +sold > p.expiresAt.toMillis() || +sold > +now()+60000) fail('failed-precondition','เวลาบิลอยู่นอกสิทธิ์ออฟไลน์ กรุณาให้เจ้าของตรวจสอบ');
      if (data.paymentMethod!=='cash' || data.discount!==0 || !Number.isFinite(data.paid) || data.paid<0 || data.paid>1e9 || !Number.isFinite(data.total)) fail('invalid-argument','รองรับเงินสดไม่มีส่วนลดเท่านั้น');
      const digest=crypto.createHash('sha256').update(JSON.stringify({items:data.items,createdAt:data.createdAt,total:data.total,paid:data.paid,permitId:data.permitId})).digest('hex');
      if (prior.exists) {
        if(prior.data().offlineDigest!==digest) fail('already-exists','รหัสบิลซ้ำกับรายการอื่น');
        return {id:data.id,receiptNo:prior.data().receiptNo,review:prior.data().offlineReview || []};
      }
      const products=new Map(p.products.map(v=>[v.id,v])), groups=new Map(p.groups.map(v=>[v.id,v]));
      const items=priceCart(data.items,products,groups,p.issuedAt.toDate());
      const total=Math.round(items.reduce((s,i)=>s+i.subtotal,0)*100)/100;
      if(Math.abs(total-data.total)>0.009 || data.paid<total) fail('invalid-argument','ยอดบิลไม่ตรงกับราคาที่เตรียมไว้');
      const quantities=new Map();for(const i of items)quantities.set(i.productId,(quantities.get(i.productId)||0)+i.quantity);
      const review=[], updates=[];
      if(+now()>p.expiresAt.toMillis())review.push('ซิงก์หลังสิทธิ์ออฟไลน์หมดอายุ');
      if(p.staffId) {
        const member=(await tx.get(ctx.shop.collection('staff').doc(p.staffId))).data();
        if(!member || member.active===false || Number(member.sessionVersion||0)!==p.staffVersion)review.push('สิทธิ์พนักงานเปลี่ยนก่อนซิงก์');
      }
      for(const [id,qty] of quantities) {
        const ref=ctx.shop.collection('products').doc(id), current=(await tx.get(ref)).data(), snapshot=products.get(id);
        if(!current){review.push('สินค้าถูกลบ: '+snapshot.name);continue;}
        if((current.stockMode||'count')!==snapshot.stockMode){review.push('วิธีนับสต็อกเปลี่ยน: '+snapshot.name);continue;}
        if(Math.abs(effectivePriceOf(current,now())-snapshot.price)>0.009)review.push('ราคาเปลี่ยน: '+snapshot.name);
        if(snapshot.stockMode==='recipe')review.push('ตรวจวัตถุดิบตามสูตรขณะซิงก์: '+snapshot.name);
        if(snapshot.stockMode!=='recipe') {
          if(Number(current.stock||0)<qty)review.push('สต็อกติดลบ: '+snapshot.name);
          updates.push({ref,qty});
        }
      }
      const receiptNo='O-'+data.id;
      tx.create(saleRef,{items,total,paid:data.paid,change:Math.round((data.paid-total)*100)/100,discount:0,paymentMethod:'cash',isDebt:false,isRefunded:false,
        createdAt:Timestamp.fromDate(sold),syncedAt:Timestamp.fromDate(now()),receiptNo,staffName:p.name,staffId:p.staffId,staffUid:p.uid,
        offline:true,offlinePermitId:data.permitId,offlineDigest:digest,offlineReview:review,needsReview:review.length>0});
      for(const u of updates)tx.update(u.ref,{stock:FieldValue.increment(-u.qty)});
      return {id:data.id,receiptNo,review};
    });
  }
  return {prepare,sync};
}
module.exports={createOfflineSales};
