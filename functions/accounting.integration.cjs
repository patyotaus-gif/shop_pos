// Executes only on the emulator. Validates actual Firestore retry/locking and device rules.
const assert=require('node:assert/strict');
const admin=require('firebase-admin');
const {initializeTestEnvironment,assertFails,assertSucceeds}=require('@firebase/rules-unit-testing');
const {doc,writeBatch,setDoc,updateDoc,serverTimestamp,increment,getDoc}=require('firebase/firestore');
const {HttpsError}=require('firebase-functions/v2/https');
const {confirmOrder,handlers:orderHandlers}=require('./order_accounting');
const {handlers}=require('./cash_accounting');
const {refundSale}=require('./refund');
(async()=>{
  if(!process.env.FIRESTORE_EMULATOR_HOST)throw Error('Emulator required');
  const app=admin.initializeApp({projectId:'demo-pokpok-admin'},'accounting-integration');
  const db=app.firestore(),FieldValue=admin.firestore.FieldValue;
  const api=handlers({db,FieldValue,HttpsError});
  const subscription=require('./subscription_payment');
  const subArgs={db,FieldValue,Timestamp:admin.firestore.Timestamp,shopId:'accounting-subscription',tier:'solo',billingCycle:'monthly',locations:1,
    planConfig:{days:30},paymentId:'same-checkout-event',shopTypeOf:()=> 'retail',now:()=>new Date('2026-10-01T00:00:00Z')};
  const subscriptionResults=await Promise.all([subscription.apply(subArgs),subscription.apply(subArgs)]);
  assert.equal(+subscriptionResults[0],+subscriptionResults[1]);
  assert.equal(+subscriptionResults[0],+new Date('2026-10-31T00:00:00Z'));
  const shopId='accounting-owner',shop=db.doc('shops/'+shopId);
  const request=data=>({auth:{uid:shopId,token:{}},data:{shopId,acknowledgeDeviceUpdate:true,...data}});
  const orderApi=orderHandlers({db,FieldValue,HttpsError});
  const complete=async orderId=>{for(const status of ['accepted','ready','completed'])await orderApi.transition(request({orderId,status}));};
  await shop.set({name:'Emulator accounting'});
  await shop.collection('products').doc('tea').set({price:50,stock:20});
  const opened=await Promise.allSettled(['round1','round2'].map(requestId=>api.open(request({requestId,openingFloat:500}))));
  assert.equal(opened.filter(r=>r.status==='fulfilled').length,1);
  const sessionId=(await shop.collection('cashControl').doc('current').get()).data().sessionId;
  await shop.collection('orders').doc('o').set({status:'pendingPayment',total:100,items:[{productId:'tea',price:50,quantity:2}]});
  await Promise.all(Array.from({length:3},()=>confirmOrder({db,FieldValue,shopId,orderId:'o',actor:shopId})));
  assert.equal((await shop.collection('sales').get()).size,1);
  assert.equal((await shop.collection('products').doc('tea').get()).data().stock,18);
  await shop.collection('sales').doc('credit').set({total:100,isDebt:true,items:[],paymentMethod:'cash',stockDeducted:{}});
  await shop.collection('debts').doc('debt').set({saleId:'credit',amount:100,paidAmount:0});
  const attempts=await Promise.allSettled(['payment1','payment2'].map(requestId=>api.collectDebt(request({debtId:'debt',requestId,amount:60,method:'cash',expectedPaidAmount:0}))));
  assert.equal(attempts.filter(r=>r.status==='fulfilled').length,1);
  await assert.rejects(api.close(request({sessionId,countedCash:560})),e=>e.details.issues.some(i=>i.type==='unfinishedOrder'));
  await complete('o');
  const close=await api.close(request({sessionId,countedCash:560}));
  assert.equal(close.expectedCash,560);assert.equal(close.grossTotal,100);
  await api.open(request({requestId:'refund-round',openingFloat:500}));
  await Promise.all(Array.from({length:2},()=>refundSale({db,FieldValue,shopId,saleId:'credit',reason:'test',refundMethod:'cash'})));
  const next=await api.close(request({sessionId:'refund-round',countedCash:440}));
  assert.equal(next.expectedCash,440);
  assert.equal((await shop.collection('debts').doc('debt').get()).data().paidAmount,60);
  assert.equal((await shop.collection('cashSessions').doc(sessionId).get()).data().summary.expectedCash,560);
  // Neither the pending nor the paid-but-unfinished state may pass the close guard.
  await api.open(request({requestId:'race-round',openingFloat:0}));
  await shop.collection('orders').doc('race').set({status:'pendingPayment',total:50,items:[{productId:'tea',price:50,quantity:1}]});
  const raced=await Promise.allSettled([confirmOrder({db,FieldValue,shopId,orderId:'race',actor:shopId}),api.close(request({sessionId:'race-round',countedCash:0}))]);
  assert.equal(raced[0].status,'fulfilled');assert.equal(raced[1].status,'rejected');
  assert.equal(raced[1].reason.code,'failed-precondition');
  assert.equal((await shop.collection('cashSessions').doc('race-round').get()).data().status,'open');
  await complete('race');
  await api.close(request({sessionId:'race-round',countedCash:0}));
  const race=(await shop.collection('moneyMovements').doc('sale-order-race').get()).data();
  const raceClose=(await shop.collection('cashSessions').doc('race-round').get()).data();
  assert.equal(race.sessionId,'race-round');assert.equal(raceClose.summary.grossTotal,50);
  // A drawer write racing close must be included, or rejected as a closed round.
  await api.open(request({requestId:'drawer-round',openingFloat:500}));
  const drawer=request({requestId:'ice',sessionId:'drawer-round',kind:'cashOut',amount:44,reason:'ice'});
  await Promise.all([api.recordCashMovement(drawer),api.recordCashMovement(drawer)]);
  const extra=request({requestId:'change',sessionId:'drawer-round',kind:'cashIn',amount:20,reason:'change'});
  const drawerRace=await Promise.allSettled([
    api.recordCashMovement(extra),api.close(request({sessionId:'drawer-round',countedCash:456}))]);
  assert.equal(drawerRace[1].status,'fulfilled',String(drawerRace[1].reason));
  const added=drawerRace[0].status==='fulfilled';
  assert.equal(drawerRace[1].value.expectedCash,added?476:456);
  assert.equal(drawerRace[1].value.cashOut,44);
  assert.equal(drawerRace[1].value.grossTotal,0);
  assert.deepEqual(drawerRace[1].value.byMethod,{});
  if(!added)assert.equal(drawerRace[0].reason.code,'failed-precondition');
  await api.recordCashMovement(drawer); // Lost response retried after close.
  assert.equal((await shop.collection('moneyMovements').doc('cash-ice').get()).data().amountMinor,-4400);
  const env=await initializeTestEnvironment({projectId:'demo-pokpok-admin'});
  try {
    const legacy=env.authenticatedContext('legacy-accounting').firestore();
 const legacyPath='shops/legacy-accounting';
 await assertSucceeds(setDoc(doc(legacy,legacyPath+'/sales/old'),{total:50,paymentMethod:'cash'}));
 await assertSucceeds(updateDoc(doc(legacy,legacyPath+'/sales/old'),{isRefunded:true}));
 await assertFails(setDoc(doc(legacy,legacyPath+'/accountingSettings/current'),{enabled:false}));
 await assertFails(setDoc(doc(legacy,legacyPath+'/sales/forged'),{accountingVersion:1,total:50}));
 const client=env.authenticatedContext(shopId).firestore();
 await assertFails(setDoc(doc(client,`shops/${shopId}/moneyMovements/cash-forged`),{
   kind:'cashOut',amountMinor:-4400,salesMinor:0,debtMinor:0,method:'cash',actor:shopId,reason:'ice',sessionId:'drawer-round'}));
 await assertFails(updateDoc(doc(client,`shops/${shopId}/moneyMovements/cash-ice`),{amountMinor:-1}));
 await assertFails(setDoc(doc(client,'shops/'+shopId+'/sales/legacy-write'),{total:50}));
 await assertFails(updateDoc(doc(client,'shops/'+shopId+'/accountingSettings/current'),{enabled:false}));
    await assertFails(updateDoc(doc(client,`shops/${shopId}/sales/order-o`),{isRefunded:true}));
    await assertFails(updateDoc(doc(client,`shops/${shopId}/debts/debt`),{paidAmount:0}));
    await assertFails(updateDoc(doc(client,`shops/${shopId}/orders/o`),{status:'cancelled'}));
    await assertFails(setDoc(doc(client,`shops/${shopId}/cashSessions/forged`),{status:'open'}));
    const batch=writeBatch(client),id='device-sale';
    batch.set(doc(client,`shops/${shopId}/sales/${id}`),{accountingVersion:1,isRefunded:false,isDebt:false,total:50,paymentMethod:'cash'});
    batch.set(doc(client,`shops/${shopId}/moneyMovements/sale-${id}`),{kind:'sale',saleId:id,amountMinor:5000,salesMinor:5000,debtMinor:0,
      recordedAt:serverTimestamp(),occurredAt:serverTimestamp(),schemaVersion:1,sessionId:null,needsReconciliation:true,method:'cash'});
    batch.update(doc(client,`shops/${shopId}/cashControl/current`),{revision:increment(1)});
    await assertSucceeds(batch.commit());
    // A device cannot omit the serialization write, change totals or attach
    // money to a closed session while manufacturing a matching sale.
    for(const scenario of ['missing-lock','wrong-amount','closed-session']){
      const invalid=writeBatch(client),bad='invalid-'+scenario;
      invalid.set(doc(client,`shops/${shopId}/sales/${bad}`),{accountingVersion:1,isRefunded:false,isDebt:false,total:50,paymentMethod:'cash'});
      invalid.set(doc(client,`shops/${shopId}/moneyMovements/sale-${bad}`),{kind:'sale',saleId:bad,
        amountMinor:scenario==='wrong-amount'?1:5000,salesMinor:5000,debtMinor:0,
        recordedAt:serverTimestamp(),occurredAt:serverTimestamp(),schemaVersion:1,
        sessionId:scenario==='closed-session'?'race-round':null,needsReconciliation:scenario!=='closed-session',method:'cash'});
      if(scenario!=='missing-lock')invalid.update(doc(client,`shops/${shopId}/cashControl/current`),{revision:increment(1)});
      await assertFails(invalid.commit());
    }
    await assertFails(updateDoc(doc(client,`shops/${shopId}/moneyMovements/sale-${id}`),{amountMinor:0}));
    const staff=env.authenticatedContext('staff-accounting',{staffRole:'cashier',staffShopId:shopId}).firestore();
    await assertFails(getDoc(doc(staff,`shops/${shopId}/moneyMovements/sale-${id}`)));
  } finally {await env.cleanup();await app.delete();}
  console.log('PASS accounting transaction races, next-day debt refund, immutable snapshot and device rules');
})().catch(e=>{console.error(e);process.exitCode=1;});
