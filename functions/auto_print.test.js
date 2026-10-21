'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {HttpsError} = require('firebase-functions/v2/https');
const {fixture} = require('./accounting_fixture.cjs');
const {handlers, candidates} = require('./auto_print');
const root = 'shops/shop', cfg = root + '/autoPrintConfig/current';
const item = {id:'i1',productName:'ข้าวผัด',quantity:1,kitchenStatus:'sent'};
const table = {status:'open',tableName:'A1',items:[item]};
const req = data => ({auth:{uid:'shop',token:{}},data:{shopId:'shop',deviceId:'phone',...data}});
async function setup() {
  const f = fixture(); let clock = 1000;
  const h = handlers({...f,HttpsError,now:()=>clock});
  const config = await h.configure(req({enabled:true,kitchen:true,receipts:true}));
  const request = data => req({session:config.session,...data});
  const enqueue = async (source='table', sourceId='t', after=table, before=undefined, eventAtMs=2000) => {
    f.docs.set(`${root}/${source==='table'?'tableOrders':source==='online'?'orders':'sales'}/${sourceId}`,after);
    await h.enqueue({shopId:'shop',source,sourceId,after,before,eventAtMs});
  };
  return {...f,h,request,enqueue,time:t=>{clock=t;}};
}
test('only new sent table lines and accepted online orders produce preparation jobs', () => {
  assert.equal(candidates('table',null,{...table,items:[{...item,kitchenStatus:'pending'}]},'t').length,0);
  assert.equal(candidates('table',table,{...table,items:[{...item,kitchenStatus:'ready'}]},'t').length,0);
  const next={...table,items:[item,{...item,id:'i2'}]};
  assert.equal(candidates('table',table,next,'t')[0].lines.length,1);
  assert.equal(candidates('online',null,{...table,status:'pendingPayment'},'o').length,0);
  assert.equal(candidates('online',{...table,status:'pendingPayment'},{...table,status:'accepted'},'o').length,1);
  assert.equal(candidates('online',{...table,status:'paid'},{...table,status:'accepted'},'o').length,0);
});
test('counter takeaway creates preparation plus receipt; linked online/table sales only receipt; debts never receipt', () => {
  const sale={items:[item],salesChannel:'takeaway',isDebt:false};
  assert.equal(candidates('sale',null,sale,'s').length,2);
  assert.equal(candidates('sale',null,{...sale,orderId:'o'},'s').length,1);
  assert.equal(candidates('sale',null,{...sale,tableName:'A1'},'s').length,1);
  assert.equal(candidates('sale',null,{...sale,isDebt:true},'s').length,0);
  assert.equal(candidates('sale',null,{...sale,isRefunded:true},'s').length,0);
  assert.equal(candidates('sale',sale,sale,'s').length,0);
});
test('duplicate trigger delivery creates one job and never resets sent status', async () => {
  const f=await setup(); await f.enqueue(); await f.enqueue();
  const j=await f.h.claim(f.request());
  await f.h.finish(f.request({jobId:j.jobId,attempt:j.attempt,outcome:'sent'}));
  await f.enqueue();
  assert.deepEqual(await f.h.claim(f.request()),{empty:true});
  assert.equal([...f.docs.keys()].filter(p=>p.includes('/autoPrintJobs/')).length,1);
  assert.equal(f.docs.get(root+'/autoPrintJobs/'+j.jobId).status,'sent');
});
test('concurrent claims have exactly one winner, and manual kitchen claim cannot duplicate it', async () => {
  const f=await setup();await f.enqueue();
  const jobs=await Promise.all([f.h.claim(f.request()),f.h.claim(f.request())]);
  assert.equal(jobs.filter(j=>j.attempt).length,1);
  const manual=require('./kitchen_print').handlers({...f,HttpsError});
  await assert.rejects(()=>manual.claim(req({source:'table',orderId:'t'})),{code:'failed-precondition'});
  const j=jobs.find(j=>j.attempt);
  await f.h.finish(f.request({jobId:j.jobId,attempt:j.attempt,outcome:'sent'}));
  assert.deepEqual(await manual.claim(req({source:'table',orderId:'t'})),{alreadyPrinted:true});
});
test('manual printing completed first consumes the automatic job without resending', async () => {
  const f=await setup();await f.enqueue();
  const manual=require('./kitchen_print').handlers({...f,HttpsError});
  const j=await manual.claim(req({source:'table',orderId:'t'}));
  await manual.finish(req({jobId:j.jobId,attempt:j.attempt,received:true}));
  assert.deepEqual(await f.h.claim(f.request()),{empty:true});
});
test('partial failure blocks following jobs until explicit review, retry is labelled copy', async () => {
  const f=await setup();await f.enqueue();await f.enqueue('table','t2',table,undefined,3000);
  const j=await f.h.claim(f.request());
  await f.h.finish(f.request({jobId:j.jobId,attempt:j.attempt,outcome:'needsReview'}));
  assert.deepEqual(await f.h.claim(f.request()),{blocked:j.jobId});
  await f.h.review(req({jobId:j.jobId,action:'retry'}));
  const retry=await f.h.claim(f.request());
  assert.equal(retry.reprint,true);assert.notEqual(retry.attempt,j.attempt);
  await assert.rejects(()=>f.h.finish(f.request({jobId:j.jobId,attempt:j.attempt,outcome:'sent'})),{code:'failed-precondition'});
});
test('lost finish acknowledgement is idempotent and does not advance the spool twice', async () => {
  const f=await setup();await f.enqueue();
  const j=await f.h.claim(f.request()),r=f.request({jobId:j.jobId,attempt:j.attempt,outcome:'sent'});
  await f.h.finish(r); const before=structuredClone([...f.docs]);await f.h.finish(r);
  assert.deepEqual([...f.docs],before);
});
test('crashed sending job is not stolen or retried on timeout; owner must review after grace', async () => {
  const f=await setup();await f.enqueue();const j=await f.h.claim(f.request());
  await assert.rejects(()=>f.h.review(req({jobId:j.jobId,action:'retry'})),{code:'failed-precondition'});
  f.time(400000);
  assert.deepEqual(await f.h.claim(f.request()),{blocked:j.jobId});
  await f.h.review(req({jobId:j.jobId,action:'received'}));
  assert.deepEqual(await f.h.claim(f.request()),{empty:true});
});
test('primary takeover requires expired lease and rejects the old session', async () => {
  const f=await setup();
  const other=req({deviceId:'other',enabled:true,kitchen:true,receipts:true});
  await assert.rejects(()=>f.h.configure(other),{code:'failed-precondition'});
  f.time(130000);await f.h.configure(other);
  await assert.rejects(()=>f.h.claim(f.request()),{code:'failed-precondition'});
  await assert.rejects(()=>f.h.heartbeat(f.request()),{code:'failed-precondition'});
});
test('disabled mode and pre-activation events do not import historical jobs', async () => {
  const f=await setup();await f.enqueue('table','old',table,undefined,999);
  assert.deepEqual(await f.h.claim(f.request()),{empty:true});
  await f.h.configure(req({enabled:false}));await f.enqueue();
  assert.equal([...f.docs.keys()].filter(p=>p.includes('/autoPrintJobs/')).length,0);
});
test('cancelled or refunded source is skipped at claim', async () => {
  const f=await setup();await f.enqueue();
  f.docs.set(root+'/tableOrders/t',{...table,status:'cancelled'});
  assert.deepEqual(await f.h.claim(f.request()),{empty:true});
});
test('cancellation or stop during rendering rejects authorization before Bluetooth output', async () => {
  const f=await setup();await f.enqueue();const j=await f.h.claim(f.request());
  const authorize=f.request({jobId:j.jobId,attempt:j.attempt});
  await f.h.heartbeat(authorize);
  f.docs.set(root+'/tableOrders/t',{...table,status:'cancelled'});
  await assert.rejects(()=>f.h.heartbeat(authorize),{code:'failed-precondition'});
  f.docs.set(root+'/tableOrders/t',table);
  await f.h.configure(req({enabled:false}));
  await assert.rejects(()=>f.h.heartbeat(authorize),{code:'failed-precondition'});
});
test('unauthenticated, cross-shop and cashier requests cannot control print station', async () => {
  const f=await setup();
  for (const auth of [null,{uid:'other',token:{}},{uid:'shop',token:{staffRole:'cashier'}}]) {
    await assert.rejects(()=>f.h.configure({...req({enabled:true,kitchen:true,receipts:true}),auth}),{code:'permission-denied'});
    await assert.rejects(()=>f.h.claim({...f.request(),auth}),{code:'permission-denied'});
  }
});
