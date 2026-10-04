'use strict';
const {minor,ledgerContext,writeMovement,saleMovement}=require('./money_ledger');
const validId=x=>typeof x==='string' && x.length>0 && x.length<=200 && !x.includes('/');
function owner(request,HttpsError) {
  const {shopId}=request.data||{};
  if(!request.auth || request.auth.uid!==shopId || request.auth.token?.staffRole) throw new HttpsError('permission-denied','Shop owner required');
  if(!validId(shopId)) throw new HttpsError('invalid-argument','Invalid shop');
  return shopId;
}
async function confirmOrder({db,FieldValue,shopId,orderId,actor,paymentRef,stripeSession}) {
  if(!validId(shopId)||!validId(orderId)) throw new Error('Invalid order');
  const shop=db.collection('shops').doc(shopId), orderRef=shop.collection('orders').doc(orderId);
  const saleRef=shop.collection('sales').doc('order-'+orderId);
  // Legacy Stripe records use random IDs. Do not blindly manufacture a second sale.
  const legacy=await shop.collection('sales').where('orderId','==',orderId).limit(2).get();
  return db.runTransaction(async tx=>{
    const orderSnap=await tx.get(orderRef), prior=await tx.get(saleRef);
    if(!orderSnap.exists) throw new Error('Order not found');
    const order=orderSnap.data();
    if(prior.exists) return {saleId:saleRef.id,alreadyRecorded:true};
    if(legacy.docs.length) return {saleId:legacy.docs[0].id,alreadyRecorded:true,legacy:true};
    if(order.status==='cancelled') throw new Error('Cancelled order requires payment reconciliation');
    if(order.status!=='pendingPayment') throw new Error('Historical paid order requires reconciliation');
    const amount=minor(stripeSession ? order.total : (order.finalAmount??order.total));
    if(stripeSession && (stripeSession.payment_status!=='paid' || stripeSession.currency!=='thb' || stripeSession.amount_total!==amount)) throw new Error('Payment amount or status mismatch');
    if(!stripeSession && (order.paymentMethod==='stripe' || order.stripeSessionId)) throw new Error('Await verified online payment');
    if(!Array.isArray(order.items)||!order.items.length) throw new Error('Empty order');
    const quantities=new Map();
    for(const i of order.items) {
      if(!validId(i.productId)||!Number.isInteger(i.quantity)||i.quantity<=0||minor(i.price)<0) throw new Error('Invalid order item');
      quantities.set(i.productId,(quantities.get(i.productId)||0)+i.quantity);
    }
    const updates=[]; const review=[];
    for(const [id,quantity] of quantities) {
      const ref=shop.collection('products').doc(id), product=(await tx.get(ref)).data();
      if(!product){review.push('Product removed: '+id);continue;}
      if(product.stockMode==='recipe') continue;
      if(Number(product.stock||0)<quantity) review.push('Insufficient stock: '+id);
      updates.push({ref,quantity});
    }
    const context=await ledgerContext(tx,shop);
    const now=FieldValue.serverTimestamp();
    const sale={items:order.items.map(i=>({...i,subtotal:minor(i.price*i.quantity)/100})),total:amount/100,
      discount:0,paid:amount/100,change:0,paymentMethod:stripeSession?'online':'qr',salesChannel:'takeaway',
      isDebt:false,isRefunded:false,customerName:order.customerName||'',createdAt:now,orderId,
      receiptNo:'WEB-'+orderId,accountingVersion:1,needsReview:review.length>0,offlineReview:review,
      stockDeducted:Object.fromEntries(updates.map(u=>[u.ref.id,u.quantity])),
      ...(stripeSession?{stripePaymentIntentId:stripeSession.payment_intent||null}:{})};
    tx.create(saleRef,sale);
    for(const u of updates)tx.update(u.ref,{stock:FieldValue.increment(-u.quantity)});
    tx.update(orderRef,{status:'paid',paidAt:now,saleId:saleRef.id,paymentRef:paymentRef||null,
      confirmedBy:actor,...(stripeSession?{stripeSessionId:stripeSession.id}:{autoConfirmed:false})});
    writeMovement(tx,shop,context,'sale-'+saleRef.id,{...saleMovement(sale,actor),saleId:saleRef.id,orderId},FieldValue);
    return {saleId:saleRef.id,alreadyRecorded:false};
  });
}
function handlers({db,FieldValue,HttpsError}) {
  return {
    confirm:async request=>{
      const shopId=owner(request,HttpsError);
      try {return await confirmOrder({db,FieldValue,shopId,orderId:request.data.orderId,actor:request.auth.uid,
        paymentRef:typeof request.data.paymentRef==='string'?request.data.paymentRef.slice(0,200):null});}
      catch(e){throw new HttpsError('failed-precondition',e.message);}
    },
    transition:async request=>{
      const shopId=owner(request,HttpsError), {orderId,status,reason}=request.data;
      if(!validId(orderId))throw new HttpsError('invalid-argument','Invalid order');
      const ref=db.collection('shops').doc(shopId).collection('orders').doc(orderId);
      return db.runTransaction(async tx=>{
        const doc=await tx.get(ref);if(!doc.exists)throw new HttpsError('not-found','Order not found');
        const old=doc.data(); if(old.status===status)return {success:true};
        const next={paid:'accepted',accepted:'ready',ready:'completed'};
        if(status==='cancelled'){
          if(old.status!=='pendingPayment'||old.paidAt||old.saleId)throw new HttpsError('failed-precondition','บิลชำระแล้ว กรุณาคืนเงินจากรายการขาย');
          if(old.paymentMethod==='stripe'||old.stripeSessionId)throw new HttpsError('failed-precondition','ต้องตรวจสอบสถานะชำระเงินออนไลน์ก่อนยกเลิก');
          if(typeof reason!=='string'||!reason.trim())throw new HttpsError('invalid-argument','กรุณาระบุเหตุผลยกเลิก');
        } else if(next[old.status]!==status)throw new HttpsError('failed-precondition','สถานะออเดอร์เปลี่ยนแล้ว');
        tx.update(ref,{status,statusUpdatedAt:FieldValue.serverTimestamp(),statusUpdatedBy:request.auth.uid,
          ...(status==='cancelled'?{cancelReason:reason.trim().slice(0,500)}:{})});
        return {success:true};
      });
    },
  };
}
module.exports={confirmOrder,handlers,owner,validId};
