'use strict';
const {owner, validId}=require('./order_accounting');
const {minor,ledgerContext,writeMovement,summarizeMovements}=require('./money_ledger');
const {inspectClose,closeError}=require('./cash_integrity');
function handlers({db,FieldValue,HttpsError}) {
  const fail=message=>{throw new HttpsError('failed-precondition',message);};
  return {
    open:async request=>{
      const shop=db.collection('shops').doc(owner(request,HttpsError));
      const openingFloat=request.data.openingFloat;
      if(minor(openingFloat)<0)fail('เงินทอนเริ่มต้นต้องไม่ติดลบ');
      // Stable request id also makes a lost response safe to retry.
      if(!validId(request.data.requestId))fail('Invalid request');
      const ref=shop.collection('cashSessions').doc(request.data.requestId);
      return db.runTransaction(async tx=>{
        const context=await ledgerContext(tx,shop), prior=await tx.get(ref);
        const settingsRef=shop.collection('accountingSettings').doc('current');
        const settings=await tx.get(settingsRef);
        const open=await tx.get(shop.collection('cashSessions').where('status','==','open').limit(2));
        if(prior.exists){
          if(prior.data().status!=='open'||context.sessionId!==ref.id)
            throw new HttpsError('failed-precondition','คำขอเปิดรอบนี้ปิดไปแล้ว กรุณาตรวจประวัติรอบ แล้วเปิดรอบใหม่',{reason:'closed-open-request'});
          if(minor(prior.data().openingFloat)!==minor(openingFloat))fail('คำขอเดิมใช้เงินทอนเริ่มต้นต่างกัน กรุณาตรวจรอบที่เปิดแล้ว');
          return {id:ref.id};
        }
        if(context.sessionId||open.docs.length)fail('มีรอบที่เปิดอยู่แล้ว กรุณาปิดรอบเดิมก่อน');
        if(settings.data()?.enabled!==true && request.data.acknowledgeDeviceUpdate!==true)
          fail('อัปเดตทุกเครื่องและซิงก์บิลให้ครบก่อนเริ่มระบบปิดยอดใหม่');
        const at=FieldValue.serverTimestamp();
        const accountingStartAt=settings.data()?.enabledAt || at;
        if(settings.data()?.enabled!==true)tx.set(settingsRef,{enabled:true,enabledAt:at,enabledBy:request.auth.uid});
        tx.create(ref,{openedAt:at,openedBy:request.auth.uid,openingFloat,status:'open',accountingVersion:1,accountingStartAt});
        tx.set(context.ref,{sessionId:ref.id,openedAt:at,revision:FieldValue.increment(1)},{merge:true});
        return {id:ref.id};
      });
    },
    close:async request=>{
      const shop=db.collection('shops').doc(owner(request,HttpsError));
      const {sessionId,countedCash}=request.data;
      if(!validId(sessionId)||minor(countedCash)<0)fail('ข้อมูลปิดรอบไม่ถูกต้อง');
      return db.runTransaction(async tx=>{
        const context=await ledgerContext(tx,shop), ref=shop.collection('cashSessions').doc(sessionId), snap=await tx.get(ref);
        if(!snap.exists)fail('ไม่พบรอบขาย');
        const session=snap.data();
        if(session.status==='closed')return session.summary || {legacy:true};
        if(session.accountingVersion!==1){
          if(request.data.acknowledgeLegacy!==true)fail('รอบเก่าไม่มีประวัติเงินครบ ต้องยืนยันแยกปิดรอบเก่าเพื่อตรวจสอบ');
          // Archive evidence; do not invent an expected-cash figure for old untracked collections.
          tx.update(ref,{status:'closed',closedAt:FieldValue.serverTimestamp(),closedBy:request.auth.uid,
            countedCash,summary:null,needsReconciliation:true,closeReason:'legacy-ledger-missing'});
          if(context.sessionId===sessionId)tx.set(context.ref,{sessionId:null,openedAt:null,revision:FieldValue.increment(1)},{merge:true});
          return {legacy:true};
        }
        if(context.sessionId!==sessionId)fail('รอบขายเปลี่ยนแล้ว กรุณาเปิดหน้านี้ใหม่');
        const rows=await tx.get(shop.collection('moneyMovements').where('sessionId','==',sessionId).limit(10001));
        if(rows.size>10000)fail('รอบนี้มีรายการจำนวนมาก กรุณาติดต่อผู้ดูแลเพื่อปิดรอบ');
        const check=await inspectClose(tx,shop,sessionId,session,rows.docs);
        if(check.issues.length)throw new HttpsError('failed-precondition',closeError(check.issues),{issues:check.issues.slice(0,20)});
        const summary=summarizeMovements(rows.docs.map(d=>d.data()),session.openingFloat);
        summary.pendingOrderCount=check.pendingOrderCount;
        summary.openTableCount=check.openTableCount;
        tx.update(ref,{status:'closed',closedAt:FieldValue.serverTimestamp(),closedBy:request.auth.uid,countedCash,summary,
          integrityVersion:1,checkedMovementCount:check.checkedMovementCount});
        tx.set(context.ref,{sessionId:null,openedAt:null,revision:FieldValue.increment(1)},{merge:true});
        return summary;
      });
    },
    collectDebt:async request=>{
      const shop=db.collection('shops').doc(owner(request,HttpsError));
      const {debtId,requestId,amount,method,expectedPaidAmount}=request.data;
      if(!validId(debtId)||!validId(requestId)||minor(amount)<=0||!['cash','transfer','qr'].includes(method))fail('ข้อมูลรับชำระไม่ถูกต้อง');
      const ref=shop.collection('debts').doc(debtId), payment=shop.collection('debtPayments').doc(requestId);
      return db.runTransaction(async tx=>{
        const prior=await tx.get(payment), debtSnap=await tx.get(ref);
        if(prior.exists){
          const p=prior.data();
          if(p.debtId!==debtId||p.amountMinor!==minor(amount)||p.method!==method)fail('รหัสรับชำระซ้ำกับรายการอื่น');
          return {success:true};
        }
        if(!debtSnap.exists)fail('ไม่พบหนี้');
        const debt=debtSnap.data();
        const sale=validId(debt.saleId)?await tx.get(shop.collection('sales').doc(debt.saleId)):null;
        if(!sale?.exists||sale.data().isRefunded||debt.cancelledAt)fail('บิลนี้ยกเลิกแล้วหรือไม่พบบิลขาย');
        const paid=minor(debt.paidAmount||0), due=minor(debt.amount)-paid;
        if(sale.data().isDebt!==true||minor(debt.amount)!==minor(sale.data().total)||paid<0||due<0)
          fail('ยอดลูกหนี้ไม่ตรงกับบิลขาย ต้องตรวจสอบก่อนรับเงินเพิ่ม');
        if(paid!==minor(expectedPaidAmount))fail('ยอดรับชำระเปลี่ยนแล้ว กรุณาปิดหน้าต่างแล้วตรวจสอบยอดใหม่');
        if(minor(amount)>due)fail('รับชำระเกินยอดหนี้คงค้าง');
        const context=await ledgerContext(tx,shop), at=FieldValue.serverTimestamp();
        tx.update(ref,{paidAmount:(paid+minor(amount))/100,lastPaymentAt:at});
        tx.create(payment,{debtId,saleId:debt.saleId,amountMinor:minor(amount),method,createdAt:at,actor:request.auth.uid});
        writeMovement(tx,shop,context,'debt-'+requestId,{kind:'debtPayment',saleId:debt.saleId,debtId,
          amountMinor:minor(amount),salesMinor:0,debtMinor:-minor(amount),method,occurredAt:at,actor:request.auth.uid},FieldValue);
        return {success:true};
      });
    },
  };
}
module.exports={handlers};
