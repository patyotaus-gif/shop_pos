// Supplier catalog validation regression. A local Firestore emulator is mandatory.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const req=require('node:module').createRequire(path.resolve(__dirname,'../functions/package.json'));
const {initializeApp,deleteApp}=req('firebase-admin/app');
const {getFirestore,FieldValue}=req('firebase-admin/firestore');
const {initializeTestEnvironment,assertSucceeds,assertFails}=req('@firebase/rules-unit-testing');
const {doc,setDoc,updateDoc}=req('firebase/firestore');
const {HttpsError}=req('firebase-functions/v2/https');
(async()=>{
  assert.match(process.env.FIRESTORE_EMULATOR_HOST||'',/^(127\.0\.0\.1|localhost):\d+$/);
  const projectId='demo-pokpok-admin';
  const env=await initializeTestEnvironment({projectId,firestore:{rules:fs.readFileSync(path.resolve(__dirname,'../firestore.rules'),'utf8')}});
  const app=initializeApp({projectId},'supplier-catalog-audit'),db=getFirestore(app);
  try{
    const supplier='catalog-audit-supplier',shop='catalog-audit-shop';
    await db.doc('suppliers/'+supplier).set({name:'Fixture supplier',active:true,minOrder:0});
    await db.doc('shops/'+shop).set({name:'Fixture shop'});
    const client=env.authenticatedContext(supplier).firestore();
    const ref=doc(client,`suppliers/${supplier}/products/invalid-price`);
    for(const data of [{price:-10,moq:1},{price:10,moq:0},{price:'10',moq:1},{price:Infinity,moq:1},{price:10,moq:NaN},{price:10,moq:1000001}]) {
      await assertFails(setDoc(ref,{name:'Invalid fixture',unit:'kg',available:true,...data}));
    }
    await assertSucceeds(setDoc(ref,{name:'Fractional fixture',price:12.5,moq:0.5,unit:'kg',available:true}));
    await assertFails(updateDoc(ref,{price:-1}));
    // Legacy bad data can still be repaired in one write.
    await db.doc(`suppliers/${supplier}/products/invalid-price`).set({name:'Legacy invalid',price:-10,moq:0});
    const market=require('../functions/marketplace').handlers({db,FieldValue,HttpsError});
    await assert.rejects(market.place({auth:{uid:shop,token:{}},data:{supplierId:supplier,requestId:'catalog-audit-request',items:[{productId:'invalid-price',quantity:1}],expectedTotal:0}}),e=>e.code==='failed-precondition');
    console.log('PASS: backend rejects checkout for the invalid catalog product');
    await assertSucceeds(updateDoc(ref,{price:12.5,moq:0.5}));
    await assertFails(updateDoc(doc(client,'suppliers/'+supplier),{minOrder:-100}));
    await assertSucceeds(updateDoc(doc(client,'suppliers/'+supplier),{minOrder:0}));
    console.log('PASS: invalid catalog/profile values denied; fractional values and legacy repair accepted');
  }finally{await env.cleanup();await deleteApp(app);}
})().catch(e=>{console.error(e.message);process.exitCode=1;});
