// Firestore emulator only. Gateway responses are fixtures; no external payments.
const assert=require('node:assert/strict'), fs=require('node:fs'), path=require('node:path');
const admin=require('firebase-admin');
const {initializeTestEnvironment,assertFails}=require('@firebase/rules-unit-testing');
const {doc,getDoc,setDoc}=require('firebase/firestore');
const {randomUUID}=require('node:crypto');
const {handlers}=require('./omise_sandbox');
(async()=>{
  if(!process.env.FIRESTORE_EMULATOR_HOST)throw Error('Emulator required');
  const projectId='demo-pokpok-admin', app=admin.initializeApp({projectId},'omise-sandbox-test');
  const env=await initializeTestEnvironment({projectId,firestore:{rules:fs.readFileSync(path.join(__dirname,'../firestore.rules'),'utf8')}});
  try{
    const db=app.firestore(),id=randomUUID();let charges=0;
    const shop=db.doc('shops/omise-integration-real');
    await shop.set({name:'Untouched fixture'});await shop.collection('sales').doc('old').set({total:777});
    const h=handlers({db,FieldValue:admin.firestore.FieldValue,assertFounder:r=>{assert.equal(r.auth.uid,'founder');},
      api:async(p,form)=>{
        if(p.startsWith('/tokens'))return {object:'token',id:'tokn_test_fixture',livemode:false,used:false,card:{id:'card_test_fixture'}};
        if(form)charges++;
        return {object:'charge',id:'chrg_test_fixture',livemode:false,amount:10000,currency:'THB',status:'successful',paid:true,captured:true,
          card:{id:'card_test_fixture'},metadata:{pokpokSandboxAttempt:id,actor:'founder'}};
      }});
    const req={auth:{uid:'founder',token:{founder:true}},data:{attemptId:id,method:'card',nonce:'tokn_test_fixture'}};
    await Promise.all(Array.from({length:5},()=>h.create(req)));
    assert.equal(charges,1);assert.equal((await h.status(req)).status,'successful');
    assert.deepEqual((await shop.get()).data(),{name:'Untouched fixture'});
    assert.equal((await shop.collection('sales').get()).size,1);
    assert.equal((await shop.collection('moneyMovements').get()).size,0);
    assert.equal((await shop.collection('orders').get()).size,0);
    for(const ctx of [env.unauthenticatedContext(),env.authenticatedContext('founder',{founder:true}),env.authenticatedContext('shop')]){
      const ref=doc(ctx.firestore(),`omiseSandboxAttempts/${id}`);
      await assertFails(getDoc(ref));await assertFails(setDoc(ref,{status:'successful'}));
    }
    console.log('PASS: real Firestore concurrent single-charge claim, isolated writes, all direct client access denied');
  }finally{await env.cleanup();await app.delete();}
})().catch(e=>{console.error(e);process.exitCode=1;});
