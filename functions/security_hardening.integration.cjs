// Emulator regression: all prior attack paths must fail, legitimate flows must work.
const assert=require('node:assert/strict');
const admin=require('firebase-admin');
const {initializeTestEnvironment,assertFails,assertSucceeds}=require('@firebase/rules-unit-testing');
const {doc,setDoc,updateDoc,deleteDoc,deleteField,getDoc}=require('firebase/firestore');
const {HttpsError}=require('firebase-functions/v2/https');
const fs=require('node:fs'),path=require('node:path');
(async()=>{
  assert.match(process.env.FIRESTORE_EMULATOR_HOST||'',/^(127\.0\.0\.1|localhost):\d+$/);
  const projectId='demo-pokpok-admin';
  const env=await initializeTestEnvironment({projectId,firestore:{rules:fs.readFileSync(path.join(__dirname,'../firestore.rules'),'utf8')}});
  const app=admin.initializeApp({projectId},'security-hardening'),db=app.firestore();
  const FieldValue=admin.firestore.FieldValue,Timestamp=admin.firestore.Timestamp;
  const market=require('./marketplace').handlers({db,FieldValue,HttpsError});
  const referral=require('./referral').handler({db,Timestamp,FieldValue,HttpsError});
  const owner='secure-shop',other='secure-other',supplier='secure-supplier';
  const request=(uid,data,token={})=>({auth:{uid,token},data});
  const client=env.authenticatedContext(owner).firestore();
  const vendor=env.authenticatedContext(supplier).firestore();
  const staff=env.authenticatedContext('secure-staff',{staffRole:'cashier',staffShopId:owner}).firestore();
  const expiry=Timestamp.fromMillis(Date.now()+60*86400000);
  try {
    await db.doc('shops/'+owner).set({name:'Shop',tier:'full',referralCode:'SECURESELF',trialEndsAt:expiry});
    await db.doc('shops/'+other).set({name:'Other',referralCode:'SECUREOTHER',trialEndsAt:expiry});
    await db.doc('suppliers/'+supplier).set({name:'Supplier',active:true,minOrder:100});
    const product=db.doc(`suppliers/${supplier}/products/rice`);
    await product.set({name:'Rice',unit:'kg',price:50,moq:2,available:true});
    const body={supplierId:supplier,requestId:'secure-request-001',items:[{productId:'rice',quantity:2}],expectedTotal:100};
    for(const c of [client,staff,env.unauthenticatedContext().firestore()]) {
      await assertFails(setDoc(doc(c,`suppliers/${supplier}/orders/forged`),{shopId:owner,status:'placed'}));
      await assertFails(setDoc(doc(c,`shops/${owner}/marketplaceOrders/forged`),{shopId:owner,status:'delivered',takeRate:0}));
    }
    await assertFails(setDoc(doc(client,`suppliers/${owner}/orders/forged`),{shopId:owner,status:'placed'}));
    await assert.rejects(market.supplierTransition(request(owner,{orderId:'forged',status:'cancelled'})),e=>e.code==='not-found');
    await assert.rejects(market.place({data:body}),e=>e.code==='unauthenticated');
    await assert.rejects(market.place(request(owner,{...body,shopId:other})),e=>e.code==='permission-denied');
    await assert.rejects(market.place(request('secure-staff',body,{staffRole:'cashier'})),e=>e.code==='permission-denied');
    for(const quantity of [-1,0,'2','<img src=x onerror=alert(1)>',Infinity])
      await assert.rejects(market.place(request(owner,{...body,items:[{productId:'rice',quantity}]})),e=>e.code==='invalid-argument');
    await assert.rejects(market.place(request(owner,{...body,expectedTotal:1,items:[{productId:'rice',quantity:2,price:0.5}]})),e=>e.code==='failed-precondition');
    await assert.rejects(market.place(request(owner,{...body,items:[{productId:'rice',quantity:1}],expectedTotal:50})),e=>e.code==='failed-precondition');
    const results=await Promise.all([market.place(request(owner,body)),market.place(request(owner,body))]);
    assert.equal(results[0].orderId,results[1].orderId);
    assert.equal(results.filter(r=>r.replayed).length,1);
    const id=results[0].orderId,own=db.doc(`shops/${owner}/marketplaceOrders/${id}`),copy=db.doc(`suppliers/${supplier}/orders/${id}`);
    assert.equal((await own.get()).data().items[0].price,50);
    assert.deepEqual((await own.get()).data(),(await copy.get()).data());
    await assertSucceeds(getDoc(doc(client,own.path)));
    await assertSucceeds(getDoc(doc(vendor,copy.path)));
    await assertFails(getDoc(doc(env.authenticatedContext(other).firestore(),own.path)));
    for(const c of [client,vendor]) {
      await assertFails(updateDoc(doc(c,copy.path),{shopId:other,status:'delivered',takeRate:0}));
      await assertFails(deleteDoc(doc(c,copy.path)));
    }
    await assert.rejects(market.place(request(owner,{...body,expectedTotal:150,items:[{productId:'rice',quantity:3}]})),e=>e.code==='already-exists');
    await assert.rejects(market.shopTransition(request(other,{orderId:id,status:'cancelled'})),e=>e.code==='not-found');
    await assert.rejects(market.shopTransition(request(owner,{orderId:id,status:'delivered'})),e=>e.code==='failed-precondition');
    await assert.rejects(market.supplierTransition(request(supplier,{orderId:id,status:'shipped'})),e=>e.code==='failed-precondition');
    await market.supplierTransition(request(supplier,{orderId:id,status:'accepted'}));
    assert.equal((await market.supplierTransition(request(supplier,{orderId:id,status:'accepted'}))).replayed,true);
    await market.supplierTransition(request(supplier,{orderId:id,status:'shipped'}));
    await assert.rejects(market.shopTransition(request(owner,{orderId:id,status:'cancelled'})),e=>e.code==='failed-precondition');
    await market.shopTransition(request(owner,{orderId:id,status:'delivered',takeRate:0}));
    assert.equal((await own.get()).data().takeRate,2.5);
    assert.deepEqual((await own.get()).data(),(await copy.get()).data());
    assert.equal((await market.shopTransition(request(owner,{orderId:id,status:'delivered'}))).replayed,true);
    await assert.rejects(market.supplierTransition(request(supplier,{orderId:id,status:'cancelled'})),e=>e.code==='failed-precondition');
    // Existing tampered mirror must not become an arbitrary write through Admin SDK.
    const forged={shopId:other,supplierId:supplier,status:'placed',items:[{productId:'rice',quantity:2,price:50}]};
    await db.doc(`suppliers/${supplier}/orders/legacy-forged`).set(forged);
    await assert.rejects(market.supplierTransition(request(supplier,{orderId:'legacy-forged',status:'accepted'})),e=>e.code==='failed-precondition');
    assert.equal((await db.doc(`shops/${other}/marketplaceOrders/legacy-forged`).get()).exists,false);
    const raceId=(await market.place(request(owner,{...body,requestId:'secure-request-race'}))).orderId;
    await market.supplierTransition(request(supplier,{orderId:raceId,status:'accepted'}));
    const race=await Promise.allSettled([market.supplierTransition(request(supplier,{orderId:raceId,status:'shipped'})),market.shopTransition(request(owner,{orderId:raceId,status:'cancelled'}))]);
    assert.equal(race.filter(r=>r.status==='fulfilled').length,1);
    const a=(await db.doc(`shops/${owner}/marketplaceOrders/${raceId}`).get()).data();
    const b=(await db.doc(`suppliers/${supplier}/orders/${raceId}`).get()).data();
    assert.equal(a.status,b.status);
    // Same request id in another shop cannot collide with a supplier-side record.
    const another=await market.place(request(other,body));assert.notEqual(another.orderId,id);
    const redeemed=await Promise.all([referral(request(owner,{code:'SECUREOTHER'})),referral(request(owner,{code:'SECUREOTHER'}))]);
    assert.equal(redeemed.filter(r=>r.applied).length,1);
    assert.equal((await db.doc('shops/'+owner).get()).data().trialEndsAt.toMillis()-expiry.toMillis(),30*86400000);
    await assertFails(updateDoc(doc(client,'shops/'+owner),{referredBy:deleteField()}));
    await assertFails(updateDoc(doc(client,'shops/'+owner),{referralCode:'CHANGED'}));
    await assertFails(deleteDoc(doc(client,'referralClaims/'+owner)));
    await assertFails(setDoc(doc(client,'referralClaims/'+owner),{applied:false}));
    // Server claim remains effective even if an administrative edit removes the display marker.
    await db.doc('shops/'+owner).update({referredBy:FieldValue.delete()});
    assert.equal((await referral(request(owner,{code:'SECUREOTHER'}))).applied,false);
    await assert.rejects(referral(request('secure-staff',{code:'SECUREOTHER'},{staffRole:'cashier'})),e=>e.code==='permission-denied');
    console.log('PASS security hardening: direct writes/tenant substitution/XSS input/price/fee tampering denied; legitimate marketplace lifecycle, replay, race, referral claim isolation passed');
  } finally {await env.cleanup();await app.delete();}
})().catch(e=>{console.error('FAIL security hardening: '+e.stack);process.exitCode=1;});
