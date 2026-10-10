'use strict';
const {owner,validId}=require('./order_accounting');
const {ledgerContext}=require('./money_ledger');
const {inspectMovementRows}=require('./cash_integrity');

// Assign an existing, verified movement once. Never recreate money, stock or
// sales, and never revise a closed Z-report. The owner decides drawer treatment.
function handler({db,FieldValue,HttpsError}) {
  return async request=>{
    const shop=db.collection('shops').doc(owner(request,HttpsError));
    const {movementId,sessionId,reason,cashTreatment,expectedAmountMinor}=request.data;
    const fail=message=>{throw new HttpsError('failed-precondition',message);};
    if(!validId(movementId)||!validId(sessionId)||!Number.isSafeInteger(expectedAmountMinor)||
       typeof reason!=='string'||!reason.trim()||reason.trim().length>300||
       !['addToDrawer','includedInOpeningFloat','nonCash'].includes(cashTreatment))
      throw new HttpsError('invalid-argument','ตรวจรายการ เลือกวิธีนับเงิน และระบุเหตุผลก่อนยืนยัน');
    return db.runTransaction(async tx=>{
      const ref=shop.collection('moneyMovements').doc(movementId);
      const snap=await tx.get(ref);
      if(!snap.exists)fail('ไม่พบรายการเงิน');
      const m=snap.data();
      if(m.reconciliation){
        const r=m.reconciliation;
        if(m.sessionId!==sessionId||m.amountMinor!==expectedAmountMinor||r.reason!==reason.trim()||r.cashTreatment!==cashTreatment)
          fail('รายการนี้จัดเข้ารอบแล้ว กรุณาโหลดข้อมูลใหม่');
        return {id:movementId,alreadyAssigned:true};
      }
      if(m.needsReconciliation!==true||m.sessionId!=null||m.amountMinor!==expectedAmountMinor)
        fail('รายการเปลี่ยนแล้วหรือผูกกับรอบอยู่แล้ว กรุณาโหลดข้อมูลใหม่');
      if(!['sale','refund','debtPayment'].includes(m.kind))fail('รายการประเภทนี้ต้องตรวจสอบเพิ่มเติม');
      if((m.method==='cash')===(cashTreatment==='nonCash'))fail('วิธีนับเงินไม่ตรงกับรายการ');
      const context=await ledgerContext(tx,shop);
      const session=await tx.get(shop.collection('cashSessions').doc(sessionId));
      if(context.sessionId!==sessionId||session.data()?.status!=='open'||session.data()?.accountingVersion!==1)
        fail('ต้องเลือกรอบขายปัจจุบันที่ยังเปิดอยู่');
      const issues=await inspectMovementRows(tx,shop,[snap]);
      if(issues.length)throw new HttpsError('failed-precondition','ยอดเงินไม่ตรงกับเอกสารต้นทาง ต้องตรวจสอบก่อนจัดเข้ารอบ',{issues});
      tx.update(ref,{sessionId,needsReconciliation:false,reconciliation:{
        previousSessionId:null,previousNeedsReconciliation:true,
        actor:request.auth.uid,at:FieldValue.serverTimestamp(),reason:reason.trim(),cashTreatment,
      }});
      tx.set(context.ref,{revision:FieldValue.increment(1)},{merge:true});
      return {id:movementId,alreadyAssigned:false};
    });
  };
}
module.exports={handler};
