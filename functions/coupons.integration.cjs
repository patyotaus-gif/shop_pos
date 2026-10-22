// Isolated demo emulator: real transactions + rules, no live customer data.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {randomUUID,randomBytes}=require('node:crypto');
const {initializeApp, deleteApp} = require('firebase-admin/app'), firestoreSdk = require('firebase-admin/firestore');
const {initializeTestEnvironment,assertFails,assertSucceeds}=require('@firebase/rules-unit-testing');
const {doc,getDoc,setDoc,updateDoc,deleteDoc}=require('firebase/firestore');
const {HttpsError}=require('firebase-functions/v2/https');
(async()=>{
  assert.match(process.env.FIRESTORE_EMULATOR_HOST||'',/^(127\.0\.0\.1|localhost):\d+$/);
  const projectId='demo-pokpok-admin';
  const env=await initializeTestEnvironment({projectId,firestore:{rules:fs.readFileSync(path.join(__dirname,'../firestore.rules'),'utf8')}});
  const app=initializeApp({projectId},'coupon-tests'),db=firestoreSdk.getFirestore(app),FieldValue=firestoreSdk.FieldValue;
  const shopId='coupon-'+randomUUID(),shop=db.collection('shops').doc(shopId);
  try {
    await shop.set({name:'Coupon test'});
    await shop.collection('settings').doc('shop').set({promptpayId:'0812345678'});
    await shop.collection('products').doc('tea').set({name:'Tea',price:50,stock:10});
    const manage=require('./coupons').manage({db,FieldValue,HttpsError});
    const owner=data=>({auth:{uid:shopId,token:{}},data:{shopId,acknowledgeDeviceUpdate:true,...data}});
    await manage(owner({action:'create',code:'SAVE20',kind:'percent',value:20,minSubtotalMinor:10000,maxUses:1,endsAt:Date.now()+86400000}));
    const couponRef=shop.collection('coupons').doc('SAVE20');
    const source=fs.readFileSync(require.resolve('./index'),'utf8'),exports={};
    require('node:vm').runInNewContext(source.slice(source.indexOf('exports.createPromptPayOrder ='),source.indexOf('exports.stripeWebhook =')),
      {exports,onRequest:(_,fn)=>fn,firestoreSdk:{getFirestore:()=>({collection:db.collection.bind(db),runTransaction:fn=>db.runTransaction(tx=>Promise.resolve(fn(tx)))}),FieldValue},
        _verifyAppCheck:async()=>true,loadModifierGroups:async()=>({}),priceLine:require('./tableorder').priceLine,
        pickupScheduling:require('./pickup'),require,console});
    const call=async(fn,body)=>{
      const out={status:200},res={set(){},status(n){out.status=n;return this;},json(d){out.data=d;},send(){}};
      await fn({method:'POST',body},res);return out;
    };
    const checkout=body=>call(exports.createPromptPayOrder,body);
    const items=[{productId:'tea',quantity:2,price:1}]; // client price must be ignored
    const quote=await checkout({shopId,items,action:'quoteCoupon',couponCode:'save20'});
    assert.equal(quote.status,200);assert.equal(quote.data.subtotalMinor,10000);assert.equal(quote.data.discountMinor,2000);
    assert.equal((await couponRef.get()).data().claimed,0,'preview does not consume');
    const payload=()=>({shopId,items,customerName:'Test',customerPhone:'0812345678',requestId:randomUUID(),
      customerToken:randomBytes(32).toString('hex'),couponCode:'SAVE20',couponQuote:{subtotalMinor:10000,discountMinor:2000}});
    const a=payload(),b=payload();
    const results=await Promise.all([checkout(a),checkout(b)]);
    assert.equal(results.filter(r=>r.status===200).length,1,'last coupon use is atomic');
    const winner=results[0].status===200?a:b;
    assert.equal((await checkout(winner)).status,200,'retry remains available after exhaustion');
    assert.equal((await couponRef.get()).data().claimed,1);
    const customer=require('./customer_order').handler({db,FieldValue,verifyAppCheck:async()=>true});
    const action={shopId,orderId:'web-'+winner.requestId,customerToken:winner.customerToken,action:'cancel'};
    await Promise.all([call(customer,action),call(customer,action)]);
    assert.equal((await couponRef.get()).data().claimed,0,'cancel restores exactly once');
    const cash=require('./cash_accounting').handlers({db,FieldValue,HttpsError});
    await cash.open(owner({requestId:'session',openingFloat:0}));
    const next=payload(),created=await checkout(next),orderId=created.data.orderId;
    assert.equal(created.data.total,80);
    await couponRef.update({active:false});
    const accounting=require('./order_accounting'),{saleId}=await accounting.confirmOrder({db,FieldValue,shopId,orderId,actor:shopId});
    const sale=(await shop.collection('sales').doc(saleId).get()).data();
    assert.equal(sale.discount,20);assert.equal(sale.total,created.data.finalAmount);
    assert.equal(sale.items.reduce((s,i)=>s+i.subtotal,0),100);
    assert.equal(Math.round((sale.total+sale.discount-sale.paymentAdjustment)*100),10000);
    const transitions=accounting.handlers({db,FieldValue,HttpsError});
    for(const status of ['accepted','ready','completed']) await transitions.transition(owner({orderId,status}));
    const closed=await cash.close(owner({sessionId:'session',countedCash:0}));
    assert.equal(closed.grossTotal,sale.total);assert.equal(closed.byMethod.qr,sale.total);assert.equal(closed.expectedCash,0);
    await require('./refund').refundSale({db,FieldValue,shopId,saleId,reason:'test',returnToStock:true,actor:shopId});
    assert.equal((await couponRef.get()).data().claimed,1,'refund does not reset paid redemption');
    assert.equal((await shop.collection('products').doc('tea').get()).data().stock,10);
    const ownerDb=env.authenticatedContext(shopId).firestore();
    await assertSucceeds(getDoc(doc(ownerDb,couponRef.path)));
    await assertFails(updateDoc(doc(ownerDb,couponRef.path),{claimed:0}));
    await assertFails(setDoc(doc(ownerDb,`shops/${shopId}/coupons/FAKE`),{active:true}));
    for(const client of [env.unauthenticatedContext().firestore(),env.authenticatedContext('other').firestore(),env.authenticatedContext('staff',{staffRole:'cashier',staffShopId:shopId}).firestore()]) {
      await assertFails(getDoc(doc(client,couponRef.path)));
      await assertFails(updateDoc(doc(client,couponRef.path),{claimed:0}));
    }
    await shop.collection('accountingSettings').doc('current').set({enabled:false});
    const orderPath=shop.collection('orders').doc(orderId).path;
    await assertFails(updateDoc(doc(ownerDb,orderPath),{coupon:null}));
    await assertFails(deleteDoc(doc(ownerDb,orderPath)));
    await assertFails(setDoc(doc(ownerDb,`shops/${shopId}/orders/fake`),{coupon:{code:'SAVE20'}}));
    console.log('PASS coupon pricing, concurrency, replay, cancellation, sale/receipt/closing/refund and owner/staff/public rules');
  } finally {await db.recursiveDelete(shop);await env.cleanup();await deleteApp(app);}
})().catch(error=>{console.error(error);process.exitCode=1;});
