const stock = require('./stock_quantity');
﻿'use strict';
const {minor,ledgerContext,writeMovement}=require('./money_ledger');
async function refundSale({db,stripe,shopId,saleId,reason,returnToStock=false,refundMethod,actor,FieldValue}) {
  if(typeof reason!=='string'||!reason.trim())throw new Error('กรุณาระบุเหตุผลคืนเงิน');
  const shop=db.collection('shops').doc(shopId), ref=shop.collection('sales').doc(saleId);
  const snapshot=await ref.get();
  if(!snapshot.exists)throw new Error('ไม่พบบิล');
  const sale=snapshot.data();
  if(sale.isRefunded)return {success:true,stripeRefundId:sale.stripeRefundId||null};
  // Live Omise checkout remains disabled until its provider refund lifecycle is
  // implemented. Never record a local refund as if external money was returned.
  if(sale.paymentProvider==='omise'||sale.omiseChargeId)throw new Error('ต้องตรวจและคืนเงินผ่าน Omise ก่อนบันทึกคืนเงินในระบบ');
  if(returnToStock&&!sale.stockDeducted)throw new Error('บิลเก่าไม่มีประวัติตัดสต็อก กรุณาตรวจสต็อกแยก');
  // Validate lot provenance before contacting a payment provider.
  if(returnToStock && sale.stripePaymentIntentId) for(const [id,q] of Object.entries(sale.stockDeducted)) {
    const p=(await shop.collection('products').doc(id).get()).data();
    if(p)stock.restore(p,q,sale.stockLotsDeducted?.[id]);
  }
  let stripeRefundId=null, stripeRefundStatus=null;
  if(sale.stripePaymentIntentId){
    const previous=await stripe.refunds.list({payment_intent:sale.stripePaymentIntentId,limit:100});
    let refund=previous.data.find(r=>r.metadata?.pokpokSaleId===saleId&&r.metadata?.pokpokShopId===shopId);
    if(!refund)refund=await stripe.refunds.create({payment_intent:sale.stripePaymentIntentId,reason:'requested_by_customer',
      metadata:{pokpokSaleId:saleId,pokpokShopId:shopId,pokpokReason:reason.trim().slice(0,500),
        pokpokReturnToStock:String(returnToStock)}}, {idempotencyKey:`pokpok-refund-${shopId}-${saleId}`});
    if(refund.metadata?.pokpokReason)reason=refund.metadata.pokpokReason;
    if(refund.metadata?.pokpokReturnToStock)returnToStock=refund.metadata.pokpokReturnToStock==='true';
    if(['failed','canceled'].includes(refund.status))throw new Error('ผู้ให้บริการคืนเงินไม่สำเร็จ กรุณาติดต่อผู้ดูแล');
    stripeRefundId=refund.id; stripeRefundStatus=refund.status;
    if(refund.status!=='succeeded'){
      await ref.update({stripeRefundId,stripeRefundStatus,refundRequestedAt:FieldValue.serverTimestamp()});
      return {success:false,pending:true};
    }
  }
  return db.runTransaction(async tx=>{
    const current=await tx.get(ref);
    if(!current.exists)throw new Error('ไม่พบบิล');
    const s=current.data(); if(s.isRefunded)return {success:true,stripeRefundId:s.stripeRefundId||null};
    const debts=s.isDebt?await tx.get(shop.collection('debts').where('saleId','==',saleId)):null;
    if(s.isDebt&&debts.docs.length!==1)throw new Error('ประวัติลูกหนี้ไม่ครบหรือซ้ำ ต้องตรวจสอบก่อนคืนเงิน');
    const paid=s.isDebt?minor(debts.docs[0].data().paidAmount||0):minor(s.total);
    if(s.isDebt&&(minor(debts.docs[0].data().amount)!==minor(s.total)||paid<0||paid>minor(s.total)))
      throw new Error('ยอดลูกหนี้ไม่ตรงกับบิลขาย ต้องตรวจสอบก่อนคืนเงิน');
    const method=s.isDebt?(refundMethod||'cash'):s.paymentMethod;
    if(!['cash','transfer','qr','online'].includes(method))throw new Error('ช่องทางคืนเงินไม่ถูกต้อง');
    const products=[], stockReturnPending=[];
    if(returnToStock){
      if(!s.stockDeducted)throw new Error('บิลเก่าไม่มีประวัติตัดสต็อก กรุณาคืนเงินโดยไม่คืนสต็อก แล้วตรวจสต็อกแยก');
      for(const [id,quantity] of Object.entries(s.stockDeducted)){
        const product=shop.collection('products').doc(id);
        const data=(await tx.get(product)).data();
        if(data) {
          try {products.push({ref:product,quantity,data,update:stock.restore(data,quantity,s.stockLotsDeducted?.[id])});}
          catch(e) {
            if(!stripeRefundId)throw e;
            stockReturnPending.push(id);
          }
        } else stockReturnPending.push(id);
      }
    }
    const customerRef=s.loyaltyCustomerId?shop.collection('customers').doc(s.loyaltyCustomerId):null;
    const customer=customerRef?await tx.get(customerRef):null;
    const orderRef=s.orderId?shop.collection('orders').doc(s.orderId):null;
    const order=orderRef?await tx.get(orderRef):null;
    const context=await ledgerContext(tx,shop), at=FieldValue.serverTimestamp();
    tx.update(ref,{isRefunded:true,refundedAt:at,refundReason:reason.trim(),returnToStock,
      refundAmount:paid/100,refundMethod:method,refundedBy:actor||shopId,stripeRefundId,stripeRefundStatus,
      ...(stockReturnPending.length?{stockReturnPending,needsReview:true,offlineReview:[...(s.offlineReview||[]),'คืนเงินแล้ว ต้องตรวจคืนสต๊อก: '+stockReturnPending.join(', ')]}:{})});
    for(const p of products)stock.write(tx,p.ref,p.data,p.update,{id:'refund-'+saleId,kind:'refund',referenceId:saleId,actor:actor||shopId,reason},FieldValue);
    if(debts)for(const d of debts.docs)tx.update(d.ref,{cancelledAt:at,cancelReason:reason.trim(),refundedAmount:paid/100});
    if(order?.exists)tx.update(orderRef,{status:'cancelled',refundedAt:at,cancelReason:reason.trim(),saleId});
    if(customer?.exists)tx.update(customerRef,{
      points:Math.max(0,Number(customer.data().points||0)-Number(s.loyaltyPointsAwarded||0)),
      totalSpent:Math.max(0,Number(customer.data().totalSpent||0)-s.total),
    });
    writeMovement(tx,shop,context,'refund-'+saleId,{kind:'refund',saleId,amountMinor:-paid,
      salesMinor:-minor(s.total),refundMinor:paid,debtMinor:s.isDebt?-(minor(s.total)-paid):0,
      method,occurredAt:at,actor:actor||shopId},FieldValue);
    return {success:true,stripeRefundId};
  });
}
module.exports={refundSale};
