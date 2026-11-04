const assert=require('node:assert/strict'),fs=require('node:fs'),vm=require('node:vm');
const {initializeApp,deleteApp}=require('firebase-admin/app');
const {getFirestore}=require('firebase-admin/firestore');
const {HttpsError}=require('firebase-functions/v2/https');
const {initializeTestEnvironment,assertFails}=require('@firebase/rules-unit-testing');
const {doc,getDoc,setDoc}=require('firebase/firestore');
(async()=>{
  assert.match(process.env.FIRESTORE_EMULATOR_HOST||'',/^(127\.0\.0\.1|localhost):\d+$/);
  const projectId='demo-pokpok-admin',app=initializeApp({projectId},'line-handover'),db=getFirestore(app);
  const src=fs.readFileSync('index.js','utf8'),start=src.indexOf('const FOUNDER_EMAILS ='),end=src.indexOf('// Grant or revoke',start);
  const ctx={HttpsError};vm.createContext(ctx);vm.runInContext(src.slice(start,end),ctx);
  const api=require('./line_handover').handlers({db,HttpsError,assertFounder:ctx.assertFounder});
  const founder={auth:{uid:'test-founder',token:{founder:true}},data:{}};
  let env;
  try{
    const batch=db.batch();for(let i=0;i<55;i++)batch.set(db.collection('lineSupportChats').doc('U'+i.toString(16).padStart(32,'0')),{mode:'bot',epoch:1,updatedAt:1000+i,preview:'test'});await batch.commit();
    const page1=await api.list(founder);assert.equal(page1.chats.length,50);
    assert.equal(page1.chats[0].updatedAt,1054);
    const page2=await api.list({...founder,data:{after:page1.next}});assert.equal(page2.chats.length,5);
    assert.equal(new Set([...page1.chats,...page2.chats].map(x=>x.userId)).size,55);
    const userId=page1.chats[0].userId,event={source:{type:'user',userId},message:{type:'text',text:'hello'},timestamp:Date.now(),webhookEventId:'race-1'};
    const ticket=await api.receive(event);
    const outcomes=await Promise.allSettled([1,2].map(()=>api.setMode({...founder,data:{userId,mode:'human',expectedMode:'bot'}})));
    assert.equal(outcomes.filter(x=>x.status==='fulfilled').length,1);
    assert.equal(await api.replyIfCurrent(ticket,async()=>assert.fail('stale send')),false);
    env=await initializeTestEnvironment({projectId,firestore:{rules:fs.readFileSync('../firestore.rules','utf8')}});
    for(const client of [env.unauthenticatedContext(),env.authenticatedContext('shop'),env.authenticatedContext('test-founder',{founder:true})]){
      const ref=doc(client.firestore(),'lineSupportChats',userId);
      await assertFails(getDoc(ref));await assertFails(setDoc(ref,{mode:'bot'}));
    }
    await assert.rejects(api.list({auth:{uid:'shop',token:{}}}),{code:'permission-denied'});
    console.log('PASS emulator: pagination, transaction contention, stale-send suppression, direct Firestore reads/writes denied, founder callable gate.');
  }finally{if(env)await env.cleanup();await deleteApp(app);}
})().catch(e=>{console.error(e);process.exitCode=1;});
