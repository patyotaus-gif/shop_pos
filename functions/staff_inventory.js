'use strict';
const {createHash}=require('node:crypto');
const access=require('./staff_permissions');
const stock=require('./stock_quantity');
const idOk=v=>typeof v==='string'&&/^[\w-]{1,128}$/.test(v);
const grants=['stock','stockReceive','stockWaste','stockHistory','cost'];
const actions=['inventoryProducts','inventoryProduct','stockHistory','stockReceive','stockWaste','stockCount'];
const can=(ctx,key)=>!ctx.staffId||ctx.permissions?.[key]===true;
function product(id,p,ctx){
 return {id,name:p.name||'',barcode:p.barcode||'',sku:p.sku||'',price:p.price||0,
  stock:p.stock||0,stockRevision:p.stockRevision||0,unit:p.unit||'ชิ้น',isWeighed:p.isWeighed===true,
  trackLots:p.trackLots===true,stockMode:p.stockMode||'own',
  stockLots:(p.stockLots||[]).map(l=>({id:l.id,number:l.number,expiresOn:l.expiresOn,quantity:l.quantity})),
  ...(can(ctx,'cost')?{unitCost:p.costPrice||0}:{})};
}
function handler({db,FieldValue,HttpsError}){
 const fail=m=>{throw new HttpsError('failed-precondition',m);};
 return async(request,ctx)=>{
  const raw=request.data,shop=db.collection('shops').doc(ctx.shopId);
  if(ctx.staffId&&!grants.some(k=>can(ctx,k)))throw new HttpsError('permission-denied','ไม่มีสิทธิ์จัดการสต๊อก');
  if(raw.action==='inventoryProducts'){
   const search=raw.search??'',mode=raw.mode??'name';
   if(typeof search!=='string'||search.length>150||!['name','barcode','sku'].includes(mode))fail('คำค้นไม่ถูกต้อง');
   const term=search.trim(),collection=shop.collection('products');
   let q=collection.orderBy('name');
   if(term)q=mode==='name'?q.startAt(term).endAt(term+'\uf8ff'):collection.where(mode,'==',term);
   if(raw.cursor){
    if(!idOk(raw.cursor))fail('หน้ารายการไม่ถูกต้อง');
    const cursor=await collection.doc(raw.cursor).get();
    if(!cursor.exists)fail('รายการเปลี่ยนแล้ว กรุณาค้นหาใหม่');
    q=q.startAfter(cursor);
   }
   const rows=await q.limit(51).get(),page=rows.docs.slice(0,50);
   return {records:page.map(d=>product(d.id,d.data(),ctx)),nextCursor:rows.size>50?page.at(-1).id:null};
  }
  if(!idOk(raw.productId))fail('รหัสสินค้าไม่ถูกต้อง');
  const ref=shop.collection('products').doc(raw.productId);
  if(raw.action==='inventoryProduct'){
   const p=await ref.get();if(!p.exists)fail('ไม่พบสินค้า');
   const held=(await shop.collection('inventoryControl').doc('online').get()).data()?.products?.[ref.id]||0;
   return {record:{...product(p.id,p.data(),ctx),reserved:held,available:Math.max(0,stock.round(stock.available(p.data())-held))}};
  }
  if(raw.action==='stockHistory'){
   await access.authorize(request,db,HttpsError,'stockHistory');
   let q=ref.collection('stockMovements').orderBy('createdAt','desc');
   if(raw.from!=null||raw.to!=null){
    const from=new Date(raw.from),to=new Date(raw.to);
    if(typeof raw.from!=='string'||typeof raw.to!=='string'||!Number.isFinite(+from)||!Number.isFinite(+to)||to<=from)fail('ช่วงวันที่ไม่ถูกต้อง');
    q=q.where('createdAt','>=',from).where('createdAt','<',to);
   }
   if(raw.cursor){
    if(!idOk(raw.cursor))fail('หน้าประวัติไม่ถูกต้อง');
    const cursor=await ref.collection('stockMovements').doc(raw.cursor).get();
    if(!cursor.exists)fail('ประวัติเปลี่ยนแล้ว กรุณาโหลดใหม่');
    q=q.startAfter(cursor);
   }
   const rows=await q.limit(41).get(),page=rows.docs.slice(0,40);
   const refs=[...new Set(page.map(d=>d.data().referenceId).filter(idOk))];
   const sales=refs.length?await db.getAll(...refs.map(id=>shop.collection('sales').doc(id))):[];
   const saleData=new Map(sales.filter(d=>d.exists).map(d=>[d.id,d.data()]));
   return {records:page.map(d=>{const m=d.data();return {id:d.id,kind:m.kind,delta:m.delta,before:m.before,after:m.after,unit:m.unit||'',reason:m.reason||'',
    createdAt:m.createdAt?.toDate().toISOString()||null,
    saleAt:m.kind==='sale'?saleData.get(m.referenceId)?.createdAt?.toDate().toISOString()||null:null,
    actorName:m.actorName||(m.kind==='sale'?saleData.get(m.referenceId)?.staffName:null)||(m.actor===ctx.shopId?'เจ้าของร้าน':'ไม่ระบุชื่อ (บันทึกเดิม)'),
    referenceId:m.referenceId||'',documentNumber:m.documentNumber||'',
    lots:(m.lots||(m.lot?[m.lot]:[])).map(l=>({number:l.number,expiresOn:l.expiresOn,quantity:l.quantity})),
    ...(can(ctx,'cost')&&typeof m.totalCost==='number'?{totalCost:m.totalCost}:{})};}),nextCursor:rows.size>40?page.at(-1).id:null};
  }
  const kind={stockReceive:'receive',stockWaste:'waste',stockCount:'count'}[raw.action];
  if(!kind)fail('คำสั่งไม่ถูกต้อง');
  await access.authorize(request,db,HttpsError,{receive:'stockReceive',waste:'stockWaste',count:'stock'}[kind]);
  if(!idOk(raw.requestId)||typeof raw.reason!=='string'||!raw.reason.trim()||raw.reason.length>300)fail('ระบุเหตุผลไม่เกิน 300 ตัวอักษร');
  if(!Number.isInteger(raw.expectedRevision)||raw.expectedRevision<0)fail('กรุณาโหลดสต๊อกล่าสุด');
  if(raw.lotId!=null&&!idOk(raw.lotId))fail('รหัสล็อตไม่ถูกต้อง');
  const documentNumber=raw.documentNumber??'';
  if(typeof documentNumber!=='string'||documentNumber.length>100)fail('เลขเอกสารยาวเกินไป');
  const totalCost=raw.totalCost??null;
  if(totalCost!==null){
   await access.authorize(request,db,HttpsError,'cost');
   if(kind!=='receive'||typeof totalCost!=='number'||!Number.isFinite(totalCost)||totalCost<0||totalCost>1e9||Math.abs(totalCost*100-Math.round(totalCost*100))>1e-6)fail('ต้นทุนรวมไม่ถูกต้อง');
  }
  const payload={kind,quantity:raw.quantity,lotId:raw.lotId||null,lotNumber:raw.lotNumber??null,expiresOn:raw.expiresOn??null,reason:raw.reason.trim(),documentNumber:documentNumber.trim(),totalCost};
  const digest=createHash('sha256').update(JSON.stringify(payload)).digest('hex');
  const movement=ref.collection('stockMovements').doc('staff-'+raw.requestId);
  return require('./transaction_retry').runTransaction(db,async tx=>{
   await access.recheck(tx,shop,request,HttpsError);
   const [snapshot,prior,control]=await Promise.all([tx.get(ref),tx.get(movement),tx.get(shop.collection('inventoryControl').doc('online'))]);
   if(prior.exists){
    const m=prior.data();
    const legacy=kind==='count'&&!m.requestDigest&&m.kind==='count'&&m.counted===raw.quantity&&m.lotId===payload.lotId&&m.reason===payload.reason&&totalCost===null&&!documentNumber&&!raw.lotNumber&&!raw.expiresOn;
    if(m.actor!==ctx.actor||(!legacy&&m.requestDigest!==digest))fail('รหัสคำขอซ้ำกับรายการอื่น');
    return {success:true,alreadyRecorded:true};
   }
   const p=snapshot.data();if(!p||p.stockMode==='recipe')fail('สินค้าตามสูตรต้องจัดการที่วัตถุดิบ');
   if(Number(p.stockRevision||0)!==raw.expectedRevision)fail('สต๊อกเปลี่ยนแล้ว กรุณาโหลดใหม่และตรวจสอบจำนวน');
   if(!stock.valid(raw.quantity,p.isWeighed===true,kind==='count'))fail('จำนวนไม่ถูกต้อง');
   let lots=p.trackLots?stock.lotsOf(p):null,lot=null;
   if(lots){
    if(kind==='receive'&&!raw.lotId){
     if(typeof raw.lotNumber!=='string'||!raw.lotNumber.trim()||raw.lotNumber.length>100||typeof raw.expiresOn!=='string'||!/^\d{4}-\d{2}-\d{2}$/.test(raw.expiresOn)||!Number.isFinite(Date.parse(raw.expiresOn))||new Date(raw.expiresOn).toISOString().slice(0,10)!==raw.expiresOn)fail('ระบุเลขล็อตและวันหมดอายุให้ถูกต้อง');
     lots=lots.filter(l=>l.quantity>0);if(lots.length>=200)fail('ล็อตสินค้าถึงขีดจำกัด');
     if(lots.some(l=>l.id===raw.requestId))fail('รหัสล็อตซ้ำ');
     lot={id:raw.requestId,number:raw.lotNumber.trim(),expiresOn:raw.expiresOn,quantity:0};lots.push(lot);
    }else{lot=lots.find(l=>l.id===raw.lotId);if(!lot)fail('เลือกล็อตสินค้า');}
   }else if(raw.lotId||raw.lotNumber||raw.expiresOn)fail('สินค้านี้ไม่ได้ติดตามล็อต');
   const base=lot?lot.quantity:Number(p.stock||0);
   const delta=stock.round(kind==='count'?raw.quantity-base:kind==='waste'?-raw.quantity:raw.quantity);
   const after=stock.round(Number(p.stock||0)+delta);
   if(lot){lot.quantity=stock.round(base+delta);if(lot.quantity<0)fail('จำนวนในล็อตไม่พอ');}
   if(!stock.valid(after,p.isWeighed===true,true))fail('จำนวนคงเหลือไม่ถูกต้อง');
   const update={stock:after,...(lots?{stockLots:lots}:{})};
   const reserved=Number(control.data()?.products?.[ref.id]||0);
   if(delta<0&&stock.available({...p,...update})+1e-9<reserved)fail('ลดสต๊อกไม่ได้ มีสินค้าจองออนไลน์ กรุณาตรวจออเดอร์ก่อน');
   if(totalCost!==null){
    const previousCost=Number(p.costPrice||0);if(!Number.isFinite(previousCost)||previousCost<0)fail('ต้นทุนเดิมไม่ถูกต้อง กรุณาให้เจ้าของร้านตรวจสอบ');
    update.costPrice=(Math.max(0,Number(p.stock||0))*previousCost+totalCost)/(Math.max(0,Number(p.stock||0))+delta);
   }
   stock.write(tx,ref,p,update,{id:movement.id,kind,actor:ctx.actor,reason:payload.reason},FieldValue);
   tx.set(movement,{requestDigest:digest,actorName:ctx.name||'เจ้าของร้าน',staffId:ctx.staffId||null,
    counted:kind==='count'?raw.quantity:null,lotId:lot?.id||null,documentNumber:payload.documentNumber,totalCost,
    ...(lot?{lot:{number:lot.number,expiresOn:lot.expiresOn,quantity:Math.abs(delta)}}:{})},{merge:true});
   return {success:true};
  });
 };
}
module.exports={handler,actions,product,can};
