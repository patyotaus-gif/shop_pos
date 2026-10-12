const {test}=require('node:test');
const assert=require('node:assert/strict');
const {fixture}=require('./accounting_fixture.cjs');
const {confirmOrder,handlers}=require('./order_accounting');
const {refundSale}=require('./refund');
const {summarizeMovements}=require('./money_ledger');
const {verifyOmisePayment}=require('./online_payment_evidence');
const {HttpsError}=require('firebase-functions/v2/https');
const binding={mode:'live',merchantId:'merchant-shop',chargeId:'chrg_live_fixture'};
const order={status:'pendingPayment',paymentMethod:'omise',omise:binding,total:100,finalAmount:100,
  items:[{productId:'tea',productName:'Tea',price:50,quantity:2}]};
const payment={merchantId:'merchant-shop',charge:{object:'charge',id:'chrg_live_fixture',livemode:true,
  amount:10000,currency:'THB',status:'successful',paid:true,captured:true,refunded_amount:0,
  metadata:{pokpokShopId:'shop',pokpokOrderId:'order'}}};
const setup=()=>fixture({'shops/shop/orders/order':structuredClone(order),'shops/shop/products/tea':{stock:10}});
const args=f=>({...f,shopId:'shop',orderId:'order',actor:'omise',omisePayment:structuredClone(payment)});
const owner=data=>({auth:{uid:'shop',token:{}},data:{shopId:'shop',orderId:'order',...data}});

test('verified live Omise evidence writes one online sale and deducts stock once',async()=>{
  const f=setup();await Promise.all([confirmOrder(args(f)),confirmOrder(args(f))]);
  const sale=f.docs.get('shops/shop/sales/order-order');
  assert.equal(sale.total,100);assert.equal(sale.paymentMethod,'online');
  assert.equal(sale.omiseChargeId,binding.chargeId);assert.equal(sale.omiseMerchantId,binding.merchantId);
  assert.equal(f.docs.get('shops/shop/products/tea').stock,8);
  const entry=f.docs.get('shops/shop/moneyMovements/sale-order-order');
  const report=summarizeMovements([entry],0);
  assert.equal(report.grossTotal,100);assert.equal(report.byMethod.online,100);assert.equal(report.expectedCash,0);
  assert.equal([...f.docs.keys()].filter(k=>k.includes('/sales/')).length,1);
});
test('test payments and mismatched settlement evidence never change real shop records',async()=>{
  const invalid=[{livemode:false},{paid:false},{captured:false},{status:'pending'},{amount:9999},{currency:'USD'},
    {refunded_amount:1},{refunded_amount:undefined},{reversed:true},{id:'chrg_live_other'},
    {metadata:{pokpokShopId:'other',pokpokOrderId:'order'}},{metadata:{pokpokShopId:'shop',pokpokOrderId:'other'}}];
  for(const change of invalid){
    const f=setup(),input=args(f);Object.assign(input.omisePayment.charge,change);
    const before=structuredClone([...f.docs]);await assert.rejects(confirmOrder(input));
    assert.deepEqual([...f.docs],before);
  }
});
test('merchant account and server-side live binding are mandatory',()=>{
  for(const changedOrder of [{...order,omise:{...binding,mode:'test'}},{...order,omise:null},
    {...order,omise:{...binding,merchantId:'other'}},{...order,finalAmount:100.91},{...order,paymentMethod:'promptpay'}]){
    assert.throws(()=>verifyOmisePayment({order:changedOrder,shopId:'shop',orderId:'order',payment}));
  }
});
test('manual confirmation cannot inject Omise evidence and Stripe cannot confirm an Omise order',async()=>{
  const f=setup(),api=handlers({...f,HttpsError});
  await assert.rejects(api.confirm(owner({omisePayment:payment})),/verified Omise/);
  const input=args(f);delete input.omisePayment;
  input.stripeSession={id:'stripe',payment_status:'paid',amount_total:10000,currency:'thb'};
  await assert.rejects(confirmOrder(input),/Wrong payment provider/);
  await assert.rejects(api.transition(owner({status:'cancelled',reason:'test'})),/ออนไลน์/);
  assert.equal(f.docs.get('shops/shop/orders/order').status,'pendingPayment');
});
test('local refund cannot invent a successful Omise refund',async()=>{
  const f=setup();await confirmOrder(args(f));const before=structuredClone([...f.docs]);
  await assert.rejects(refundSale({...f,shopId:'shop',saleId:'order-order',reason:'test',returnToStock:true}),/Omise/);
  assert.deepEqual([...f.docs],before);
});
test('customer cannot cancel gateway order and release its inventory without gateway verification',async()=>{
  const {handler,tokenHash}=require('./customer_order');
  const f=setup(),token='a'.repeat(64),ref=f.docs.get('shops/shop/orders/order');ref.customerTokenHash=tokenHash(token);
  const fn=handler({...f,verifyAppCheck:async()=>true});
  const res={code:200,set(){},status(n){this.code=n;return this;},json(d){this.body=d;return this;}};
  await fn({method:'POST',body:{shopId:'shop',orderId:'order',customerToken:token,action:'cancel'}},res);
  assert.equal(res.code,409);assert.equal(f.docs.get('shops/shop/orders/order').status,'pendingPayment');
});
test('gateway order rejects uploaded slip before image/storage processing',async()=>{
  const f=setup();
  const fn=require('./slip_upload').createSlipUpload({...f,verifyAppCheck:async()=>true,getBucket:()=>assert.fail('no upload'),logger:{error:()=>{}}});
  const res={code:200,set(){},status(n){this.code=n;return this;},json(d){this.body=d;return this;}};
  await fn({method:'POST',body:{shopId:'shop',orderId:'order',slipBase64:'invalid'}},res);
  assert.equal(res.code,409);assert.equal(res.body.error,'gateway_payment');
});
