const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const sdk=require('firebase-admin/firestore');
const {HttpsError}=require('firebase-functions/v2/https');
(async()=>{
 assert.match(process.env.FIRESTORE_EMULATOR_HOST||'',/^(127\.0\.0\.1|localhost):\d+$/);
 const app=initializeApp({projectId:'demo-pokpok-admin'},'chef-regression');
 const db=sdk.getFirestore(app),FieldValue=sdk.FieldValue,Timestamp=sdk.Timestamp;
 const shopId='chef-'+randomUUID(),shop=db.collection('shops').doc(shopId);
 const deps={db,FieldValue,HttpsError};
 const work=require('./staff_work').handler(deps),table=require('./table_promotions').handlers(deps);
 let claims;
 const staff=require('./staff_access').createStaffAccess({...deps,Timestamp,auth:{createCustomToken:async(uid,token)=>{claims={uid,token};return 'test';}}});
 const owner=data=>({auth:{uid:shopId,token:{name:'Owner'}},data:{shopId,...data}});
 try{
  await shop.set({tier:'restaurant',subscriptionStatus:'active',subscriptionEndsAt:Timestamp.fromMillis(Date.now()+86400000)});
  await shop.collection('settings').doc('shop').set({name:'Chef test',serviceChargePercent:0});
  await shop.collection('products').doc('food').set({name:'Food',price:50,costPrice:20,stock:100,stockRevision:0});
  const {id}=await staff.manage(owner({name:'Chef',position:'kitchen',pin:'123456',permissions:{}}));
  await staff.switchSession(owner({staffId:id,pin:'123456'}));
  const req=data=>({auth:claims,data:{shopId,...data}});
  await shop.collection('tables').doc('a1').set({name:'A1',status:'available'});
  const {orderId}=await work(req({action:'open',tableId:'a1'}));
  await work(req({action:'add',orderId,requestId:'food',items:[{productId:'food',quantity:2,optionIds:[]}]}));
  const sync=await table(owner({action:'send',orderId}));
  const original=(await shop.collection('tableOrders').doc(orderId).get()).data();
  const itemId=original.items[0].id;
  const {saleId}=await table(owner({action:'close',orderId,revision:sync.promotion.revision,expectedTotalMinor:10000,paid:100,paymentMethod:'cash',splitCount:1}));
  // A new customer can use the same table while the old food is being prepared.
  const reopened=await work(req({action:'open',tableId:'a1'}));
  const tableBefore=(await shop.collection('tables').doc('a1').get()).data();
  const saleBefore=(await shop.collection('sales').doc(saleId).get()).data();
  const stockBefore=(await shop.collection('products').doc('food').get()).data();
  assert.notEqual(reopened.orderId,orderId);
  // Historical bills exceed a single page. The old uncompleted item must survive.
  for(let chunk=0;chunk<2;chunk++){
   const batch=db.batch();
   for(let i=0;i<250;i++)batch.set(shop.collection('tableOrders').doc(`history-${chunk}-${i}`),{
    status:'closed',tableName:'old',openedAt:Timestamp.now(),items:[{id:'x',kitchenStatus:'ready',costPrice:99}],
   });
   await batch.commit();
  }
  const initial=await work(req({action:'read',collection:'kitchenOrders'}));
  const queue=initial.records;
  assert.equal(queue.length,1);assert.equal(queue[0].id,orderId);
  assert.equal(queue[0].items[0].costPrice,undefined);
  const incremental={action:'read',collection:'kitchenOrders',kitchenSince:initial.kitchenSince,kitchenPendingIds:[orderId]};
  assert.equal((await work(req(incremental))).records[0].id,orderId);
  await assert.rejects(work(req({...incremental,kitchenPendingIds:['../other']})));
  await assert.rejects(work(req({...incremental,kitchenSince:'invalid'})));
  await assert.rejects(work(req({action:'quantity',orderId,itemId,quantity:3,expectedQuantity:2})));
  const ready=req({action:'ready',orderId,itemId});
  await Promise.all([work(ready),work(ready)]);
  const after=(await shop.collection('tableOrders').doc(orderId).get()).data();
  assert.equal(after.status,'closed');assert.equal(after.saleId,saleId);
  assert.equal(after.items[0].kitchenStatus,'ready');assert.equal(after.items[0].readyByName,'Chef');
  await work(owner({action:'ready',orderId,itemId}));
  assert.deepEqual((await shop.collection('tableOrders').doc(orderId).get()).data(),after);
  assert.deepEqual((await shop.collection('tables').doc('a1').get()).data(),tableBefore);
  assert.deepEqual((await shop.collection('sales').doc(saleId).get()).data(),saleBefore);
  assert.deepEqual((await shop.collection('products').doc('food').get()).data(),stockBefore);
  assert.equal((await work(req({action:'read',collection:'kitchenOrders'}))).records.length,0);
  assert.equal((await work(req(incremental))).records.length,0);
  for(const [key,status,kitchenStatus] of [['cancelled','cancelled','sent'],['pending','closed','pending']]){
   await shop.collection('tableOrders').doc(key).set({status,tableId:'a1',items:[{id:'x',kitchenStatus}]});
   await assert.rejects(work(req({action:'ready',orderId:key,itemId:'x'})));
  }
  await assert.rejects(work(req({action:'ready',orderId,itemId:'missing'})));
  await shop.collection('tableOrders').doc('gift').set({status:'closed',tableId:'a1',items:[{
   id:'gift',productId:'food',quantity:1,kitchenStatus:'sent',isGift:true,promotionId:'promo',price:0,notes:'allergy',modifiers:[{optionName:'extra'}],
  }]});
  await work(req({action:'ready',orderId:'gift',itemId:'gift'}));
  const gift=(await shop.collection('tableOrders').doc('gift').get()).data().items[0];
  assert.equal(gift.isGift,true);assert.equal(gift.promotionId,'promo');assert.equal(gift.price,0);
  assert.equal(gift.notes,'allergy');assert.equal(gift.modifiers[0].optionName,'extra');
  await assert.rejects(work({data:{shopId,action:'read',collection:'kitchenOrders'}}));
  await assert.rejects(work({auth:claims,data:{shopId:'other',action:'read',collection:'kitchenOrders'}}));
  await staff.manage(owner({id,name:'Chef',position:'kitchen',active:false,permissions:{}}));
  await assert.rejects(work(ready));
  await assert.rejects(work(req({action:'read',collection:'kitchenOrders'})));
  console.log('PASS chef: paid unfinished queue, history pagination, reused table, idempotent ready, unchanged billing/stock, audit, cancellation and authorization');
 }finally{await db.recursiveDelete(shop);await deleteApp(app);}
})().catch(e=>{console.error(e);process.exitCode=1;});
