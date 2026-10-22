// Real transactions/rules against the isolated demo emulator only.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {randomUUID,randomBytes}=require('node:crypto'),{initializeApp, deleteApp} = require('firebase-admin/app'), firestoreSdk = require('firebase-admin/firestore');
const {initializeTestEnvironment,assertFails,assertSucceeds}=require('@firebase/rules-unit-testing');
const {doc,getDoc,setDoc,updateDoc,deleteDoc}=require('firebase/firestore');
const {HttpsError}=require('firebase-functions/v2/https');
(async()=>{
  assert.match(process.env.FIRESTORE_EMULATOR_HOST||'',/^(127\.0\.0\.1|localhost):\d+$/);
  const projectId='demo-pokpok-admin';
  const env=await initializeTestEnvironment({projectId,firestore:{rules:fs.readFileSync(path.join(__dirname,'../firestore.rules'),'utf8')}});
  const app=initializeApp({projectId},'buy-get-tests'),db=firestoreSdk.getFirestore(app),FieldValue=firestoreSdk.FieldValue;
  const shopId='gifts-'+randomUUID(),shop=db.collection('shops').doc(shopId);
  try {
    await shop.set({name:'Gift tests'});
    await shop.collection('settings').doc('shop').set({promptpayId:'0812345678'});
    await shop.collection('products').doc('tea').set({name:'Tea',price:50,stock:20,costPrice:10});
    await shop.collection('products').doc('cake').set({name:'Cake',price:20,stock:1,costPrice:5});
    const owner=data=>({auth:{uid:shopId,token:{}},data:{shopId,acknowledgeDeviceUpdate:true,...data}});
    const manage=require('./buy_get').manage({db,FieldValue,HttpsError});
    await manage(owner({action:'save',buyProductId:'tea',giftProductId:'cake',buyQuantity:2,giftQuantity:1,maxSets:2,endsAt:Date.now()+86400000}));
    const promotion=shop.collection('buyGetPromotions').doc('tea');
    const source=fs.readFileSync(require.resolve('./index'),'utf8'),exports={};
    require('node:vm').runInNewContext(source.slice(source.indexOf('exports.createPromptPayOrder ='),source.indexOf('exports.stripeWebhook =')),
      {exports,onRequest:(_,fn)=>fn,firestoreSdk:{getFirestore:()=>({collection:db.collection.bind(db),runTransaction:fn=>db.runTransaction(tx=>Promise.resolve(fn(tx)))}),FieldValue},_verifyAppCheck:async()=>true,
        loadModifierGroups:async()=>({}),priceLine:require('./tableorder').priceLine,pickupScheduling:require('./pickup'),require,console});
    const call=async(fn,body)=>{
      const result={status:200},res={set(){},status(n){result.status=n;return this;},json(data){result.data=data;},send(){}};
      await fn({method:'POST',body},res);return result;
    };
    const checkout=body=>call(exports.createPromptPayOrder,body);
    const items=[{productId:'tea',quantity:2,price:0,isGift:true}]; // injected price/flag ignored
    const q=await checkout({shopId,items,action:'quoteGifts'});
    assert.equal(q.status,200);assert.equal(q.data.buyGet[0].quantity,1);
    const payload=()=>({shopId,items,buyGetQuote:q.data.buyGet,customerName:'Test',customerPhone:'0812345678',
      customerToken:randomBytes(32).toString('hex'),requestId:randomUUID()});
    const a=payload(),b=payload(),both=await Promise.all([checkout(a),checkout(b)]);
    assert.equal(both.filter(r=>r.status===200).length,1,'only one order gets last gift stock');
    const winner=both[0].status===200?a:b;
    const replay=await checkout(winner);assert.equal(replay.status,200);assert.equal(replay.data.total,100);
    const orderRef=shop.collection('orders').doc('web-'+winner.requestId);
    const saved=(await orderRef.get()).data();
    assert.equal(saved.items.length,2);assert.equal(saved.items[0].price,50);assert.equal(saved.items[1].price,0);
    assert.equal(saved.inventoryReservation.products.cake,1);
    const customer=require('./customer_order').handler({db,FieldValue,verifyAppCheck:async()=>true});
    const action={shopId,orderId:orderRef.id,customerToken:winner.customerToken,action:'cancel'};
    const cancels=await Promise.all([call(customer,action),call(customer,action)]);
    assert.ok(cancels.every(r=>r.status===200));
    const cash=require('./cash_accounting').handlers({db,FieldValue,HttpsError});
    await cash.open(owner({requestId:'session',openingFloat:0}));
    const next=payload(),created=await checkout(next);assert.equal(created.status,200);
    const id=created.data.orderId;
    await manage(owner({action:'toggle',buyProductId:'tea',active:false}));
    const accounting=require('./order_accounting'),args={db,FieldValue,shopId,orderId:id,actor:shopId};
    const {saleId}=await accounting.confirmOrder(args);await accounting.confirmOrder(args);
    const sale=(await shop.collection('sales').doc(saleId).get()).data();
    assert.equal(sale.items[1].subtotal,0);assert.equal(sale.items[1].costPrice,5);
    assert.equal((await shop.collection('products').doc('cake').get()).data().stock,0);
    for(const status of ['accepted','ready','completed']) await accounting.handlers({db,FieldValue,HttpsError}).transition(owner({orderId:id,status}));
    const closing=await cash.close(owner({sessionId:'session',countedCash:0}));
    assert.equal(closing.grossTotal,created.data.finalAmount);assert.equal(closing.byMethod.qr,sale.total);
    await cash.open(owner({requestId:'counter-session',openingFloat:0}));
    const refund={db,FieldValue,shopId,saleId,actor:shopId,reason:'test',returnToStock:true};
    await require('./refund').refundSale(refund);await require('./refund').refundSale(refund);
    assert.equal((await shop.collection('products').doc('cake').get()).data().stock,1);
    assert.equal((await shop.collection('products').doc('tea').get()).data().stock,20);
    // The same promotion also runs through authenticated cashier checkout.
    await shop.update({tier:'full',subscriptionStatus:'trial',trialEndsAt:firestoreSdk.Timestamp.fromMillis(Date.now()+86400000)});
    await manage(owner({action:'toggle',buyProductId:'tea',active:true}));
    let claims;
    const staff=require('./staff_access').createStaffAccess({db,FieldValue,Timestamp:firestoreSdk.Timestamp,
      auth:{createCustomToken:async(uid,token)=>{claims={uid,token};return 'test-token';}}});
    const member=await staff.manage(owner({name:'Cashier',pin:'123456'}));
    await staff.switchSession(owner({staffId:member.id,pin:'123456'}));
    const counterItems=[{productId:'tea',quantity:2,optionIds:[],price:0,isGift:true}];
    const giftQuote=await staff.quoteGifts({auth:claims,data:{items:counterItems.map(({isGift,...i})=>i)}});
    const counterRequest={auth:claims,data:{requestId:'counter-'+randomUUID(),items:counterItems,paid:100,
      expectedTotal:100,paymentMethod:'cash',buyGetQuote:giftQuote.buyGet}};
    const counterResults=await Promise.all([staff.checkout(counterRequest),staff.checkout(counterRequest)]);
    assert.equal(counterResults[0].id,counterResults[1].id);
    assert.equal(counterResults[0].items[1].isGift,true);assert.equal(counterResults[0].items[1].subtotal,0);
    assert.equal(counterResults[0].items[1].costPrice,undefined,'staff cannot read gift cost');
    assert.equal((await shop.collection('products').doc('cake').get()).data().stock,0);
    await assert.rejects(()=>staff.checkout({...counterRequest,data:{...counterRequest.data,requestId:'counter-'+randomUUID()}}),/สต็อก/);
    const counterClosed=await cash.close(owner({sessionId:'counter-session',countedCash:100}));
    assert.equal(counterClosed.expectedCash,100);
    assert.equal(counterClosed.grossTotal,Math.round((100-sale.total)*100)/100);
    assert.equal(counterClosed.refundTotal,sale.total);assert.equal(counterClosed.byMethod.cash,100);
    const ownerDb=env.authenticatedContext(shopId).firestore();
    await assertSucceeds(getDoc(doc(ownerDb,promotion.path)));
    await assertFails(updateDoc(doc(ownerDb,promotion.path),{giftQuantity:99}));
    for(const client of [env.unauthenticatedContext().firestore(),env.authenticatedContext('other').firestore(),env.authenticatedContext('staff',{staffRole:'cashier',staffShopId:shopId}).firestore()]) {
      await assertFails(getDoc(doc(client,promotion.path)));
      await assertFails(setDoc(doc(client,promotion.path),{active:true}));
    }
    await shop.collection('accountingSettings').doc('current').set({enabled:false});
    await assertFails(updateDoc(doc(ownerDb,shop.collection('orders').doc(id).path),{buyGet:null}));
    await assertFails(deleteDoc(doc(ownerDb,shop.collection('orders').doc(id).path)));
    await assertFails(setDoc(doc(ownerDb,`shops/${shopId}/orders/forged`),{buyGet:q.data.buyGet}));
    console.log('PASS buy/get web and cashier concurrency, reservations, replay, cancellation, costs, payment, closing, refund and access rules');
  } finally {await db.recursiveDelete(shop);await env.cleanup();await deleteApp(app);}
})().catch(error=>{console.error(error);process.exitCode=1;});
