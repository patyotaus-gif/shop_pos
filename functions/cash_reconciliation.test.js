const {test}=require('node:test');
const assert=require('node:assert/strict');
const {fixture}=require('./accounting_fixture.cjs');
const {HttpsError}=require('firebase-functions/v2/https');
const {handlers}=require('./cash_accounting');
const {handler}=require('./cash_reconciliation');
const request=data=>({auth:{uid:'shop',token:{}},data:{shopId:'shop',...data}});
const data={movementId:'sale-s',sessionId:'round',reason:'checked receipt',expectedAmountMinor:7000,cashTreatment:'addToDrawer'};
async function setup(method='cash',kind='sale') {
  const f=fixture();const api=handlers({...f,HttpsError});
  await api.open(request({requestId:'round',openingFloat:500,acknowledgeDeviceUpdate:true}));
  f.docs.set('shops/shop/sales/s',{total:70,paymentMethod:method,createdAt:500,isRefunded:kind==='refund',refundAmount:70,refundMethod:method});
  const row={kind,saleId:'s',method,amountMinor:7000,salesMinor:7000,debtMinor:0,
    occurredAt:500,recordedAt:1000,sessionId:null,needsReconciliation:true};
  if(kind==='refund')Object.assign(row,{amountMinor:-7000,salesMinor:-7000,refundMinor:7000});
  if(kind==='debtPayment'){
    Object.assign(row,{debtId:'d',salesMinor:0,debtMinor:-7000});
    f.docs.set('shops/shop/debtPayments/p',{saleId:'s',debtId:'d',amountMinor:7000,method,createdAt:500});
  }
  const id=kind==='sale'?'sale-s':kind==='refund'?'refund-s':'debt-p';
  f.docs.set('shops/shop/moneyMovements/'+id,row);
  return {...f,api,assign:handler({...f,HttpsError}),id,row};
}
test('unassigned verified sale blocks close until owner assigns; retry never duplicates',async()=>{
  const f=await setup();
  await assert.rejects(f.api.close(request({sessionId:'round',countedCash:570})),e=>e.details.issues.some(i=>i.type==='unassignedMovement'));
  await Promise.all([f.assign(request(data)),f.assign(request(data))]);
  const m=f.docs.get('shops/shop/moneyMovements/sale-s');
  assert.equal(m.sessionId,'round');assert.equal(m.needsReconciliation,false);
  for(const k of ['amountMinor','salesMinor','debtMinor','method','occurredAt','recordedAt'])assert.equal(m[k],f.row[k]);
  assert.equal(m.reconciliation.actor,'shop');
  const summary=await f.api.close(request({sessionId:'round',countedCash:570}));
  assert.equal(summary.grossTotal,70);assert.equal(summary.expectedCash,570);assert.equal(summary.reconciledCount,1);
  await f.assign(request(data));
  assert.deepEqual(await f.api.close(request({sessionId:'round',countedCash:0})),summary);
  assert.equal([...f.docs.keys()].filter(k=>k.includes('/moneyMovements/')).length,1);
});
test('cash already included in opening balance is not counted twice, including negative refunds',async()=>{
  for(const kind of ['sale','refund','debtPayment']){
    const f=await setup('cash',kind);
    await f.assign(request({...data,movementId:f.id,expectedAmountMinor:f.row.amountMinor,cashTreatment:'includedInOpeningFloat'}));
    const summary=await f.api.close(request({sessionId:'round',countedCash:500}));
    assert.equal(summary.expectedCash,500);assert.equal(summary.openingCashIncluded,f.row.amountMinor/100);
    assert.equal(summary.grossTotal,f.row.salesMinor/100);
    assert.equal(summary.byMethod.cash,f.row.amountMinor/100);
  }
});
test('noncash stays outside drawer; cash treatment must match method',async()=>{
  const f=await setup('qr');
  for(const cashTreatment of ['addToDrawer','includedInOpeningFloat'])
    await assert.rejects(f.assign(request({...data,cashTreatment})));
  await f.assign(request({...data,cashTreatment:'nonCash'}));
  const summary=await f.api.close(request({sessionId:'round',countedCash:500}));
  assert.equal(summary.expectedCash,500);assert.equal(summary.byMethod.qr,70);
});
test('assignment requires owner, fresh valid amount, open round and a matching immutable source',async()=>{
  const f=await setup();
  for(const auth of [undefined,{uid:'other',token:{}},{uid:'shop',token:{staffRole:'cashier'}}])
    await assert.rejects(f.assign({auth,data:{shopId:'shop',...data}}),e=>e.code==='permission-denied');
  for(const override of [{reason:''},{reason:'x'.repeat(301)},{expectedAmountMinor:1},{movementId:'bad/id'},
    {sessionId:'closed'},{cashTreatment:'nonCash'},{cashTreatment:'skip'}])
    await assert.rejects(f.assign(request({...data,...override})));
  f.docs.get('shops/shop/sales/s').total=99;
  await assert.rejects(f.assign(request(data)),e=>e.details.issues.some(i=>i.type==='amountMismatch'));
  assert.equal(f.docs.get('shops/shop/moneyMovements/sale-s').needsReconciliation,true);
});
test('cannot reassign existing round, edit prior reconciliation or use a closed session',async()=>{
  const f=await setup();const m=f.docs.get('shops/shop/moneyMovements/sale-s');
  m.sessionId='old';await assert.rejects(f.assign(request(data)));m.sessionId=null;
  await f.assign(request(data));
  for(const override of [{reason:'changed'},{expectedAmountMinor:1},{sessionId:'new'},{cashTreatment:'includedInOpeningFloat'}])
    await assert.rejects(f.assign(request({...data,...override})));
  const g=await setup();g.docs.get('shops/shop/cashSessions/round').status='closed';
  await assert.rejects(g.assign(request(data)));
});
test('assignment does not bypass outstanding work or source integrity guards',async()=>{
  const f=await setup();await f.assign(request(data));
  f.docs.set('shops/shop/orders/pending',{status:'pendingPayment',createdAt:1000});
  await assert.rejects(f.api.close(request({sessionId:'round',countedCash:570})),e=>e.details.issues.some(i=>i.type==='pendingOrder'));
});
