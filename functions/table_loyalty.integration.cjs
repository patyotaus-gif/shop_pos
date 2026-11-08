// Local demo Firestore only. Loyalty points on table bills through real transactions.
const assert=require('node:assert/strict'),{randomUUID}=require('node:crypto');
const {initializeApp,deleteApp}=require('firebase-admin/app'),firestoreSdk=require('firebase-admin/firestore'),{HttpsError}=require('firebase-functions/v2/https');
(async()=>{
  assert.match(process.env.FIRESTORE_EMULATOR_HOST||'',/^(127\.0\.0\.1|localhost):\d+$/);
  const app=initializeApp({projectId:'demo-pokpok-admin'},'table-loyalty'),db=firestoreSdk.getFirestore(app),FieldValue=firestoreSdk.FieldValue;
  const shopId='table-loyalty-'+randomUUID(),shop=db.collection('shops').doc(shopId);
  const call=data=>require('./table_promotions').handlers({db,FieldValue,HttpsError})({auth:{uid:shopId,token:{}},data:{shopId,orderId:'o',...data}});
  const points=async()=>(await shop.collection('customers').doc('c1').get()).data().points;
  try {
    await shop.set({name:'isolated table loyalty test'});
    await shop.collection('settings').doc('shop').set({serviceChargePercent:0,loyaltyPointsPerBaht:10});
    await shop.collection('products').doc('tea').set({name:'Tea',price:50,costPrice:10,stock:20});
    await shop.collection('products').doc('water').set({name:'Water',price:5,costPrice:1,stock:20});
    await shop.collection('customers').doc('c1').set({name:'คุณเอ',phone:'0811111111',points:120,totalSpent:0});
    await shop.collection('tables').doc('t').set({name:'T1',status:'occupied',currentOrderId:'o'});
    const ref=shop.collection('tableOrders').doc('o');
    const tea=[{id:'a',productId:'tea',productName:'Tea',price:50,costPrice:10,quantity:2,kitchenStatus:'sent'}];
    await ref.set({tableId:'t',tableName:'T1',status:'open',openedAt:new Date(),items:tea});
    const cash=require('./cash_accounting').handlers({db,FieldValue,HttpsError});
    await cash.open({auth:{uid:shopId,token:{}},data:{shopId,acknowledgeDeviceUpdate:true,requestId:'round',openingFloat:500}});

    let {promotion:p}=await call({action:'loyalty',customerId:'c1',redeemBaht:10});
    assert.equal(p.loyalty.pointsRedeemed,100);assert.equal(p.discountMinor,1000);assert.equal(p.totalMinor,9000);
    await assert.rejects(call({action:'loyalty',customerId:'c1',redeemBaht:13}),/แต้มลูกค้าไม่พอ/);
    await assert.rejects(call({action:'loyalty',customerId:'missing',redeemBaht:1}),/ไม่พบลูกค้า/);

    // Shrinking the bill shrinks the redemption instead of failing the sync.
    await ref.update({items:[{id:'w',productId:'water',productName:'Water',price:5,costPrice:1,quantity:1,kitchenStatus:'sent'}]});
    p=(await call({action:'sync'})).promotion;
    assert.equal(p.loyalty.redeemBaht,5);assert.equal(p.totalMinor,0);
    await ref.update({items:tea});
    p=(await call({action:'sync'})).promotion;
    assert.equal(p.loyalty.redeemBaht,5);assert.equal(p.totalMinor,9500);
    p=(await call({action:'loyalty',customerId:'c1',redeemBaht:10})).promotion;
    assert.equal(p.totalMinor,9000);

    const close={action:'close',revision:p.revision,expectedTotalMinor:9000,paid:90,paymentMethod:'cash',splitCount:1};
    // Points spent elsewhere after attaching must block payment, not go negative.
    await shop.collection('customers').doc('c1').update({points:50});
    await assert.rejects(call(close),/แต้มลูกค้าไม่พอ/);
    assert.equal((await ref.get()).data().status,'open');
    await shop.collection('customers').doc('c1').update({points:120});

    const results=await Promise.all([call(close),call(close)]);
    assert.equal(results[0].saleId,results[1].saleId);
    const sale=(await shop.collection('sales').doc(results[0].saleId).get()).data();
    assert.equal(sale.total,90);assert.equal(sale.discount,10);
    assert.equal(sale.loyaltyCustomerId,'c1');assert.equal(sale.loyaltyPointsRedeemed,100);assert.equal(sale.loyaltyPointsAwarded,3);
    assert.equal(await points(),23,'120 - 100 redeemed + 3 earned, once');
    assert.equal((await shop.collection('customers').doc('c1').get()).data().totalSpent,90);

    await require('./refund').refundSale({db,FieldValue,shopId,saleId:results[0].saleId,reason:'test'});
    assert.equal(await points(),120,'refund returns redeemed points and takes back earned points');
    console.log('PASS table loyalty: attach/redeem, short balance, bill shrink clamp, close once, refund restores points');
  } finally {await db.recursiveDelete(shop);await deleteApp(app);}
})().catch(error=>{console.error(error);process.exitCode=1;});
