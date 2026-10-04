'use strict';
// A checkout can emit both completed and async_payment_succeeded, with retries.
async function apply({db,Timestamp,FieldValue,shopId,tier,billingCycle,locations,planConfig,paymentId,shopTypeOf,now=()=>new Date()}) {
  const shop=db.collection('shops').doc(shopId);
  const event=paymentId?db.collection('stripeSubscriptionEvents').doc(paymentId):null;
  return db.runTransaction(async tx=>{
    const prior=event?await tx.get(event):null, current=await tx.get(shop);
    if(prior?.exists)return prior.data().endsAt.toDate();
    const existing=current.data()?.subscriptionEndsAt?.toDate();
    const base=existing&&existing>now()?existing:now();
    const end=new Date(+base+planConfig.days*86400000);
    tx.set(shop,{subscriptionStatus:'active',subscriptionEndsAt:Timestamp.fromDate(end),tier,
      shopType:tier==='restaurant'?'restaurant':shopTypeOf(current.data()||{}),plan:billingCycle,
      locations:Math.max(1,parseInt(locations||1)),lastPaymentAt:FieldValue.serverTimestamp()},{merge:true});
    if(event)tx.create(event,{shopId,endsAt:Timestamp.fromDate(end),createdAt:FieldValue.serverTimestamp()});
    return end;
  });
}
module.exports={apply};
