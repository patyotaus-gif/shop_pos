const {test}=require('node:test');
const assert=require('node:assert/strict');
const {fixture}=require('./accounting_fixture.cjs');
const {handlers}=require('./cash_accounting');
const {confirmOrder,handlers:orderHandlers}=require('./order_accounting');
const {HttpsError}=require('firebase-functions/v2/https');
const owner=data=>({auth:{uid:'shop',token:{}},data:{shopId:'shop',acknowledgeDeviceUpdate:true,...data}});
const now=Date.parse('2026-10-09T16:59:00Z'); // 23:59 in Thailand, not the developer's timezone.
const tomorrow=Date.parse('2026-10-09T17:00:00Z');
async function setup(initial={}) {
  const f=fixture(initial),api=handlers({...f,HttpsError,now:()=>now});
  await api.open(owner({requestId:'s',openingFloat:200}));
  return {...f,api};
}
const close=api=>api.close(owner({sessionId:'s',countedCash:200}));
test('today and overdue paid work block until delivered; cancelled orders do not block',async()=>{
  const f=await setup(),orders=orderHandlers({...f,HttpsError});
  f.docs.set('shops/shop/orders/o',{status:'pendingPayment',createdAt:1,total:50,items:[{productId:'tea',price:50,quantity:1}]});
  await confirmOrder({...f,shopId:'shop',orderId:'o',actor:'shop'});
  for(const status of ['paid','accepted','ready']) {
    if(status!=='paid')await orders.transition(owner({orderId:'o',status}));
    await assert.rejects(close(f.api),e=>e.details.issues.some(i=>i.type==='unfinishedOrder'));
    assert.equal(f.docs.get('shops/shop/cashSessions/s').status,'open');
  }
  await orders.transition(owner({orderId:'o',status:'completed'}));
  f.docs.set('shops/shop/orders/cancelled',{status:'cancelled'});
  assert.equal((await f.api.readiness(owner({sessionId:'s'}))).canClose,true);
  const summary=await close(f.api);
  assert.equal(summary.grossTotal,50);assert.equal(summary.expectedCash,200);
});
test('future scheduled orders carry forward while money stays in its receipt round',async()=>{
  const f=await setup();
  f.docs.set('shops/shop/orders/future-paid',{status:'pendingPayment',total:50,items:[{productId:'tea',price:50,quantity:1}],pickupMode:'scheduled',pickupStartAt:tomorrow});
  f.docs.set('shops/shop/orders/future-unpaid',{status:'pendingPayment',pickupMode:'scheduled',pickupStartAt:tomorrow+3600000});
  await confirmOrder({...f,shopId:'shop',orderId:'future-paid',actor:'shop'});
  const check=await f.api.readiness(owner({sessionId:'s'}));
  assert.equal(check.canClose,true);assert.equal(check.futureOrderCount,2);
  const summary=await close(f.api);
  assert.equal(summary.futureOrderCount,2);assert.equal(summary.grossTotal,50);assert.equal(summary.byMethod.qr,50);
  assert.equal(summary.pendingOrderCount,1);
  assert.equal(f.docs.get('shops/shop/orders/future-paid').status,'paid');
  assert.equal(f.docs.get('shops/shop/orders/future-unpaid').status,'pendingPayment');
  // Moving to the pickup day makes that same unfinished work block again.
  const next=handlers({...f,HttpsError,now:()=>tomorrow});
  await next.open(owner({requestId:'next',openingFloat:200}));
  await assert.rejects(next.close(owner({sessionId:'next',countedCash:200})),e=>
    ['unfinishedOrder','pendingOrder'].every(type=>e.details.issues.some(i=>i.type===type)));
  assert.equal(f.docs.get('shops/shop/cashSessions/s').summary.grossTotal,50);
});
test('missing, invalid, ASAP and today pickup times cannot bypass the guard',async()=>{
  for(const pickup of [undefined,null,'tomorrow',Infinity,NaN,tomorrow-1,now-86400000]) {
    const f=await setup();
    f.docs.set('shops/shop/orders/o',{status:'pendingPayment',pickupMode:'scheduled',pickupStartAt:pickup});
    await assert.rejects(close(f.api),e=>e.details.issues.some(i=>i.type==='pendingOrder'));
  }
  const f=await setup();
  f.docs.set('shops/shop/orders/o',{status:'pendingPayment',pickupMode:'asap',pickupStartAt:tomorrow});
  await assert.rejects(close(f.api),e=>e.details.issues.some(i=>i.type==='pendingOrder'));
});
test('future pickups with unreviewed payment still block',async()=>{
  for(const evidence of [{slipUrl:'test'},{slipReviewStatus:'awaitingOwner'},{bankMatchStatus:'awaitingOwner'}]) {
    const f=await setup();
    f.docs.set('shops/shop/orders/o',{status:'pendingPayment',pickupMode:'scheduled',pickupStartAt:tomorrow,...evidence});
    await assert.rejects(close(f.api),e=>e.details.issues.some(i=>i.type==='unreviewedPayment'));
  }
});
test('legacy acknowledgement cannot bypass unresolved old work',async()=>{
  for(const collection of ['orders','tableOrders']) {
    const f=fixture({'shops/shop/cashSessions/old':{status:'open'},
      ['shops/shop/'+collection+'/old']:{status:collection==='orders'?'pendingPayment':'open',createdAt:1}});
    const api=handlers({...f,HttpsError});
    await assert.rejects(api.close(owner({sessionId:'old',countedCash:0,acknowledgeLegacy:true})),e=>e.code==='failed-precondition');
    assert.equal(f.docs.get('shops/shop/cashSessions/old').status,'open');
  }
});
test('preflight does not write or authorize a later close after a new order arrives',async()=>{
  const f=await setup(),before=structuredClone([...f.docs]);
  assert.equal((await f.api.readiness(owner({sessionId:'s'}))).canClose,true);
  assert.deepEqual([...f.docs],before);
  f.docs.set('shops/shop/orders/late',{status:'pendingPayment'});
  await assert.rejects(close(f.api),e=>e.details.issues.some(i=>i.type==='pendingOrder'));
  assert.equal(f.docs.get('shops/shop/cashSessions/s').status,'open');
});
test('closed retries preserve the original snapshot even with subsequent new work',async()=>{
  const f=await setup();const saved=await close(f.api);
  f.docs.set('shops/shop/orders/new',{status:'pendingPayment'});
  assert.deepEqual(await close(f.api),saved);
  assert.equal((await f.api.readiness(owner({sessionId:'s'}))).closed,true);
});
test('another owner cannot inspect or close a shop session',async()=>{
  const f=await setup();
  for(const fn of [f.api.readiness,f.api.close])
    await assert.rejects(fn({auth:{uid:'other',token:{}},data:{shopId:'shop',sessionId:'s',countedCash:200}}),e=>e.code==='permission-denied');
});
