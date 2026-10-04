const {test}=require('node:test');
const assert=require('node:assert/strict');
const {fixture}=require('./accounting_fixture.cjs');
const {summarizeMovements}=require('./money_ledger');
const {confirmOrder,handlers:orders}=require('./order_accounting');
const {handlers:cash}=require('./cash_accounting');
const {refundSale}=require('./refund');
const {HttpsError}=require('firebase-functions/v2/https');
const owner=data=>({auth:{uid:'shop',token:{}},data:{shopId:'shop',acknowledgeDeviceUpdate:true,...data}});
const sale={total:100,items:[{productId:'tea',price:50,quantity:2}],paymentMethod:'cash',stockDeducted:{tea:2}};
test('cash refund nets once; debt collection is cash but not a second sale',()=>{
  const summary=summarizeMovements([
    {kind:'sale',salesMinor:10000,amountMinor:10000,method:'cash'},
    {kind:'refund',salesMinor:-10000,amountMinor:-10000,refundMinor:10000,method:'cash'},
    {kind:'debtPayment',amountMinor:3000,debtMinor:-3000,method:'cash'},
  ],500);
  assert.equal(summary.expectedCash,530);assert.equal(summary.grossTotal,0);assert.equal(summary.debtCollections,30);
});
test('concurrent order confirmations make one sale, stock deduction, and movement',async()=>{
  const f=fixture({'shops/shop/orders/o':{status:'pendingPayment',total:100,items:sale.items},'shops/shop/products/tea':{stock:5}});
  const args={...f,shopId:'shop',orderId:'o',actor:'shop'};
  await Promise.all([confirmOrder(args),confirmOrder(args)]);
  assert.equal(f.docs.get('shops/shop/products/tea').stock,3);
  assert.equal(f.docs.get('shops/shop/orders/o').saleId,'order-o');
  assert.equal(f.docs.get('shops/shop/moneyMovements/sale-order-o').amountMinor,10000);
  assert.equal([...f.docs.keys()].filter(k=>k.includes('/sales/')).length,1);
});
test('unsettled/mismatched Stripe payment cannot confirm an order',async()=>{
  const f=fixture({'shops/shop/orders/o':{status:'pendingPayment',total:100,items:sale.items}});
  for(const stripeSession of [{payment_status:'unpaid',currency:'thb',amount_total:10000},{payment_status:'paid',currency:'thb',amount_total:1}])
    await assert.rejects(confirmOrder({...f,shopId:'shop',orderId:'o',actor:'stripe',stripeSession}),/mismatch/);
  assert.equal(f.docs.get('shops/shop/orders/o').status,'pendingPayment');
});
test('paid order cancellation is rejected; unpaid cancellation needs a reason',async()=>{
  const f=fixture({'shops/shop/orders/o':{status:'paid'}}), api=orders({...f,HttpsError});
  await assert.rejects(api.transition(owner({orderId:'o',status:'cancelled',reason:'test'})),/บิลชำระแล้ว/);
  f.docs.set('shops/shop/orders/o',{status:'pendingPayment'});
  await assert.rejects(api.transition(owner({orderId:'o',status:'cancelled'})),/เหตุผล/);
});
test('collecting debt is idempotent, bounded and rejects a stale balance',async()=>{
  const f=fixture({'shops/shop/sales/s':{...sale,isDebt:true},'shops/shop/debts/d':{saleId:'s',amount:100,paidAmount:0}});
  const api=cash({...f,HttpsError});const req=owner({debtId:'d',requestId:'p',amount:40,method:'cash',expectedPaidAmount:0});
  await Promise.all([api.collectDebt(req),api.collectDebt(req)]);
  assert.equal(f.docs.get('shops/shop/debts/d').paidAmount,40);
  await assert.rejects(api.collectDebt(owner({...req.data,requestId:'p2'})),/ยอดรับชำระเปลี่ยน/);
  await assert.rejects(api.collectDebt(owner({...req.data,requestId:'p3',expectedPaidAmount:40,amount:61})),/เกิน/);
  assert.equal(f.docs.get('shops/shop/moneyMovements/debt-p').salesMinor,0);
});
test('credit refund keeps payment history, cancels remaining debt and refunds collected cash only',async()=>{
  const f=fixture({'shops/shop/sales/s':{...sale,isDebt:true},'shops/shop/debts/d':{saleId:'s',amount:100,paidAmount:40},'shops/shop/products/tea':{stock:3}});
  const args={...f,shopId:'shop',saleId:'s',reason:'test',returnToStock:true};
  await Promise.all([refundSale(args),refundSale(args)]);
  assert.equal(f.docs.get('shops/shop/products/tea').stock,5);
  assert.equal(f.docs.get('shops/shop/debts/d').paidAmount,40);
  assert.ok(f.docs.get('shops/shop/debts/d').cancelledAt);
  const movement=f.docs.get('shops/shop/moneyMovements/refund-s');
  assert.equal(movement.amountMinor,-4000);assert.equal(movement.debtMinor,-6000);
});
test('food refund defaults to no restock and synchronizes the order',async()=>{
  const f=fixture({'shops/shop/sales/s':{...sale,orderId:'o'},'shops/shop/orders/o':{status:'accepted'},'shops/shop/products/tea':{stock:3}});
  await refundSale({...f,shopId:'shop',saleId:'s',reason:'test'});
  assert.equal(f.docs.get('shops/shop/products/tea').stock,3);
  assert.equal(f.docs.get('shops/shop/orders/o').status,'cancelled');
});
test('one session at a time, repeated close returns immutable summary',async()=>{
  const f=fixture(),api=cash({...f,HttpsError});
  await api.open(owner({requestId:'s',openingFloat:500}));
  await assert.rejects(api.open(owner({requestId:'s2',openingFloat:0})),/เปิดอยู่/);
  f.docs.set('shops/shop/sales/old',{total:100,isRefunded:true,refundAmount:100,refundMethod:'cash',refundedAt:1000});
  f.docs.set('shops/shop/moneyMovements/refund-old',{sessionId:'s',saleId:'old',kind:'refund',amountMinor:-10000,refundMinor:10000,salesMinor:-10000,debtMinor:0,method:'cash'});
  const summary=await api.close(owner({sessionId:'s',countedCash:400}));
  assert.equal(summary.expectedCash,400);
  assert.deepEqual(await api.close(owner({sessionId:'s',countedCash:999})),summary);
  assert.equal(f.docs.get('shops/shop/cashSessions/s').countedCash,400);
});

test('closing refuses missing paid-order sale without modifying the session',async()=>{
  const f=fixture(),api=cash({...f,HttpsError});await api.open(owner({requestId:'s',openingFloat:0}));
  f.docs.set('shops/shop/orders/paid',{status:'completed',total:100,paidAt:1000});
  await assert.rejects(api.close(owner({sessionId:'s',countedCash:0})),e=>e.details.issues.some(i=>i.type==='missingSale'));
  assert.equal(f.docs.get('shops/shop/cashSessions/s').status,'open');
  assert.equal(f.docs.get('shops/shop/cashControl/current').sessionId,'s');
});
test('closing refuses duplicate linked sales and unassigned late receipts',async()=>{
  for(const duplicate of [true,false]){
    const f=fixture(),api=cash({...f,HttpsError});await api.open(owner({requestId:'s',openingFloat:0}));
    if(duplicate){
      f.docs.set('shops/shop/orders/o',{status:'paid',paidAt:1000});
      for(const id of ['a','b'])f.docs.set('shops/shop/sales/'+id,{orderId:'o',total:50});
    }else f.docs.set('shops/shop/moneyMovements/late',{needsReconciliation:true,sessionId:null,recordedAt:1000});
    await assert.rejects(api.close(owner({sessionId:'s',countedCash:0})),e=>e.details.issues.some(i=>i.type===(duplicate?'duplicateSale':'unassignedMovement')));
    assert.equal(f.docs.get('shops/shop/cashSessions/s').status,'open');
  }
});
test('sale without its atomic money movement blocks close instead of reporting zero',async()=>{
  const f=fixture(),api=cash({...f,HttpsError});await api.open(owner({requestId:'s',openingFloat:500}));
  f.docs.set('shops/shop/sales/missing',{...sale,createdAt:1000});
  await assert.rejects(api.close(owner({sessionId:'s',countedCash:600})),e=>e.details.issues.some(i=>i.type==='missingMovement'));
});
test('wrong amount or orphan money entry cannot enter a closing snapshot',async()=>{
  for(const orphan of [true,false]){
    const f=fixture(),api=cash({...f,HttpsError});await api.open(owner({requestId:'s',openingFloat:0}));
    if(!orphan)f.docs.set('shops/shop/sales/sale',{...sale,createdAt:1000});
    f.docs.set('shops/shop/moneyMovements/sale-sale',{sessionId:'s',kind:'sale',saleId:'sale',method:'cash',amountMinor:9999,salesMinor:10000,debtMinor:0});
    await assert.rejects(api.close(owner({sessionId:'s',countedCash:100})),e=>e.details.issues.some(i=>i.type===(orphan?'missingSource':'amountMismatch')));
  }
});
test('mixed sale, debt, collection and refund close conserves every satang',async()=>{
  const f=fixture(),api=cash({...f,HttpsError});await api.open(owner({requestId:'s',openingFloat:500}));
  f.docs.set('shops/shop/sales/cash',{...sale,total:100.01,createdAt:1000});
  f.docs.set('shops/shop/sales/credit',{...sale,total:60,isDebt:true,createdAt:1000});
  f.docs.set('shops/shop/debts/d',{saleId:'credit',amount:60,paidAmount:0});
  for(const [id,total,debt] of [['cash',10001,false],['credit',6000,true]])
    f.docs.set('shops/shop/moneyMovements/sale-'+id,{sessionId:'s',kind:'sale',saleId:id,amountMinor:debt?0:total,salesMinor:total,debtMinor:debt?total:0,method:debt?'credit':'cash'});
  f.docs.set('shops/shop/orders/o',{status:'pendingPayment',total:75,finalAmount:75.91,items:[{productId:'tea',price:75,quantity:1}]});
  await confirmOrder({...f,shopId:'shop',orderId:'o',actor:'shop'});
  await api.collectDebt(owner({debtId:'d',requestId:'collect',amount:20.01,method:'cash',expectedPaidAmount:0}));
  await refundSale({...f,shopId:'shop',saleId:'cash',reason:'test'});
  const summary=await api.close(owner({sessionId:'s',countedCash:520.01}));
  assert.equal(summary.grossTotal,135.91);assert.equal(summary.expectedCash,520.01);
  assert.equal(summary.debtTotal,39.99);assert.equal(summary.refundTotal,100.01);
  assert.equal(summary.byMethod.qr,75.91);assert.equal(summary.billCount,3);
  assert.equal(f.docs.get('shops/shop/cashSessions/s').checkedMovementCount,5);
});
test('a closed session cannot be reopened by retrying an old open request',async()=>{
  const f=fixture(),api=cash({...f,HttpsError});await api.open(owner({requestId:'s',openingFloat:0}));
  await assert.rejects(api.open(owner({requestId:'s',openingFloat:1})),/ต่างกัน/);
  await api.close(owner({sessionId:'s',countedCash:0}));
  await assert.rejects(api.open(owner({requestId:'s',openingFloat:0})),/ปิดไปแล้ว/);
});
test('uploaded slip awaiting bank review blocks close; unpaid orders remain explicit',async()=>{
  const f=fixture(),api=cash({...f,HttpsError});await api.open(owner({requestId:'s',openingFloat:0}));
  f.docs.set('shops/shop/orders/unpaid',{status:'pendingPayment',slipReviewStatus:'awaitingOwner'});
  await assert.rejects(api.close(owner({sessionId:'s',countedCash:0})),e=>e.details.issues.some(i=>i.type==='unreviewedPayment'));
  f.docs.set('shops/shop/orders/unpaid',{status:'pendingPayment'});
  f.docs.set('shops/shop/tableOrders/open',{status:'open'});
  const summary=await api.close(owner({sessionId:'s',countedCash:0}));
  assert.equal(summary.pendingOrderCount,1);assert.equal(summary.openTableCount,1);assert.equal(summary.grossTotal,0);
  assert.equal(f.docs.get('shops/shop/orders/unpaid').status,'pendingPayment');
});
test('closed table without a linked sale prevents a misleading clean close',async()=>{
  const f=fixture(),api=cash({...f,HttpsError});await api.open(owner({requestId:'s',openingFloat:0}));
  f.docs.set('shops/shop/tableOrders/closed',{status:'closed',closedAt:1000,saleId:'missing'});
  await assert.rejects(api.close(owner({sessionId:'s',countedCash:0})),e=>e.details.issues.some(i=>i.type==='missingTableSale'));
});
test('inconsistent legacy debt cannot receive or refund an invented amount',async()=>{
  const f=fixture({'shops/shop/sales/s':{...sale,isDebt:true},'shops/shop/debts/d':{saleId:'s',amount:100,paidAmount:120}});
  await assert.rejects(cash({...f,HttpsError}).collectDebt(owner({debtId:'d',requestId:'p',amount:1,method:'cash',expectedPaidAmount:120})),/ไม่ตรง/);
  await assert.rejects(refundSale({...f,shopId:'shop',saleId:'s',reason:'test'}),/ไม่ตรง/);
  assert.equal(f.docs.get('shops/shop/sales/s').isRefunded,undefined);
});
test('employee cannot collect debts or open/close owner cash sessions',async()=>{
  const f=fixture(),api=cash({...f,HttpsError});
  for(const fn of [api.open,api.close,api.collectDebt])await assert.rejects(fn({auth:{uid:'staff',token:{staffRole:'cashier'}},data:{shopId:'shop'}}),e=>e.code==='permission-denied');
});
test('ingredient refund works in both trigger orders and never resurrects deleted inventory',async()=>{
  const {deduct,restore}=require('./ingredient_accounting');
  for(const refundFirst of [true,false]){
    const f=fixture({'shops/shop/sales/s':{isRefunded:refundFirst,returnToStock:true},'shops/shop/ingredients/flour':{stock:10}});
    const args={...f,shop:f.db.collection('shops').doc('shop'),saleRef:f.db.collection('shops').doc('shop').collection('sales').doc('s'),usage:{flour:2,deleted:3}};
    if(refundFirst)await restore(args);
    await deduct(args);
    f.docs.get('shops/shop/sales/s').isRefunded=true;
    await restore(args);await restore(args);await deduct(args);
    assert.equal(f.docs.get('shops/shop/ingredients/flour').stock,10);
    assert.equal(f.docs.has('shops/shop/ingredients/deleted'),false);
  }
});
test('prepared food without stock return stays consumed when refunded before ingredient trigger',async()=>{
  const {deduct,restore}=require('./ingredient_accounting');
  const f=fixture({'shops/shop/sales/s':{isRefunded:true,returnToStock:false},'shops/shop/ingredients/flour':{stock:10}});
  const args={...f,shop:f.db.collection('shops').doc('shop'),saleRef:f.db.collection('shops').doc('shop').collection('sales').doc('s'),usage:{flour:2}};
  await deduct(args);await restore(args);assert.equal(f.docs.get('shops/shop/ingredients/flour').stock,8);
});
test('legacy session archive requires explicit acknowledgement and does not invent a summary',async()=>{
  const f=fixture({'shops/shop/cashSessions/old':{status:'open',openingFloat:500}}),api=cash({...f,HttpsError});
  await assert.rejects(api.close(owner({sessionId:'old',countedCash:123})),/รอบเก่า/);
  await api.close(owner({sessionId:'old',countedCash:123,acknowledgeLegacy:true}));
  assert.equal(f.docs.get('shops/shop/cashSessions/old').summary,null);
  assert.equal(f.docs.get('shops/shop/cashSessions/old').needsReconciliation,true);
});
test('pending Stripe refund never changes sales or inventory until provider succeeds',async()=>{
  const f=fixture({'shops/shop/sales/s':{total:100,paymentMethod:'online',items:[],stripePaymentIntentId:'pi',stockDeducted:{}}});
  const refund={id:'re',status:'pending',metadata:{pokpokShopId:'shop',pokpokSaleId:'s'}};
  const stripe={refunds:{list:async()=>({data:[refund]}),create:async()=>{throw Error('must reuse refund');}}};
  const args={...f,stripe,shopId:'shop',saleId:'s',reason:'test'};
  assert.equal((await refundSale(args)).pending,true);
  assert.notEqual(f.docs.get('shops/shop/sales/s').isRefunded,true);
  assert.equal(f.docs.has('shops/shop/moneyMovements/refund-s'),false);
  refund.status='succeeded';await refundSale(args);await refundSale(args);
  assert.equal(f.docs.get('shops/shop/moneyMovements/refund-s').amountMinor,-10000);
});
test('loyalty is reversed once together with its linked sale refund',async()=>{
  const f=fixture({'shops/shop/sales/s':{...sale,loyaltyCustomerId:'c',loyaltyPointsAwarded:4},
    'shops/shop/customers/c':{points:6,totalSpent:150}});
  const args={...f,shopId:'shop',saleId:'s',reason:'test'};
  await refundSale(args);await refundSale(args);
  assert.deepEqual(f.docs.get('shops/shop/customers/c'),{points:2,totalSpent:50});
});

test('activation requires device acknowledgement and preserves historical boundary',async()=>{
 const f=fixture({'shops/shop/orders/legacy':{status:'paid',paidAt:900,createdAt:900}}),api=cash({...f,HttpsError});
 await assert.rejects(api.open(owner({requestId:'s',openingFloat:0,acknowledgeDeviceUpdate:false})),/ซิงก์/);
 assert.equal(f.docs.has('shops/shop/accountingSettings/current'),false);
 await api.open(owner({requestId:'s',openingFloat:0}));
 assert.equal(f.docs.get('shops/shop/accountingSettings/current').enabled,true);
 await api.close(owner({sessionId:'s',countedCash:0}));
 assert.equal(f.docs.get('shops/shop/orders/legacy').status,'paid');
 await api.open(owner({requestId:'next',openingFloat:0,acknowledgeDeviceUpdate:false}));
 assert.equal(f.docs.get('shops/shop/cashSessions/next').accountingStartAt,1000);
});
