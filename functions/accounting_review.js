'use strict';
const {owner}=require('./order_accounting');
function handler({db,HttpsError}) {
  return async request=>{
    const shop=db.collection('shops').doc(owner(request,HttpsError));
    const [orders,movements,sessions]=await Promise.all([
      shop.collection('orders').where('status','in',['paid','accepted','ready','completed']).limit(201).get(),
      shop.collection('moneyMovements').where('needsReconciliation','==',true).limit(201).get(),
      shop.collection('cashSessions').orderBy('openedAt','desc').limit(101).get(),
    ]);
    const findings=[];
    for(let start=0;start<Math.min(200,orders.docs.length);start+=10){
      const results=await Promise.all(orders.docs.slice(start,Math.min(start+10,200)).map(async o=>{
        const linked=await shop.collection('sales').where('orderId','==',o.id).limit(3).get();
        if(linked.empty)return {type:'missingSale',id:o.id,amount:o.data().finalAmount??o.data().total??0};
        if(linked.size>1)return {type:'duplicateSale',id:o.id,amount:o.data().total??0};
        return null;
      }));findings.push(...results.filter(Boolean));
    }
    for(const m of movements.docs.slice(0,200))findings.push({type:'unassignedMovement',id:m.id,amount:(m.data().amountMinor||0)/100});
    for(const s of sessions.docs.slice(0,100)){
      if(s.data().needsReconciliation || (s.data().status==='open'&&s.data().accountingVersion!==1))
        findings.push({type:'legacySession',id:s.id,amount:s.data().countedCash??s.data().openingFloat??0});
    }
    return {findings,truncated:orders.size>200||movements.size>200||sessions.size>100,
      scope:'ตรวจออเดอร์ที่ชำระแล้วไม่เกิน 200 รายการ เงินนอกรอบไม่เกิน 200 รายการ และรอบล่าสุด 100 รอบ ไม่แก้ข้อมูลอัตโนมัติ'};
  };
}
module.exports={handler};
