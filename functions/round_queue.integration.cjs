// Real Firestore transactions and security rules, emulator only.
const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const sdk=require('firebase-admin/firestore');
const {HttpsError}=require('firebase-functions/v2/https');
const {createWithPickup,slots}=require('./pickup');
(async()=>{
  assert.match(process.env.FIRESTORE_EMULATOR_HOST||'',/^(127\.0\.0\.1|localhost):\d+$/);
  const app=initializeApp({projectId:'demo-pokpok-admin'},'round-queue');
  const db=sdk.getFirestore(app), shopId='queue-'+randomUUID(),shop=db.collection('shops').doc(shopId);
  const deps={db,FieldValue:sdk.FieldValue,Timestamp:sdk.Timestamp,HttpsError};
  const cash=require('./cash_accounting').handlers(deps), orders=require('./order_accounting').handlers(deps);
  const print=require('./kitchen_print').handlers(deps),work=require('./staff_work').handler(deps);
  let claims;
  const staff=require('./staff_access').createStaffAccess({...deps,auth:{createCustomToken:async(uid,token)=>{claims={uid,token};return 'test';}}});
  const owner=data=>({auth:{uid:shopId,token:{}},data:{shopId,...data}});
  try {
    await shop.set({tier:'restaurant',subscriptionStatus:'active',subscriptionEndsAt:sdk.Timestamp.fromMillis(Date.now()+86400000)});
    await shop.collection('settings').doc('shop').set({pickup:{enabled:false}});
    await shop.collection('products').doc('tea').set({name:'Tea',price:20,stock:100,stockRevision:0});
    const {id}=await staff.manage(owner({name:'Cashier',position:'cashier',pin:'123456',permissions:{}}));
    await staff.switchSession(owner({staffId:id,pin:'123456'}));
    const req=data=>({auth:claims,data:{shopId,...data}});
    await cash.open(owner({requestId:'round-a',openingFloat:0,acknowledgeDeviceUpdate:true}));
    const online=(id,extra={})=>createWithPickup({db,shopRef:shop,orderRef:shop.collection('orders').doc(id),
      order:{items:[{productId:'tea',productName:'Tea',price:20,quantity:1}],total:20,finalAmount:20,status:'pendingPayment',requestSignature:id,...extra}});
    const results=await Promise.all(['a','b','c','d'].map(id=>online(id)));
    assert.deepEqual(results.map(o=>o.queueNumber).sort(),['001','002','003','004']);
    assert.equal((await online('a')).queueNumber,results[0].queueNumber);
    const checkout=id=>staff.checkout(req({requestId:id,items:[{productId:'tea',quantity:1,optionIds:[]}],paid:20,paymentMethod:'cash',expectedTotal:20,salesChannel:'takeaway'}));
    const sales=await Promise.all(['takeaway-one','takeaway-two'].map(checkout));
    assert.deepEqual(sales.map(s=>s.queueNumber).sort(),['001','002']);
    assert.equal((await checkout('takeaway-one')).queueNumber,sales[0].queueNumber);
    for (const id of ['a','b','c','d']) {
      await orders.transition(owner({orderId:id,status:'cancelled',reason:'fixture'}));
    }
    // Actual close/open resets both counters, while replay remains tied to old round.
    await cash.close(owner({sessionId:'round-a',countedCash:40}));
    await cash.open(owner({requestId:'round-b',openingFloat:0}));
    const fresh=await online('new');assert.equal(fresh.queueNumber,'001');assert.equal(fresh.queueSessionId,'round-b');
    const take=await checkout('takeaway-three');assert.equal(take.queueNumber,'001');
    assert.equal((await checkout('takeaway-one')).queueSessionId,'round-a');
    // Payment and print retries preserve queue, stock and financial movement counts.
    await orders.confirm(owner({orderId:'new'}));
    await orders.confirm(owner({orderId:'new'}));
    const sale=(await shop.collection('sales').doc('order-new').get()).data();
    assert.equal(sale.queueNumber,'001');assert.equal(sale.queueChannel,'online');
    const p=await print.claim(owner({source:'online',orderId:'new'}));
    assert.equal(p.queueLabel,'ออนไลน์ 001');
    await print.finish(owner({jobId:p.jobId,attempt:p.attempt,received:true}));
    const again=await print.claim(owner({source:'online',orderId:'new',reprint:true}));
    assert.equal(again.queueLabel,p.queueLabel);
    assert.equal((await shop.collection('counters').doc('queue-round-b-online').get()).data().seq,1);
    const response=await work(req({action:'read',collection:'orders',id:'new'}));
    assert.equal(response.record.queueNumber,'001');
    const receipt=await work(req({action:'read',collection:'sales',id:'order-new'}));
    assert.equal(receipt.record.queueNumber,'001');
    // A future booking uses a stable reference but reserves no current queue.
    const pickup={enabled:true,capacity:10};
    await shop.collection('settings').doc('shop').set({pickup});
    const now=Date.now(),slot=slots(pickup,now).at(-1);
    assert.ok(slot);
    const future=await createWithPickup({db,shopRef:shop,orderRef:shop.collection('orders').doc('future'),
      order:{items:[{productId:'tea',productName:'Tea',price:20,quantity:1}],total:20,finalAmount:20,status:'pendingPayment',requestSignature:'future'},requestedSlot:slot.id,pickupMode:'scheduled',now:()=>now});
    assert.equal(future.queueNumber,undefined);
    await orders.confirm(owner({orderId:'future'}));
    assert.equal((await shop.collection('sales').doc('order-future').get()).data().queueNumber,undefined);
    await orders.transition(owner({orderId:'future',status:'accepted'}));
    assert.equal((await shop.collection('orders').doc('future').get()).data().queueNumber,'002');
    assert.equal((await shop.collection('sales').doc('order-future').get()).data().queueNumber,'002');
    assert.equal((await shop.collection('sales').get()).size,5);
    assert.equal((await shop.collection('moneyMovements').get()).size,5);
    await assert.rejects(orders.transition({auth:{uid:'other',token:{}},data:{shopId,orderId:'future',status:'ready'}}));
    // Existing rules allow only the owner to write client-side counters.
    const {initializeTestEnvironment,assertFails}=require('@firebase/rules-unit-testing');
    const {doc,setDoc}=require('firebase/firestore');
    const env=await initializeTestEnvironment({projectId:'demo-pokpok-admin',firestore:{host:'127.0.0.1',port:8181,rules:require('node:fs').readFileSync('../firestore.rules','utf8')}});
    try {
      await assertFails(setDoc(doc(env.authenticatedContext(claims.uid,claims.token).firestore(),`shops/${shopId}/counters/queue-round-b-takeaway`),{seq:0}));
      await assertFails(setDoc(doc(env.authenticatedContext('other').firestore(),`shops/${shopId}/counters/queue-round-b-takeaway`),{seq:0}));
    } finally {await env.cleanup();}
    console.log('PASS round queue: concurrent allocation, channel isolation, actual close/open reset, replay, scheduled acceptance, linked receipts, kitchen reprints, staff projection and denied counter writes');
  } finally {await db.recursiveDelete(shop);await deleteApp(app);}
})().catch(e=>{console.error(e);process.exitCode=1;});
