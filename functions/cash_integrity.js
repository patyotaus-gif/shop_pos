'use strict';
const {minor,saleMovement}=require('./money_ledger');
const {inspectOpenWork}=require('./cash_close_work');
const LIMIT=10000;

// All reads run inside the same transaction as close. Payment writers also
// update cashControl/current, so a payment racing close forces a fresh check.
async function inspectClose(tx,shop,sessionId,session,rows,work) {
  work=work||await inspectOpenWork(tx,shop);
  const issues=[...work.issues];
  const problem=(type,id)=>issues.push({type,id});
  const query=async q=>{
    const s=await tx.get(q.limit(LIMIT+1));
    if(s.size>LIMIT)problem('tooManyRecords','');
    return s.docs.slice(0,LIMIT);
  };
  const cache=new Map();
  const read=(collection,id)=>{
    if(typeof id!=='string'||!id||id.includes('/'))return Promise.resolve(null);
    const key=collection+'/'+id;
    if(!cache.has(key))cache.set(key,tx.get(shop.collection(collection).doc(id)));
    return cache.get(key);
  };
  if(!session.openedAt)problem('missingOpeningTime',sessionId);
  // Activation is an explicit migration boundary, not a claim that legacy
  // records were repaired. Earlier gaps remain visible in accounting review.
  const start=session.accountingStartAt;
  const unassignedQuery=start
    ? shop.collection('moneyMovements').where('recordedAt','>=',start)
    : shop.collection('moneyMovements').where('needsReconciliation','==',true);
  const unassigned=(await query(unassignedQuery)).filter(d=>d.data().needsReconciliation===true);
  for(const d of unassigned)problem('unassignedMovement',d.id);
  // Check payments since activation, including orders created earlier but paid later.
  // Earlier gaps remain in the separate historical review.
  const orderRows=start
    ? [...await query(shop.collection('orders').where('paidAt','>=',start)),
       ...await query(shop.collection('orders').where('createdAt','>=',start))]
    : await query(shop.collection('orders').where('status','in',['paid','accepted','ready','completed']));
  const orders=[...new Map(orderRows.map(d=>[d.id,d])).values()]
    .filter(d=>['paid','accepted','ready','completed'].includes(d.data().status));
  for(const order of orders){
    const linked=await tx.get(shop.collection('sales').where('orderId','==',order.id).limit(2));
    if(linked.empty)problem('missingSale',order.id);
    else if(linked.size!==1)problem('duplicateSale',order.id);
    else if(linked.docs[0].data().isRefunded)problem('refundedActiveOrder',order.id);
  }
  const expected=new Map();
  const addExpected=(id,data)=>expected.set(id,data);
  if(session.openedAt){
    for(const d of await query(shop.collection('tableOrders').where('closedAt','>=',session.openedAt))){
      if(d.data().status!=='closed')continue;
      const linked=await read('sales',d.data().saleId);
      if(!linked?.exists)problem('missingTableSale',d.id);
    }
    for(const field of ['createdAt','syncedAt']){
      for(const d of await query(shop.collection('sales').where(field,'>=',session.openedAt)))
        addExpected('sale-'+d.id,{kind:'sale',saleId:d.id});
    }
    for(const d of await query(shop.collection('sales').where('refundedAt','>=',session.openedAt)))
      addExpected('refund-'+d.id,{kind:'refund',saleId:d.id});
    for(const d of await query(shop.collection('debtPayments').where('createdAt','>=',session.openedAt)))
      addExpected('debt-'+d.id,{kind:'debtPayment',paymentId:d.id});
  }
  const present=new Set(rows.map(d=>d.id));
  for(const id of expected.keys()){
    if(!present.has(id))problem('missingMovement',id);
  }
  for(const row of rows){
    const r=row.data();
    // Manual drawer entries are immutable, owner-authorized server records.
    // They change cash on hand, never sales, debt or payment-method revenue.
    if(['cashIn','cashOut'].includes(r.kind)){
      if(!row.id.startsWith('cash-')||r.method!=='cash'||r.actor!==shop.id||
          !Number.isSafeInteger(r.amountMinor)||Math.abs(r.amountMinor)>1e11||
          (r.kind==='cashIn'?r.amountMinor<=0:r.amountMinor>=0)||
          r.salesMinor!==0||r.debtMinor!==0||(r.refundMinor||0)!==0||
          typeof r.reason!=='string'||!r.reason.trim()||r.reason.length>300)
        problem('invalidMovement',row.id);
      continue;
    }
    if(!['sale','refund','debtPayment'].includes(r.kind)||
        !['amountMinor','salesMinor','debtMinor'].every(k=>Number.isSafeInteger(r[k]))||
        (r.refundMinor!==undefined&&!Number.isSafeInteger(r.refundMinor))||
        !['cash','transfer','qr','online','credit'].includes(r.method)){
      problem('invalidMovement',row.id);continue;
    }
    try {
      const sale=await read('sales',r.saleId);
      if(!sale?.exists){problem('missingSource',row.id);continue;}
      const s=sale.data();let expectedValues;
      if(r.kind==='sale'){
        if(row.id!=='sale-'+r.saleId)problem('duplicateMovement',row.id);
        expectedValues=saleMovement(s,null);
      }else if(r.kind==='refund'){
        if(row.id!=='refund-'+r.saleId||!s.isRefunded)problem('invalidRefund',row.id);
        const paid=minor(s.refundAmount);
        expectedValues={amountMinor:-paid,salesMinor:-minor(s.total),refundMinor:paid,
          debtMinor:s.isDebt?-(minor(s.total)-paid):0,method:s.refundMethod};
      }else{
        const p=await read('debtPayments',row.id.startsWith('debt-')?row.id.slice(5):null);
        if(!p?.exists){problem('missingSource',row.id);continue;}
        const payment=p.data();
        if(payment.saleId!==r.saleId||payment.debtId!==r.debtId)problem('wrongSource',row.id);
        expectedValues={amountMinor:payment.amountMinor,salesMinor:0,debtMinor:-payment.amountMinor,method:payment.method};
      }
      for(const key of ['amountMinor','salesMinor','debtMinor','method']){
        if(r[key]!==expectedValues[key]){problem('amountMismatch',row.id);break;}
      }
      if((r.refundMinor||0)!==(expectedValues.refundMinor||0))problem('amountMismatch',row.id);
    }catch(_){problem('invalidSource',row.id);}
  }
  return {...work,issues,checkedMovementCount:rows.length};
}
const labels={pendingOrder:'ออเดอร์ยังรอชำระ',openTable:'บิลโต๊ะยังไม่ปิด',unfinishedOrder:'ออเดอร์จ่ายแล้วแต่ยังไม่เสร็จสิ้น',
  unassignedMovement:'เงินยังไม่ผูกกับรอบ',missingSale:'ออเดอร์รับเงินแล้วไม่มีบิลขาย',
  duplicateSale:'บิลขายซ้ำ',refundedActiveOrder:'คืนเงินแล้วแต่สถานะออเดอร์ไม่ตรง',
  missingMovement:'รายการขายหรือรับเงินยังลงประวัติเงินไม่ครบ',invalidMovement:'ข้อมูลเงินไม่ถูกต้อง',
  missingSource:'ไม่พบเอกสารต้นทาง',duplicateMovement:'ประวัติเงินซ้ำ',invalidRefund:'ข้อมูลคืนเงินไม่ตรง',
  wrongSource:'เอกสารอ้างอิงไม่ตรง',amountMismatch:'ยอดเงินไม่ตรงกับเอกสารต้นทาง',
  invalidSource:'ข้อมูลต้นทางไม่ครบ',tooManyRecords:'ข้อมูลเกินขอบเขตตรวจ ต้องตรวจเพิ่ม',missingOpeningTime:'ไม่พบเวลาเปิดรอบ',
  unreviewedPayment:'มีสลิปหรือยอดโอนที่ร้านยังไม่ได้ตรวจยืนยัน',missingTableSale:'ปิดบิลโต๊ะแล้วแต่ไม่มีรายการขาย'};
function closeError(issues){
  return 'ยังปิดรอบไม่ได้: '+issues.slice(0,3).map(x=>(labels[x.type]||x.type)+(x.id?' ('+x.id+')':'')).join(' · ')+
    (issues.length>3?' และอีก '+(issues.length-3)+' รายการ':'')+' กรุณาจัดการออเดอร์ บิลโต๊ะ และรายการเงินก่อนปิดรอบ';
}
module.exports={inspectClose,closeError,labels};
