'use strict';
const {createHash}=require('node:crypto');
const idOk=s=>typeof s==='string' && /^[A-Za-z0-9_-]{1,128}$/.test(s);
const money=n=>Math.round(n*100)/100;
const validNumber=n=>typeof n==='number' && Number.isFinite(n);
function handlers({db,FieldValue,HttpsError}) {
  const fail=(code,message)=>{throw new HttpsError(code,message);};
  function caller(request) {
    if(!request.auth)fail('unauthenticated','กรุณาเข้าสู่ระบบ');
    if(request.auth.token?.staffRole)fail('permission-denied','เฉพาะเจ้าของบัญชี');
    return request.auth.uid;
  }
  const shopRef=id=>db.collection('shops').doc(id);
  const supplierRef=id=>db.collection('suppliers').doc(id);
  function itemsTotal(items) {
    if(!Array.isArray(items)||!items.length||items.length>100)fail('failed-precondition','ข้อมูลรายการไม่ถูกต้อง กรุณาติดต่อผู้ดูแล');
    let total=0;
    for(const i of items) {
      if(!idOk(i.productId)||!validNumber(i.quantity)||i.quantity<=0||i.quantity>1000000||!validNumber(i.price)||i.price<0||i.price>1e9)
        fail('failed-precondition','ข้อมูลรายการไม่ถูกต้อง กรุณาติดต่อผู้ดูแล');
      total+=money(i.price*i.quantity);
    }
    if(!Number.isFinite(total)||total>1e9)fail('failed-precondition','ยอดสั่งซื้อไม่ถูกต้อง');
    return money(total);
  }
  function matching(shopOrder,supplierOrder,shopId,supplierId) {
    if(!shopOrder||!supplierOrder||shopOrder.shopId!==shopId||supplierOrder.shopId!==shopId||shopOrder.supplierId!==supplierId||supplierOrder.supplierId!==supplierId||shopOrder.status!==supplierOrder.status||JSON.stringify(shopOrder.items)!==JSON.stringify(supplierOrder.items))
      fail('failed-precondition','ข้อมูลออเดอร์สองฝั่งไม่ตรงกัน กรุณาติดต่อผู้ดูแล');
    itemsTotal(shopOrder.items);
  }
  async function place(request) {
    const uid=caller(request), {supplierId,requestId,items,expectedTotal}=request.data||{};
    if(request.data?.shopId!==undefined && request.data.shopId!==uid)fail('permission-denied','บัญชีร้านเปลี่ยน กรุณาเปิดหน้าสั่งซื้อใหม่');
    if(!idOk(supplierId)||!idOk(requestId)||requestId.length<10||!Array.isArray(items)||!items.length||items.length>100||!validNumber(expectedTotal)||expectedTotal<0||expectedTotal>1e9)
      fail('invalid-argument','ข้อมูลสั่งซื้อไม่ถูกต้อง');
    const seen=new Set();
    const lines=items.map(i=>{
      if(!idOk(i?.productId)||seen.has(i.productId)||!validNumber(i.quantity)||i.quantity<=0||i.quantity>1000000)
        fail('invalid-argument','จำนวนสินค้าไม่ถูกต้อง');
      seen.add(i.productId);return {productId:i.productId,quantity:i.quantity};
    }).sort((a,b)=>a.productId.localeCompare(b.productId));
    const digest=createHash('sha256').update(JSON.stringify({supplierId,lines,expectedTotal})).digest('hex');
    // Namespace by purchaser even when two shops submit the same client request id.
    const orderId='mp_'+createHash('sha256').update(uid+':'+requestId).digest('hex');
    const shop=shopRef(uid), supplier=supplierRef(supplierId);
    const own=shop.collection('marketplaceOrders').doc(orderId), other=supplier.collection('orders').doc(orderId);
    return db.runTransaction(async tx=>{
      const [s,sup,prior,mirror]=await Promise.all([tx.get(shop),tx.get(supplier),tx.get(own),tx.get(other)]);
      if(!s.exists||!sup.exists)fail('not-found','ไม่พบร้านหรือซัพพลายเออร์');
      if(prior.exists) {
        if(prior.data().requestDigest!==digest)fail('already-exists','คำขอเดิมมีข้อมูลต่างกัน');
        matching(prior.data(),mirror.data(),uid,supplierId);
        return {orderId,replayed:true};
      }
      if(mirror.exists)fail('failed-precondition','ออเดอร์สองฝั่งไม่ตรงกัน');
      if(sup.data().active===false)fail('failed-precondition','ซัพพลายเออร์ปิดรับออเดอร์');
      const priced=[];
      for(const i of lines) {
        const snapshot=await tx.get(supplier.collection('products').doc(i.productId)),p=snapshot.data();
        if(!p||p.available===false)fail('failed-precondition','สินค้าปิดขาย กรุณาโหลดใหม่');
        if(!validNumber(p.price)||p.price<0||p.price>1e9||!validNumber(p.moq??1)||(p.moq??1)<=0||i.quantity<(p.moq??1))fail('failed-precondition','ราคาหรือจำนวนขั้นต่ำเปลี่ยน กรุณาโหลดใหม่');
        priced.push({...i,name:String(p.name||'').slice(0,200),unit:String(p.unit||'ชิ้น').slice(0,40),price:p.price});
      }
      const total=itemsTotal(priced),min=sup.data().minOrder??0;
      if(!validNumber(min)||min<0||total<min)fail('failed-precondition','ยอดสั่งซื้อต่ำกว่าขั้นต่ำ');
      if(Math.abs(total-expectedTotal)>0.009)fail('failed-precondition','ราคาเปลี่ยน กรุณาโหลดสินค้าใหม่ก่อนสั่ง');
      const order={shopId:uid,supplierId,shopName:String(s.data().name||'ร้านค้า').slice(0,200),supplierName:String(sup.data().name||'').slice(0,200),items:priced,status:'placed',total,takeRate:0,createdAt:FieldValue.serverTimestamp(),requestDigest:digest,schemaVersion:1};
      tx.create(own,order);tx.create(other,order);
      return {orderId,replayed:false};
    });
  }
  async function transition(request,side) {
    const uid=caller(request), {orderId,status}=request.data||{};
    if(!idOk(orderId)||!(side==='supplier'?['accepted','shipped','cancelled']:['cancelled','delivered']).includes(status))fail('invalid-argument','สถานะไม่ถูกต้อง');
    return db.runTransaction(async tx=>{
      const actor=side==='supplier'?supplierRef(uid):shopRef(uid);
      const ref=actor.collection(side==='supplier'?'orders':'marketplaceOrders').doc(orderId);
      const [profile,snapshot]=await Promise.all([tx.get(actor),tx.get(ref)]),order=snapshot.data();
      if(!profile.exists||!order)fail('not-found','ไม่พบออเดอร์หรือบัญชี');
      if(!idOk(order.shopId)||!idOk(order.supplierId)||(side==='supplier'?order.supplierId:order.shopId)!==uid)fail('permission-denied','ไม่มีสิทธิ์จัดการออเดอร์');
      const mirror=(side==='supplier'?shopRef(order.shopId).collection('marketplaceOrders'):supplierRef(order.supplierId).collection('orders')).doc(orderId);
      const other=(await tx.get(mirror)).data();
      matching(side==='shop'?order:other,side==='supplier'?order:other,order.shopId,order.supplierId);
      if(order.status===status)return {ok:true,replayed:true};
      const allowed=side==='supplier'?{placed:['accepted','cancelled'],accepted:['shipped','cancelled']}:{placed:['cancelled'],accepted:['cancelled'],shipped:['delivered']};
      if(!allowed[order.status]?.includes(status))fail('failed-precondition','สถานะออเดอร์เปลี่ยนแล้ว กรุณาโหลดใหม่');
      const patch={status,updatedAt:FieldValue.serverTimestamp(),updatedBy:uid};
      if(status==='delivered')Object.assign(patch,{takeRate:money(itemsTotal(order.items)*0.025),deliveredAt:FieldValue.serverTimestamp()});
      tx.update(ref,patch);tx.update(mirror,patch);
      return {ok:true,replayed:false};
    });
  }
  return {place,supplierTransition:r=>transition(r,'supplier'),shopTransition:r=>transition(r,'shop')};
}
module.exports={handlers};
