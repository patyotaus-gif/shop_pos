'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {HttpsError}=require('firebase-functions/v2/https');
const {fixture}=require('./accounting_fixture.cjs');
const {handlers}=require('./cash_accounting');
const req=data=>({auth:{uid:'shop',token:{}},data:{shopId:'shop',acknowledgeDeviceUpdate:true,...data}});
const path='shops/shop/';
async function setup(){
  const f=fixture(),api=handlers({...f,HttpsError});
  await api.open(req({requestId:'first',openingFloat:500}));
  return {...f,api};
}

test('manual close stays closed; next opening remembers float not closing cash',async()=>{
  const f=await setup();
  await f.api.recordCashMovement(req({requestId:'in',sessionId:'first',kind:'cashIn',amount:4500,reason:'cash'}));
  await f.api.close(req({sessionId:'first',countedCash:5000,autoOpenNext:false}));
  const old=structuredClone(f.docs.get(path+'cashSessions/first'));
  assert.equal(old.status,'closed');
  assert.equal(old.nextSessionId,undefined);
  assert.equal(f.docs.get(path+'accountingSettings/current').defaultOpeningFloat,500);
  assert.equal([...f.docs].filter(([p,d])=>p.startsWith(path+'cashSessions/')&&d.status==='open').length,0);
  await f.api.open(req({requestId:'next',openingFloat:1000}));
  assert.equal(f.docs.get(path+'cashSessions/next').openingFloat,1000);
  assert.equal(f.docs.get(path+'accountingSettings/current').defaultOpeningFloat,1000);
  await f.api.close(req({sessionId:'first',countedCash:999,autoOpenNext:false}));
  assert.deepEqual(f.docs.get(path+'cashSessions/first'),old);
  const summary=await f.api.close(req({sessionId:'next',countedCash:1000,autoOpenNext:false}));
  assert.equal(summary.grossTotal,0);
  assert.equal(summary.expectedCash,1000);
});

test('opening rejects invalid float before changing saved default',async()=>{
  const f=await setup();
  for(const openingFloat of [-0.001,0.001,NaN,Infinity,'1000',1e9+1]) {
    await assert.rejects(f.api.open(req({requestId:'invalid',openingFloat})),{code:'invalid-argument'});
  }
  assert.equal(f.docs.get(path+'accountingSettings/current').defaultOpeningFloat,500);
});
test('automatic successor carries counted cash, preserves shortage and starts revenue at zero',async()=>{
  const f=await setup();
  await f.api.recordCashMovement(req({requestId:'in',sessionId:'first',kind:'cashIn',amount:20,reason:'float'}));
  const summary=await f.api.close(req({sessionId:'first',countedCash:515.25,autoOpenNext:true}));
  assert.equal(summary.expectedCash,520);
  const old=f.docs.get(path+'cashSessions/first');
  assert.equal(old.countedCash,515.25);assert.equal(old.carriedCash,515.25);
  const second=f.docs.get(path+'cashSessions/'+old.nextSessionId);
  assert.equal(second.status,'open');assert.equal(second.openingFloat,515.25);
  assert.equal(second.previousSessionId,'first');
  assert.equal(second.accountingStartAt,f.docs.get(path+'accountingSettings/current').enabledAt);
  assert.equal(f.docs.get(path+'cashControl/current').sessionId,old.nextSessionId);
  const nextSummary=await f.api.close(req({sessionId:old.nextSessionId,countedCash:515.25,autoOpenNext:true}));
  assert.equal(nextSummary.expectedCash,515.25);
  assert.equal(nextSummary.grossTotal,0);assert.equal(nextSummary.billCount,0);assert.equal(nextSummary.cashIn,0);
});
test('concurrent closes and very late retries never create two successors or overwrite counts',async()=>{
  const f=await setup();
  await Promise.all([500,999].map(countedCash=>f.api.close(req({sessionId:'first',countedCash,autoOpenNext:true}))));
  const first=f.docs.get(path+'cashSessions/first');
  assert.equal(first.countedCash,500);
  await assert.rejects(f.api.open(req({requestId:'manual',openingFloat:0})),/เปิดอยู่/);
  await f.api.close(req({sessionId:first.nextSessionId,countedCash:400,autoOpenNext:true}));
  const before=structuredClone([...f.docs]);
  await f.api.close(req({sessionId:'first',countedCash:10,autoOpenNext:true}));
  assert.deepEqual([...f.docs],before);
  assert.equal([...f.docs].filter(([p,d])=>p.startsWith(path+'cashSessions/')&&d.status==='open').length,1);
});
test('blocked close leaves original round open and creates no successor',async()=>{
  for(const issue of ['table','unassigned']){
    const f=await setup();
    if(issue==='table')f.docs.set(path+'tableOrders/t',{status:'open',tableName:'1',items:[]});
    else f.docs.set(path+'moneyMovements/late',{sessionId:null,needsReconciliation:true,recordedAt:1000});
    const before=structuredClone([...f.docs]);
    await assert.rejects(f.api.close(req({sessionId:'first',countedCash:500,autoOpenNext:true})),{code:'failed-precondition'});
    assert.deepEqual([...f.docs],before);
  }
});
test('zero cash carries zero; invalid precision cannot enter the next drawer',async()=>{
  const f=await setup();
  await assert.rejects(f.api.close(req({sessionId:'first',countedCash:0.001,autoOpenNext:true})),/2 ตำแหน่ง/);
  await f.api.close(req({sessionId:'first',countedCash:0,autoOpenNext:true}));
  const id=f.docs.get(path+'cashControl/current').sessionId;
  assert.equal(f.docs.get(path+'cashSessions/'+id).openingFloat,0);
});
test('legacy archive cannot silently enable accounting through automatic reopening',async()=>{
  const f=fixture({[path+'cashSessions/old']:{status:'open',openingFloat:0}}),api=handlers({...f,HttpsError});
  await assert.rejects(api.close(req({sessionId:'old',countedCash:0,acknowledgeLegacy:true,autoOpenNext:true})),/รอบเก่า/);
  assert.equal(f.docs.get(path+'cashSessions/old').status,'open');
});
