const {test}=require('node:test');
const assert=require('node:assert/strict');
const {fixture}=require('./accounting_fixture.cjs');
const queue=require('./round_queue');
const {createWithPickup}=require('./pickup');
const {handlers}=require('./order_accounting');
const {HttpsError}=require('firebase-functions/v2/https');
const root='shops/shop';
function setup() {
  const f=fixture({[root+'/cashControl/current']:{sessionId:'round-a'},[root+'/cashSessions/round-a']:{status:'open'}});
  const shop=f.db.collection('shops').doc('shop');
  const create=(id,time,extra={})=>createWithPickup({db:f.db,shopRef:shop,orderRef:shop.collection('orders').doc(id),
    order:{total:20,finalAmount:20,status:'pendingPayment',requestSignature:id,...extra},now:()=>time});
  return {...f,shop,create};
}
test('online queues survive midnight and cancellation; replay and shop/round/channel isolation',async()=>{
  const f=setup(), time=Date.parse('2026-10-30T16:59:59Z');
  const a=await f.create('a',time);
  assert.equal(a.queueNumber,'001');
  assert.equal((await f.create('a',time+2000)).queueNumber,'001');
  f.docs.get(root+'/orders/a').status='cancelled';
  assert.equal((await f.create('b',time+2000)).queueNumber,'002');
  const takeaway=await f.db.runTransaction(async tx=>{const q=await queue.prepare(tx,f.shop,'takeaway');q.write();return q.fields;});
  assert.equal(takeaway.queueNumber,'001');
  f.docs.set(root+'/cashSessions/round-a',{status:'closed'});
  f.docs.set(root+'/cashControl/current',{sessionId:'round-b'});
  f.docs.set(root+'/cashSessions/round-b',{status:'open'});
  const c=await f.create('c',time+3000);
  assert.equal(c.queueNumber,'001');assert.equal(c.queueSessionId,'round-b');
  assert.equal((await f.create('b',time+4000)).queueNumber,'002');
  const other=f.db.collection('shops').doc('other');
  const empty=await f.db.runTransaction(tx=>queue.prepare(tx,other,'online'));
  assert.deepEqual(empty.fields,{});
});
test('closed rounds and table orders never allocate a takeaway/online counter',async()=>{
  const f=setup();f.docs.set(root+'/cashSessions/round-a',{status:'closed'});
  assert.equal((await f.create('closed',Date.now())).queueNumber,undefined);
  assert.equal([...f.docs.keys()].filter(k=>k.includes('/counters/queue-')).length,0);
  assert.equal(queue.label({tableName:'A1'}),'โต๊ะ A1');
  assert.equal(queue.label({queueNumber:'001',queueChannel:'online',queueSessionId:'a'}),'ออนไลน์ 001');
});
test('scheduled orders receive their queue when accepted, including the existing paid receipt',async()=>{
  const f=setup(), ref=root+'/orders/future', sale=root+'/sales/paid-future';
  f.docs.set(ref,{status:'paid',pickupMode:'scheduled',orderNumber:'20261030-005',saleId:'paid-future',items:[]});
  f.docs.set(sale,{orderId:'future',total:20,receiptNo:'WEB-future'});
  const h=handlers({...f,HttpsError});
  const request={auth:{uid:'shop',token:{}},data:{shopId:'shop',orderId:'future',status:'accepted'}};
  await h.transition(request);await h.transition(request);
  assert.equal(f.docs.get(ref).queueNumber,'001');
  assert.equal(f.docs.get(sale).queueNumber,'001');
  assert.equal(f.docs.get(sale).total,20);assert.equal(f.docs.get(sale).receiptNo,'WEB-future');
  assert.equal(f.docs.get(root+'/counters/queue-round-a-online').seq,1);
});
test('failed transactions roll back the number and >999 numbers do not wrap',async()=>{
  const f=setup(), counter=root+'/counters/queue-round-a-takeaway';
  await assert.rejects(f.db.runTransaction(async tx=>{const q=await queue.prepare(tx,f.shop,'takeaway');q.write();throw Error('abort');}));
  assert.equal(f.docs.has(counter),false);
  f.docs.set(counter,{seq:999});
  const q=await f.db.runTransaction(async tx=>{const q=await queue.prepare(tx,f.shop,'takeaway');q.write();return q.fields;});
  assert.equal(q.queueNumber,'1000');
});
test('auto printing carries queue labels and delays scheduled kitchen work until acceptance',()=>{
  const {candidates}=require('./auto_print');
  const order={status:'paid',pickupMode:'scheduled',items:[{productName:'Tea',quantity:1}]};
  assert.equal(candidates('online',null,order,'o').length,0);
  const jobs=candidates('online',order,{...order,status:'accepted',queueNumber:'007',queueSessionId:'s',queueChannel:'online'},'o');
  assert.equal(jobs[0].queueLabel,'ออนไลน์ 007');
  const sale={items:order.items,salesChannel:'takeaway',queueNumber:'003',queueSessionId:'s',queueChannel:'takeaway'};
  assert.equal(candidates('sale',null,sale,'s')[0].queueLabel,'กลับบ้าน 003');
  const asap={...order,pickupMode:'asap',pickupStartAt:new Date('2026-10-31T02:00:00Z')};
  assert.equal(candidates('online',null,asap,'next-day').length,0);
  assert.equal(candidates('online',asap,{...asap,status:'accepted',queueNumber:'002',queueChannel:'online',queueSessionId:'next'},'next-day')[0].queueLabel,'ออนไลน์ 002');
  assert.equal(queue.onlineChannel(asap,Date.parse('2026-10-30T02:00:00Z')),null);
});
test('web labels keep table names, queue channel and legacy references distinct',async()=>{
  const {orderLabel}=await import('../public/order/js/order-display.mjs');
  assert.equal(orderLabel({queueNumber:'001',queueSessionId:'s',queueChannel:'online'}),'ออนไลน์ 001');
  assert.equal(orderLabel({tableName:'B2',orderNumber:'old'}),'โต๊ะ B2');
  assert.equal(orderLabel({orderNumber:'20261030-001'}),'เลขออเดอร์ 20261030-001');
});
