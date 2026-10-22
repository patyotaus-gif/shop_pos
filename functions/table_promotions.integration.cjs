// Local demo Firestore only. Exercises real transactions and client rules.
const assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
const {initializeApp, deleteApp} = require('firebase-admin/app'), firestoreSdk = require('firebase-admin/firestore'),{HttpsError}=require('firebase-functions/v2/https');
const {initializeTestEnvironment,assertFails,assertSucceeds}=require('@firebase/rules-unit-testing');
const {doc,updateDoc,setDoc,deleteDoc}=require('firebase/firestore');
const fs=require('node:fs'),path=require('node:path');
(async()=>{
  assert.match(process.env.FIRESTORE_EMULATOR_HOST||'',/^(127\.0\.0\.1|localhost):\d+$/);
  const projectId='demo-pokpok-admin';
  const env=await initializeTestEnvironment({projectId,firestore:{rules:fs.readFileSync(path.join(__dirname,'../firestore.rules'),'utf8')}});
  const app=initializeApp({projectId},'table-promotions'),db=firestoreSdk.getFirestore(app),FieldValue=firestoreSdk.FieldValue;
  const shopId='table-promo-'+randomUUID(),shop=db.collection('shops').doc(shopId);
  const call=data=>require('./table_promotions').handlers({db,FieldValue,HttpsError})({auth:{uid:shopId,token:{}},data:{shopId,orderId:'o',...data}});
  try {
    await shop.set({name:'isolated table promotion test'});
    await shop.collection('settings').doc('shop').set({serviceChargePercent:10});
    await shop.collection('products').doc('tea').set({name:'Tea',price:50,costPrice:10,stock:20});
    await shop.collection('products').doc('cake').set({name:'Cake',price:25,costPrice:5,stock:20});
    await shop.collection('buyGetPromotions').doc('tea').set({active:true,revision:'g',endsAt:new Date(Date.now()+86400000),
      buyQuantity:2,giftQuantity:1,maxSets:5,giftProductId:'cake'});
    await shop.collection('promotionSettings').doc('bundles').set({bundles:[{id:'set',name:'Tea Cake',revision:'b',active:true,
      endsAt:new Date(Date.now()+86400000),maxSets:5,priceMinor:10000,components:[{productId:'tea',quantity:2},{productId:'cake',quantity:1}]}]});
    await shop.collection('coupons').doc('SAVE10').set({code:'SAVE10',active:true,endsAt:new Date(Date.now()+86400000),
      kind:'percent',value:10,minSubtotalMinor:2000,maxUses:1,claimed:0});
    await shop.collection('tables').doc('t').set({name:'T1',status:'occupied',currentOrderId:'o'});
    const ref=shop.collection('tableOrders').doc('o');
    await ref.set({tableId:'t',tableName:'T1',status:'open',openedAt:new Date(),items:[
      {id:'a',productId:'tea',productName:'Tea',price:50,costPrice:10,quantity:2,kitchenStatus:'sent'},
      {id:'b',productId:'cake',productName:'Cake',price:25,costPrice:5,quantity:1,kitchenStatus:'pending'}]});
    const cash=require('./cash_accounting').handlers({db,FieldValue,HttpsError});
    const owner=data=>({auth:{uid:shopId,token:{}},data:{shopId,acknowledgeDeviceUpdate:true,...data}});
    await cash.open(owner({requestId:'round',openingFloat:500}));
    const {promotion:p}=await call({action:'preview',couponCode:'SAVE10'});
    await Promise.all([call({action:'apply',couponCode:'SAVE10',revision:p.revision}),call({action:'apply',couponCode:'SAVE10',revision:p.revision})]);
    assert.equal((await ref.get()).data().items.filter(i=>i.isGift).length,1);
    assert.equal((await shop.collection('coupons').doc('SAVE10').get()).data().claimed,0);
    assert.equal((await call({action:'sync'})).promotion.totalMinor,9900);
    const client=env.authenticatedContext(shopId).firestore(),clientRef=doc(client,ref.path);
    await assertFails(updateDoc(clientRef,{tablePromotion:{...p,totalMinor:1}}));
    await assertFails(updateDoc(clientRef,{status:'closed',saleId:'forged'}));
    await assertFails(deleteDoc(clientRef));
    await assertFails(setDoc(doc(client,shop.collection('tableOrders').doc('forged').path),{status:'open',tablePromotion:p}));
    await assertFails(updateDoc(doc(env.authenticatedContext('other').firestore(),ref.path),{items:[]}));
    const items=(await ref.get()).data().items;
    await updateDoc(clientRef,{items:items.map(i=>({...i,isGift:false}))});
    await assert.rejects(()=>call({action:'preview',couponCode:'SAVE10'}),/ข้อมูลของแถมถูกเปลี่ยน/);
    await assertSucceeds(updateDoc(clientRef,{items}));
    await Promise.all([call({action:'send'}),call({action:'send'})]);
    assert.ok((await ref.get()).data().items.every(i=>i.kitchenStatus==='sent'));
    assert.equal((await ref.get()).data().items.filter(i=>i.isGift).length,1);
    const close={action:'close',revision:p.revision,expectedTotalMinor:p.totalMinor,paid:100,paymentMethod:'cash',splitCount:1};
    const [a,b]=await Promise.all([call(close),call(close)]);assert.equal(a.saleId,b.saleId);
    const sale=(await shop.collection('sales').doc(a.saleId).get()).data();
    assert.equal(sale.total,99);assert.equal(sale.discount,35);assert.equal(sale.serviceCharge,9);assert.equal(sale.change,1);
    assert.equal(sale.items.at(-1).isGift,true);assert.equal(sale.items.at(-1).costPrice,5);
    assert.equal((await shop.collection('products').doc('cake').get()).data().stock,18);
    assert.equal((await shop.collection('coupons').doc('SAVE10').get()).data().claimed,1);
    const closed=await cash.close(owner({sessionId:'round',countedCash:599,autoOpenNext:true}));
    assert.equal(closed.grossTotal,99);assert.equal(closed.expectedCash,599);
    const refund={db,FieldValue,shopId,saleId:a.saleId,reason:'test',returnToStock:true};
    await require('./refund').refundSale(refund);await require('./refund').refundSale(refund);
    assert.equal((await shop.collection('products').doc('cake').get()).data().stock,20);
    assert.equal((await shop.collection('coupons').doc('SAVE10').get()).data().claimed,1);
    assert.equal((await shop.collection('cashSessions').doc('round').get()).data().summary.expectedCash,599);
    // Cancelling an unpaid promoted table leaves coupon counters untouched.
    await shop.collection('tables').doc('cancel-table').set({status:'occupied',currentOrderId:'cancel'});
    await shop.collection('tableOrders').doc('cancel').set({...(await ref.get()).data(),tableId:'cancel-table',status:'open',saleId:null});
    await assertSucceeds(updateDoc(doc(client,shop.collection('tableOrders').doc('cancel').path),{status:'cancelled'}));
    // New UX: one-step pricing/send, then owner keeps an already prepared gift.
    const ux=shop.collection('tableOrders').doc('ux');
    await shop.collection('tables').doc('ux').set({status:'occupied',currentOrderId:'ux'});
    await ux.set({tableId:'ux',tableName:'UX',status:'open',openedAt:new Date(),items:items.filter(i=>!i.isGift)});
    const {promotion:u}=await call({action:'send',orderId:'ux'});
    const changed=(await ux.get()).data().items.map(i=>i.id==='a'?{...i,quantity:1}:i);
    await ux.update({items:changed});
    await assert.rejects(()=>call({action:'sync',orderId:'ux'}),/ของแถมส่งครัวแล้ว/);
    const {promotion:v}=await call({action:'sync',orderId:'ux',keepPreparedGifts:true,revision:u.revision,reason:'ร้านให้ของแถมเดิม'});
    assert.equal(v.totalMinor,8250);
    const result=await call({action:'close',orderId:'ux',revision:v.revision,expectedTotalMinor:v.totalMinor,paid:100,paymentMethod:'cash',splitCount:1});
    const retained=(await shop.collection('sales').doc(result.saleId).get()).data();
    assert.equal(retained.retainedGifts[0].reason,'ร้านให้ของแถมเดิม');
    assert.equal(retained.stockDeducted.cake,2);
    console.log('PASS table promotions: sync/send races, retained gift audit, rules, net cash close and next-round refund');
  } finally {await db.recursiveDelete(shop);await env.cleanup();await deleteApp(app);}
})().catch(e=>{console.error(e);process.exitCode=1;});
