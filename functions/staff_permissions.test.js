const {test}=require('node:test');
const assert=require('node:assert/strict');
const {HttpsError}=require('firebase-functions/v2/https');
const {authorize,recheck}=require('./staff_permissions');
const {project}=require('./staff_work');
const member={active:true,sessionVersion:3,position:'kitchen',name:'Cook',permissions:{cancel:true}};
const store={tier:'restaurant',subscriptionStatus:'active',subscriptionEndsAt:{toDate:()=>new Date(Date.now()+60000)}};
const snap=data=>({exists:!!data,data:()=>data});
const ref=(data)=>({get:async()=>snap(data),collection:()=>({doc:()=>ref(member)})});
const db={collection:()=>({doc:()=>ref(store)})};
const request={auth:{uid:'staff_abc',token:{staffRole:'cashier',staffShopId:'shop',staffId:'cook',staffVersion:3}},data:{shopId:'shop'}};
test('position does not restrict common work or implicitly grant sensitive actions',async()=>{
 assert.equal((await authorize(request,db,HttpsError)).position,'kitchen');
 await authorize(request,db,HttpsError,'cancel');
 await assert.rejects(authorize(request,db,HttpsError,'refund'),e=>e.code==='permission-denied');
});
test('forged shop, role, version, disabled and expired accounts fail closed',async()=>{
 for(const token of [{staffShopId:'another'},{staffRole:'owner'},{staffVersion:2},{staffId:'a/b'}]){
  await assert.rejects(authorize({...request,auth:{...request.auth,token:{...request.auth.token,...token}}},db,HttpsError),e=>e.code==='permission-denied');
 }
 await assert.rejects(authorize({...request,data:{shopId:'another'}},db,HttpsError));
 member.active=false;await assert.rejects(authorize(request,db,HttpsError));member.active=true;
 const saved=store.subscriptionEndsAt;store.subscriptionEndsAt={toDate:()=>new Date(0)};
 await assert.rejects(authorize(request,db,HttpsError));store.subscriptionEndsAt=saved;
});
test('transaction recheck rejects revoked sessions',async()=>{
 member.sessionVersion=4;
 await assert.rejects(recheck({get:async r=>r.get()},ref(store),request,HttpsError),e=>e.code==='permission-denied');
 member.sessionVersion=3;
});
test('operational projection recursively removes costs and secrets while retaining timestamps',()=>{
 const data=project('tableOrders',{openedAt:{toDate:()=>new Date('2026-01-01Z')},pinHash:'secret',internal:'hidden',items:[{price:10,costPrice:4,modifiers:[{priceAdjust:1,costAdjust:2}]}]});
 assert.equal(data.pinHash,undefined);assert.equal(data.internal,undefined);
 assert.equal(data.items[0].costPrice,undefined);assert.equal(data.items[0].modifiers[0].costAdjust,undefined);
 assert.equal(data.items[0].modifiers[0].priceAdjust,1);assert.equal(data.openedAt,'2026-01-01T00:00:00.000Z');
});
