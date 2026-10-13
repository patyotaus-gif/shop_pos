// Demo-only Firestore: weighted checkout races, expired lots and history access.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {randomUUID}=require('node:crypto'),admin=require('firebase-admin');
const {initializeTestEnvironment,assertFails,assertSucceeds}=require('@firebase/rules-unit-testing');
const {doc,getDoc,setDoc,updateDoc,deleteDoc}=require('firebase/firestore');
(async()=>{
  assert.match(process.env.FIRESTORE_EMULATOR_HOST||'',/^(127\.0\.0\.1|localhost):\d+$/);
  const projectId='demo-pokpok-admin',app=admin.initializeApp({projectId},'inventory-tests'),db=app.firestore(),FieldValue=admin.firestore.FieldValue;
  const env=await initializeTestEnvironment({projectId,firestore:{rules:fs.readFileSync(path.join(__dirname,'../firestore.rules'),'utf8')}});
  const shopId='inventory-'+randomUUID(),shop=db.collection('shops').doc(shopId);
  try {
    await shop.set({name:'Inventory tests',tier:'full',subscriptionStatus:'trial',trialEndsAt:admin.firestore.Timestamp.fromMillis(Date.now()+86400000)});
    await shop.collection('settings').doc('shop').set({promptpayId:'0812345678'});
    await shop.collection('products').doc('rice').set({name:'Rice',price:80,stock:0.5,isWeighed:true,unit:'kg',trackLots:true,
      stockLots:[{id:'first',number:'L1',expiresOn:'2099-01-01',quantity:0.25},{id:'second',number:'L2',expiresOn:'2099-12-31',quantity:0.25}]});
    const reserve=require('./order_inventory').reserve;
    const checkout=id=>db.runTransaction(async tx=>{
      const reservation=await reserve(tx,shop,[{productId:'rice',quantity:0.375}]);
      tx.create(shop.collection('orders').doc(id),{status:'pendingPayment',total:30,finalAmount:30,
        items:[{productId:'rice',price:80,quantity:0.375,unit:'kg',isWeighed:true}],inventoryReservation:reservation.reservation});reservation.write();
    });
    const raced=await Promise.allSettled([checkout('a'),checkout('b')]);
    assert.equal(raced.filter(r=>r.status==='fulfilled').length,1,'only one 0.375 kg order can reserve 0.5 kg stock');
    const id=raced[0].status==='fulfilled'?'a':'b';
    const args={db,FieldValue,shopId,orderId:id,actor:shopId};
    await Promise.all([require('./order_accounting').confirmOrder(args),require('./order_accounting').confirmOrder(args)]);
    const p=(await shop.collection('products').doc('rice').get()).data();
    assert.equal(p.stock,0.125);assert.equal(p.stockLots[0].quantity,0);assert.equal(p.stockLots[1].quantity,0.125);
    const ref=shop.collection('products').doc('rice').collection('stockMovements');
    assert.equal((await ref.get()).size,1);assert.equal((await shop.collection('sales').get()).size,1);
    const refund={db,FieldValue,shopId,saleId:'order-'+id,reason:'test',returnToStock:true};
    await Promise.all([require('./refund').refundSale(refund),require('./refund').refundSale(refund)]);
    assert.equal((await shop.collection('products').doc('rice').get()).data().stock,0.5);
    assert.equal((await ref.get()).size,2);
    const owner=env.authenticatedContext(shopId).firestore(),other=env.authenticatedContext('other').firestore(),anon=env.unauthenticatedContext().firestore();
    const history='shops/'+shopId+'/products/rice/stockMovements/manual-test';
    await assertSucceeds(setDoc(doc(owner,history),{kind:'count',delta:0}));
    await assertSucceeds(getDoc(doc(owner,history)));
    await assertFails(updateDoc(doc(owner,history),{delta:100}));
    await assertFails(deleteDoc(doc(owner,history)));
    await assertFails(getDoc(doc(other,history)));await assertFails(setDoc(doc(anon,history),{delta:100}));
    await assertSucceeds(setDoc(doc(owner,'shops/'+shopId+'/productSkus/RICE'),{productId:'rice'}));
    await assertFails(getDoc(doc(other,'shops/'+shopId+'/productSkus/RICE')));
    console.log('PASS weighted reservation race, FEFO, idempotent sale/refund, immutable owner-only inventory history');
  } finally {await db.recursiveDelete(shop);await env.cleanup();await app.delete();}
})().catch(e=>{console.error(e);process.exitCode=1;});
