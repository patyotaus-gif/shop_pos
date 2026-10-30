'use strict';
const {authorize}=require('./staff_permissions');
const {randomUUID}=require('node:crypto');
const validId=v=>typeof v==='string'&&/^[\w-]{1,128}$/.test(v);
// Only operational fields cross the staff boundary. Never expose whole shop documents.
const fields={
 tables:'name capacity section status currentOrderId createdAt',
 tableOrders:'tableId tableName items status openedAt closedAt saleId tablePromotion',
 orders:'orderNumber queueNumber queueChannel queueSessionId customerName customerPhone items total discount coupon bundleDiscount bundles finalAmount paymentMethod paymentRef slipUrl autoConfirmed bankMatchStatus status createdAt paidAt statusUpdatedAt orderType tableName pickupMode pickupStartAt pickupEndAt pickupLabel saleId',
 sales:'queueNumber queueChannel queueSessionId items total discount bundleDiscount bundles serviceCharge serviceChargePercent paid change paymentMethod salesChannel isDebt isRefunded createdAt staffName staffId receiptNo receiptProfile tableName splitCount customerName refundReason refundedAt',
 cashSessions:'openedAt openedBy openedByName closedAt closedBy closedByName openingFloat countedCash status summary accountingVersion accountingStartAt needsReconciliation nextSessionId previousSessionId carriedCash',
 accountingSettings:'enabled defaultOpeningFloat',
};
function clean(value){
 if(value?.toDate)return value.toDate().toISOString();
 if(value instanceof Date)return value.toISOString();
 if(Array.isArray(value))return value.map(clean);
 if(value&&typeof value==='object')return Object.fromEntries(Object.entries(value)
  .filter(([key])=>!['costPrice','costKnown','costAdjust','cost','pin','pinHash','pinSalt'].includes(key)).map(([k,v])=>[k,clean(v)]));
 return value;
}
function project(collection,data){return clean(Object.fromEntries(fields[collection].split(' ').filter(k=>data[k]!==undefined).map(k=>[k,data[k]])));}
function handler({db,FieldValue,HttpsError}){
 const fail=message=>{throw new HttpsError('failed-precondition',message);};
 return async request=>{
  const raw=request.data||{};
  const ctx=await authorize(request,db,HttpsError);
  const shop=db.collection('shops').doc(ctx.shopId);
  if(require('./staff_inventory').actions.includes(raw.action))return require('./staff_inventory').handler({db,FieldValue,HttpsError})(request,ctx);
  if(raw.action==='report'){
   await authorize(request,db,HttpsError,'reports');
   const from=new Date(raw.from),to=new Date(raw.to);
   if(!Number.isFinite(+from)||!Number.isFinite(+to)||to<=from||to-from>32*86400000)fail('เลือกช่วงวันที่ไม่เกิน 31 วัน');
   const rows=await shop.collection('sales').where('createdAt','>=',from).where('createdAt','<',to).limit(2001).get();
   if(rows.size>2000)fail('รายการมากเกินไป กรุณาเลือกช่วงวันที่สั้นลง');
   return {records:rows.docs.map(d=>({id:d.id,...project('sales',d.data())}))};
  }
  if(raw.action==='products'){
   if(!ctx.permissions?.cost&&!ctx.permissions?.stock&&ctx.staffId)throw new HttpsError('permission-denied','ไม่มีสิทธิ์ดูต้นทุนหรือปรับสต๊อก');
   const rows=await shop.collection('products').limit(501).get();
   if(rows.size>500)fail('รายการมากเกินไป กรุณาให้เจ้าของร้านจัดการสินค้า');
   return {records:rows.docs.map(d=>{const p=d.data();return clean({id:d.id,name:p.name,stock:p.stock||0,stockRevision:p.stockRevision||0,unit:p.unit||'ชิ้น',isWeighed:p.isWeighed===true,trackLots:p.trackLots===true,stockMode:p.stockMode||'own',stockLots:p.stockLots||[],...(ctx.permissions?.cost?{unitCost:p.costPrice||0}:{})});})};
  }
  if(raw.action==='read'){
   if(raw.collection==='kitchenOrders'){
    // Include legacy paid tabs with unfinished food. Page the source rather
    // than truncating after historical bills; only operational rows cross the boundary.
    const records=new Map();
    const readAt=new Date();
    const since=raw.kitchenSince===undefined?null:new Date(raw.kitchenSince);
    if(since&&(!Number.isFinite(+since)||since>readAt))fail('เวลาคิวครัวไม่ถูกต้อง');
    const known=raw.kitchenPendingIds||[];
    if(!Array.isArray(known)||known.length>500||known.some(id=>!validId(id)))fail('รายการคิวครัวไม่ถูกต้อง');
    const add=d=>{
     if(!d.exists){records.delete(d.id);return;}
     const o=d.data(),items=o.items||[];
     if((o.status==='open'&&items.some(i=>['sent','ready'].includes(i.kitchenStatus)))||
        (o.status==='closed'&&items.some(i=>i.kitchenStatus==='sent')))
      records.set(d.id,{id:d.id,...project('tableOrders',o)});
     else records.delete(d.id);
    };
    let cursor;
    const base=since?shop.collection('tableOrders').where('status','==','open'):
      shop.collection('tableOrders').where('status','in',['open','closed']);
    do {
     const page=await (cursor?base.startAfter(cursor):base).limit(400).get();
     page.docs.forEach(add);
     if(records.size>500)fail('งานครัวค้างเกิน 500 บิล กรุณาให้เจ้าของร้านตรวจสอบ');
     cursor=page.size===400?page.docs[page.docs.length-1]:null;
    }while(cursor);
    if(since){
     // A short overlap covers timestamp/commit races. Older pending paid bills
     // are reread by ID, so completion and cancellation remove them promptly.
     const recent=await shop.collection('tableOrders').where('closedAt','>=',new Date(+since-60000)).get();
     recent.docs.forEach(add);
     if(known.length)(await db.getAll(...known.map(id=>shop.collection('tableOrders').doc(id)))).forEach(add);
    }
    if(records.size>500)fail('งานครัวค้างเกิน 500 บิล กรุณาให้เจ้าของร้านตรวจสอบ');
    return {records:[...records.values()],kitchenSince:readAt.toISOString()};
   }
   if(!Object.hasOwn(fields,raw.collection))throw new HttpsError('permission-denied','ไม่มีสิทธิ์อ่านข้อมูลนี้');
   let q=shop.collection(raw.collection);
   if(['cashSessions','accountingSettings'].includes(raw.collection))await authorize(request,db,HttpsError,'cashSession');
   if(raw.id!==undefined){
    if(!validId(raw.id))fail('รหัสไม่ถูกต้อง');
    const d=await q.doc(raw.id).get();
    if(!d.exists&&raw.collection==='accountingSettings'&&raw.id==='current')return {record:{id:'current',enabled:false,defaultOpeningFloat:0}};
    if(!d.exists)fail('ไม่พบรายการ');
    return {record:{id:d.id,...project(raw.collection,d.data())}};
   }
   if(raw.collection==='sales')throw new HttpsError('permission-denied','เลือกใบเสร็จจากออเดอร์');
   if(raw.collection==='accountingSettings')throw new HttpsError('permission-denied','ระบุการตั้งค่ารอบ');
   if(raw.collection==='cashSessions')q=q.orderBy('openedAt','desc').limit(30);
   if(raw.collection==='tableOrders')q=q.where('status','==','open');
   if(raw.collection==='orders')q=q.where('status','in',['pendingPayment','paid','accepted','ready']);
   const rows=await (raw.collection==='cashSessions'?q:q.limit(501)).get();
   if(rows.size>500)fail('รายการเกิน 500 รายการ กรุณาให้เจ้าของร้านตรวจรายการค้าง');
   if(raw.collection==='orders'){
    const recent=await shop.collection('orders').orderBy('createdAt','desc').limit(100).get();
    const merged=new Map([...recent.docs,...rows.docs].map(d=>[d.id,d]));
    return {records:[...merged.values()].map(d=>({id:d.id,...project('orders',d.data())}))};
   }
   return {records:rows.docs.map(d=>({id:d.id,...project(raw.collection,d.data())}))};
  }
  if(!['open','add','quantity','ready'].includes(raw.action))fail('คำสั่งไม่ถูกต้อง');
  if(!validId(raw.action==='open'?raw.tableId:raw.orderId))fail('รหัสไม่ถูกต้อง');
  const ref=shop.collection('tableOrders').doc(raw.action==='open'?randomUUID():raw.orderId);
  return require('./transaction_retry').runTransaction(db,async tx=>{
   await require('./staff_permissions').recheck(tx,shop,request,HttpsError);
   const audit={updatedBy:ctx.actor,updatedByName:ctx.name,updatedAt:FieldValue.serverTimestamp()};
   if(raw.action==='open'){
    const tableRef=shop.collection('tables').doc(raw.tableId),table=(await tx.get(tableRef)).data();
    if(!table)fail('ไม่พบโต๊ะ');
    const existing=await tx.get(shop.collection('tableOrders').where('tableId','==',raw.tableId).where('status','==','open').limit(2));
    if(existing.size>1)fail('พบหลายบิลในโต๊ะเดียวกัน กรุณาให้เจ้าของร้านตรวจสอบ');
    if(table.currentOrderId){
     if(existing.size!==1||existing.docs[0].id!==table.currentOrderId)fail('สถานะโต๊ะไม่ตรงกับบิล กรุณาให้เจ้าของร้านตรวจสอบ');
     return {orderId:table.currentOrderId};
    }
    if(existing.size||table.status==='occupied')fail('โต๊ะยังมีบิลค้าง กรุณาให้เจ้าของร้านตรวจสอบ');
    tx.create(ref,{tableId:raw.tableId,tableName:table.name,items:[],status:'open',openedAt:FieldValue.serverTimestamp(),openedBy:ctx.actor,openedByName:ctx.name,...audit});
    tx.update(tableRef,{status:'occupied',currentOrderId:ref.id});
    return {orderId:ref.id};
   }
   const order=(await tx.get(ref)).data();
   if(raw.action==='ready'){
    if(!order||!['open','closed'].includes(order.status))fail('บิลนี้ถูกยกเลิกหรือไม่พบรายการ');
    const items=(order.items||[]).map(i=>({...i}));
    const item=items.find(i=>i.id===raw.itemId);
    if(!item)fail('รายการเปลี่ยนแล้ว กรุณาโหลดใหม่');
    if(item.kitchenStatus==='ready')return {success:true};
    if(item.kitchenStatus!=='sent')fail('ยังไม่ได้ส่งรายการเข้าครัว');
    item.kitchenStatus='ready';item.readyAt=new Date();
    item.readyBy=ctx.actor;item.readyByName=ctx.name;
    // Only the original food line is updated. A paid table may already host a
    // new bill; never reopen it or touch its currentOrderId, sale, or stock.
    tx.update(ref,{items,...audit});
    return {success:true};
   }
   if(!order||order.status!=='open')fail('บิลนี้ปิดหรือยกเลิกแล้ว');
   const table=(await tx.get(shop.collection('tables').doc(order.tableId))).data();
   if(table?.currentOrderId!==ref.id)fail('โต๊ะเปลี่ยนบิลแล้ว');
   let items=order.items||[];
   if(raw.action==='add'){
    if(!validId(raw.requestId))fail('รหัสคำขอไม่ถูกต้อง');
    const batches=order.appliedItemBatchIds||[];
    if(batches.includes(raw.requestId))return {success:true};
    if(batches.length>=500)fail('บิลมีการแก้ไขมากเกินไป กรุณาปิดบิลก่อน');
    if(!Array.isArray(raw.items)||!raw.items.length||raw.items.length>50||raw.items.some(i=>!validId(i.productId)))fail('รายการไม่ถูกต้อง');
    const productIds=[...new Set(raw.items.map(i=>i.productId))];
    const products=await tx.getAll(...productIds.map(id=>shop.collection('products').doc(id)));
    const groups=await tx.get(shop.collection('modifierGroups'));
    const priced=require('./staff_access').priceCart(raw.items,new Map(products.filter(d=>d.exists).map(d=>[d.id,d.data()])),new Map(groups.docs.map(d=>[d.id,d.data()])),new Date());
    items=[...items,...priced.map(i=>({...i,id:randomUUID(),kitchenStatus:'pending'}))];
    if(items.length>200)fail('บิลรองรับไม่เกิน 200 รายการ');
    tx.update(ref,{items,appliedItemBatchIds:[...batches,raw.requestId],...audit});
   }else{
    const index=items.findIndex(i=>i.id===raw.itemId);
    if(index<0)fail('รายการเปลี่ยนแล้ว กรุณาโหลดใหม่');
    items=items.map(i=>({...i}));
    const item=items[index];
    if(raw.action==='ready'){
     if(item.kitchenStatus==='pending')fail('ยังไม่ได้ส่งรายการเข้าครัว');
     item.kitchenStatus='ready';item.readyAt=new Date();
    }else{
     if(item.isGift)fail('ปรับของแถมผ่านโปรโมชั่นเท่านั้น');
     if(item.quantity!==raw.expectedQuantity)fail('จำนวนถูกเปลี่ยนจากเครื่องอื่นแล้ว');
     const q=raw.quantity;
     if(q!==0&&!require('./stock_quantity').valid(q,item.isWeighed===true)||q>99)fail('จำนวนไม่ถูกต้อง');
     if(item.kitchenStatus!=='pending'){
      if(q<=item.quantity)fail('ส่งครัวแล้ว กรุณาประสานครัวก่อนปรับลด');
      items.push({...item,id:randomUUID(),quantity:q-item.quantity,kitchenStatus:'pending',sentToKitchenAt:null,readyAt:null});
     }else if(q===0)items.splice(index,1);else item.quantity=q;
    }
    if(items.length>200)fail('บิลรองรับไม่เกิน 200 รายการ');
    tx.update(ref,{items,...audit});
   }
   return {success:true};
  });
 };
}
module.exports={handler,project,clean};
