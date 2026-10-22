// Isolated demo emulator: never connect to live shop data.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {randomUUID,randomBytes}=require('node:crypto'),{initializeApp, deleteApp} = require('firebase-admin/app'), firestoreSdk = require('firebase-admin/firestore');
const {initializeTestEnvironment,assertFails,assertSucceeds}=require('@firebase/rules-unit-testing');
const {doc,getDoc,setDoc,updateDoc,deleteDoc}=require('firebase/firestore');
const {HttpsError}=require('firebase-functions/v2/https');
(async()=>{
  assert.match(process.env.FIRESTORE_EMULATOR_HOST||'',/^(127\.0\.0\.1|localhost):\d+$/);
  const projectId='demo-pokpok-admin';
  const env=await initializeTestEnvironment({projectId,firestore:{rules:fs.readFileSync(path.join(__dirname,'../firestore.rules'),'utf8')}});
  const app=initializeApp({projectId},'bundle-tests'),db=firestoreSdk.getFirestore(app),FieldValue=firestoreSdk.FieldValue;
  const shopId='bundles-'+randomUUID(),shop=db.collection('shops').doc(shopId);
  try {
    await shop.set({name:'Bundle tests',tier:'full',subscriptionStatus:'trial',trialEndsAt:firestoreSdk.Timestamp.fromMillis(Date.now()+86400000)});
    await shop.collection('settings').doc('shop').set({promptpayId:'0812345678'});
    await shop.collection('products').doc('tea').set({name:'Tea',price:50,stock:20,costPrice:10});
    await shop.collection('products').doc('cake').set({name:'Cake',price:25,stock:2,costPrice:5});
    const owner=data=>({auth:{uid:shopId,token:{}},data:{shopId,acknowledgeDeviceUpdate:true,...data}});
    const manage=require('./bundles').manage({db,FieldValue,HttpsError}),endsAt=Date.now()+86400000;
    const cfg={action:'save',id:'tea-cake',name:'Tea and Cake',components:[{productId:'tea',quantity:2},{productId:'cake',quantity:1}],priceMinor:10000,maxSets:2,endsAt};
    await manage(owner(cfg));
    const overlap=await Promise.allSettled([manage(owner({...cfg,id:'overlap'})),manage(owner({...cfg,id:'overlap2'}))]);
    assert.ok(overlap.every(x=>x.status==='rejected'),'overlapping sets cannot race through');
    await require('./buy_get').manage({db,FieldValue,HttpsError})(owner({action:'save',buyProductId:'tea',giftProductId:'cake',buyQuantity:2,giftQuantity:1,maxSets:1,endsAt}));
    await require('./coupons').manage({db,FieldValue,HttpsError})(owner({action:'create',code:'SAVE10',kind:'percent',value:10,minSubtotalMinor:2000,maxUses:5,endsAt}));
    const source=fs.readFileSync(require.resolve('./index'),'utf8'),exports={};
    require('node:vm').runInNewContext(source.slice(source.indexOf('exports.createPromptPayOrder ='),source.indexOf('exports.stripeWebhook ='))
      .replace('const known = error.couponError',"if (!error.couponError && !error.buyGetError && !error.bundleError) console.error(error); const known = error.couponError"),
      {exports,onRequest:(_,fn)=>fn,firestoreSdk:{getFirestore:()=>({collection:db.collection.bind(db),runTransaction:fn=>db.runTransaction(tx=>Promise.resolve(fn(tx)))}),FieldValue},_verifyAppCheck:async()=>true,
        loadModifierGroups:async()=>({}),priceLine:require('./tableorder').priceLine,pickupScheduling:require('./pickup'),require,console});
    const call=async(fn,body)=>{
      const result={status:200},res={set(){},status(n){result.status=n;return this;},json(data){result.data=data;},send(){}};
      await fn({method:'POST',body},res);return result;
    };
    const checkout=body=>call(exports.createPromptPayOrder,body);
    const items=[{productId:'tea',quantity:2,price:0},{productId:'cake',quantity:1,price:0}];
    const q=await checkout({shopId,items,action:'quoteGifts'});
    assert.equal(q.status,200);assert.equal(q.data.bundles[0].discountMinor,2500);assert.equal(q.data.buyGet[0].quantity,1);
    const coupon=await checkout({shopId,items,action:'quoteCoupon',couponCode:'SAVE10'});
    assert.equal(coupon.data.subtotalMinor,10000);assert.equal(coupon.data.discountMinor,1000);
    const payload=()=>({shopId,items,buyGetQuote:q.data.buyGet,bundleQuote:q.data.bundles,
      couponCode:'SAVE10',couponQuote:{subtotalMinor:10000,discountMinor:1000},customerName:'Test',customerPhone:'0812345678',
      customerToken:randomBytes(32).toString('hex'),requestId:randomUUID()});
    const a=payload(),b=payload(),both=await Promise.all([checkout(a),checkout(b)]);
    assert.equal(both.filter(r=>r.status===200).length,1,'reservation includes bundle items plus gifts');
    assert.equal(both.find(r=>r.status!==200).status,409,'losing checkout reports a stock/promotion conflict, not a transaction failure');
    const winner=both[0].status===200?a:b;
    const replay=await checkout(winner);assert.equal(replay.status,200);assert.equal(replay.data.total,90);
    const originalId=replay.data.orderId;
    const customer=require('./customer_order').handler({db,FieldValue,verifyAppCheck:async()=>true});
    const cancel={shopId,orderId:originalId,customerToken:winner.customerToken,action:'cancel'};
    await call(customer,cancel);await call(customer,cancel);
    assert.equal((await shop.collection('coupons').doc('SAVE10').get()).data().claimed,0);
    const cash=require('./cash_accounting').handlers({db,FieldValue,HttpsError});
    await cash.open(owner({requestId:'session',openingFloat:0}));
    const created=await checkout(payload());assert.equal(created.status,200);assert.equal(created.data.total,90);
    const id=created.data.orderId;
    await manage(owner({action:'delete',id:'tea-cake'}));
    const accounting=require('./order_accounting'),args={db,FieldValue,shopId,orderId:id,actor:shopId};
    const {saleId}=await accounting.confirmOrder(args);await accounting.confirmOrder(args);
    const sale=(await shop.collection('sales').doc(saleId).get()).data();
    assert.equal(sale.discount,35);assert.equal(sale.bundleDiscount,25);assert.equal(sale.items.length,3);
    assert.equal((await shop.collection('products').doc('cake').get()).data().stock,0);
    for(const status of ['accepted','ready','completed'])await accounting.handlers({db,FieldValue,HttpsError}).transition(owner({orderId:id,status}));
    const closed=await cash.close(owner({sessionId:'session',countedCash:0}));
    assert.equal(closed.grossTotal,created.data.finalAmount);assert.equal(closed.byMethod.qr,sale.total);
    await cash.open(owner({requestId:'counter-session',openingFloat:0}));
    const refund={db,FieldValue,shopId,saleId,actor:shopId,reason:'test',returnToStock:true};
    await require('./refund').refundSale(refund);await require('./refund').refundSale(refund);
    assert.equal((await shop.collection('products').doc('cake').get()).data().stock,2);
    await manage(owner(cfg));
    let claims;
    const staff=require('./staff_access').createStaffAccess({db,FieldValue,Timestamp:firestoreSdk.Timestamp,
      auth:{createCustomToken:async(uid,token)=>{claims={uid,token};return 'test-token';}}});
    const member=await staff.manage(owner({name:'Cashier',pin:'123456'}));await staff.switchSession(owner({staffId:member.id,pin:'123456'}));
    const catalog=await staff.bundleCatalog({auth:claims});assert.equal(catalog.bundles[0].priceMinor,10000);
    const counterItems=items.map(i=>({...i,optionIds:[]}));
    const preview=await staff.quoteGifts({auth:claims,data:{items:counterItems}});
    const request={auth:claims,data:{requestId:'counter-'+randomUUID(),items:counterItems,paid:100,expectedTotal:100,
      paymentMethod:'cash',buyGetQuote:preview.buyGet,bundleQuote:preview.bundles}};
    await assert.rejects(()=>staff.checkout({...request,data:{...request.data,bundleQuote:[]}}),/ชุดสินค้า/);
    const results=await Promise.all([staff.checkout(request),staff.checkout(request)]);
    assert.equal(results[0].id,results[1].id);assert.equal(results[0].total,100);assert.equal(results[0].discount,25);
    assert.equal(results[0].items[2].costPrice,undefined);
    assert.equal((await shop.collection('products').doc('cake').get()).data().stock,0);
    const counterClosed=await cash.close(owner({sessionId:'counter-session',countedCash:100}));
    assert.equal(counterClosed.expectedCash,100);assert.equal(counterClosed.refundTotal,sale.total);
    assert.equal(counterClosed.grossTotal,Math.round((100-sale.total)*100)/100);
    const conf=shop.collection('promotionSettings').doc('bundles'),ownerDb=env.authenticatedContext(shopId).firestore();
    await assertSucceeds(getDoc(doc(ownerDb,conf.path)));await assertFails(updateDoc(doc(ownerDb,conf.path),{bundles:[]}));
    for(const client of [env.unauthenticatedContext().firestore(),env.authenticatedContext('other').firestore(),env.authenticatedContext('staff',{staffRole:'cashier',staffShopId:shopId}).firestore()]) {
      await assertFails(getDoc(doc(client,conf.path)));await assertFails(setDoc(doc(client,conf.path),{bundles:[]}));
    }
    await shop.collection('accountingSettings').doc('current').set({enabled:false});
    await assertFails(updateDoc(doc(ownerDb,shop.collection('orders').doc(id).path),{bundles:null}));
    await assertFails(deleteDoc(doc(ownerDb,shop.collection('orders').doc(id).path)));
    await assertFails(setDoc(doc(ownerDb,`shops/${shopId}/orders/forged`),{bundles:q.data.bundles}));
    console.log('PASS bundles: web/counter, simultaneous reservations, coupon+gift, replay, net ledger/close, refund and access rules');
  } finally {await db.recursiveDelete(shop);await env.cleanup();await deleteApp(app);}
})().catch(error=>{console.error(error);process.exitCode=1;});
