const {test}=require('node:test');
const assert=require('node:assert/strict');
const coupons=require('./coupons');
const {fixture}=require('./accounting_fixture.cjs');
const {createWithPickup}=require('./pickup');
const {confirmOrder,handlers}=require('./order_accounting');
const {refundSale}=require('./refund');
const {HttpsError}=require('firebase-functions/v2/https');
const future=Date.now()+86400000;
const config={code:'SAVE10',kind:'percent',value:10,minSubtotalMinor:2000,maxUses:1,endsAt:future};
const owner=data=>({auth:{uid:'shop',token:{}},data:{shopId:'shop',...data}});
function setup() {
  const f=fixture({'shops/shop/products/p':{name:'Tea',price:50,stock:10},
    'shops/shop/coupons/SAVE10':{...config,active:true,claimed:0}});
  const shopRef=f.db.collection('shops').doc('shop');
  const create=(id,extra={})=>createWithPickup({...f,shopRef,orderRef:shopRef.collection('orders').doc(id),order:{
    requestSignature:id,status:'pendingPayment',total:100,finalAmount:100.35,paymentMethod:'promptpay',
    couponCode:'SAVE10',couponQuote:{subtotalMinor:10000,discountMinor:1000},
    items:[{productId:'p',productName:'Tea',price:50,quantity:2}],...extra}});
  return {...f,shopRef,create};
}
test('coupon validation, rounding, thresholds and expiry',()=>{
  assert.equal(coupons.validateConfig({...config,code:' save10 '}).code,'SAVE10');
  const c={...config,active:true,claimed:0};
  assert.equal(coupons.quote(c,3535).discountMinor,354);
  for(const edit of [{active:false},{endsAt:Date.now()-1},{claimed:1},{minSubtotalMinor:10001}])
    assert.throws(()=>coupons.quote({...c,...edit},10000),/คูปอง/);
  assert.throws(()=>coupons.quote({...c,kind:'fixed',value:9000},10000),/20/);
  for(const edit of [{code:'../a'},{value:100},{maxUses:0},{endsAt:0},{minSubtotalMinor:-1}])
    assert.throws(()=>coupons.validateConfig({...config,...edit}),/คูปอง/);
});
test('owner creates and toggles, cannot reuse codes or edit counters, denies staff/other shop',async()=>{
  const f=fixture(), manage=coupons.manage({...f,HttpsError});
  await manage(owner({...config,action:'create'}));
  assert.equal(f.docs.get('shops/shop/coupons/SAVE10').claimed,0);
  await assert.rejects(()=>manage(owner({...config,action:'create'})),/มีโค้ด/);
  await manage(owner({code:'SAVE10',action:'toggle',active:false,claimed:999}));
  assert.equal(f.docs.get('shops/shop/coupons/SAVE10').claimed,0);
  await assert.rejects(()=>manage({auth:{uid:'other',token:{}},data:{shopId:'shop',...config,action:'create'}}));
  await assert.rejects(()=>manage({auth:{uid:'shop',token:{staffRole:'cashier'}},data:{shopId:'shop',...config,action:'create'}}));
});
test('last use is serialized, retry does not spend again; pending cancel releases once',async()=>{
  const f=setup();
  const results=await Promise.allSettled([f.create('a'),f.create('b')]);
  assert.equal(results.filter(r=>r.status==='fulfilled').length,1);
  const id=results[0].status==='fulfilled'?'a':'b';
  const saved=await f.create(id);
  assert.equal(saved.total,90);assert.equal(saved.finalAmount,90.35);
  const api=handlers({...f,HttpsError});
  await api.transition(owner({orderId:id,status:'cancelled',reason:'not paid'}));
  await api.transition(owner({orderId:id,status:'cancelled',reason:'not paid'}));
  assert.equal(f.docs.get('shops/shop/coupons/SAVE10').claimed,0);
  await f.create('c');
  assert.equal(f.docs.get('shops/shop/coupons/SAVE10').claimed,1);
});
test('bad quote and inventory failure roll back coupon claim',async()=>{
  const f=setup();
  await assert.rejects(()=>f.create('a',{couponQuote:{subtotalMinor:10000,discountMinor:9999}}),/ยอดเปลี่ยน/);
  f.docs.get('shops/shop/products/p').stock=0;
  await assert.rejects(()=>f.create('b'),/ไม่พอ/);
  assert.equal(f.docs.get('shops/shop/coupons/SAVE10').claimed,0);
});
test('Firestore callback retry rechecks coupon instead of reusing mutated discounted order',async()=>{
  const f=setup(),run=f.db.runTransaction;
  f.db.runTransaction=async action=>{
    await action({get:ref=>ref.get(),set(){},create(){},update(){}}); // aborted attempt
    f.docs.get('shops/shop/coupons/SAVE10').claimed=1; // rival committed first
    return run(action);
  };
  await assert.rejects(()=>f.create('retry'),/สิทธิ์ครบ/);
  assert.equal(f.docs.has('shops/shop/orders/retry'),false);
});
test('payment, receipt discount, stock and refund use net amount; paid use is not restored',async()=>{
  const f=setup();await f.create('a');
  f.docs.get('shops/shop/coupons/SAVE10').active=false;
  const args={...f,shopId:'shop',orderId:'a',actor:'shop'};
  const {saleId}=await confirmOrder(args);await confirmOrder(args);
  const sale=f.docs.get('shops/shop/sales/'+saleId);
  assert.equal(sale.total,90.35);assert.equal(sale.discount,10);assert.equal(sale.paymentAdjustment,.35);
  assert.equal(sale.items.reduce((s,i)=>s+i.subtotal,0),100);
  assert.equal(f.docs.get('shops/shop/products/p').stock,8);
  assert.equal(f.docs.get('shops/shop/moneyMovements/sale-'+saleId).amountMinor,9035);
  await refundSale({...f,shopId:'shop',saleId,reason:'test',returnToStock:true,actor:'shop'});
  assert.equal(f.docs.get('shops/shop/products/p').stock,10);
  assert.equal(f.docs.get('shops/shop/moneyMovements/refund-'+saleId).amountMinor,-9035);
  assert.equal(f.docs.get('shops/shop/coupons/SAVE10').claimed,1);
});
