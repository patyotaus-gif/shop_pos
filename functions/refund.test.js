const { test } = require('node:test');
const assert = require('node:assert/strict');
const { refundSale } = require('./refund');

function fixture() {
  const base=require('./accounting_fixture.cjs').fixture({
    'shops/shop/sales/sale':{total:100,paymentMethod:'online',items:[{productId:'tea',quantity:2}],stockDeducted:{tea:2},stripePaymentIntentId:'pi_test'},
    'shops/shop/products/tea':{stock:3},
  });
  const documents=base.docs;
  let failNextTransaction=false;
  const db={...base.db,runTransaction:async action=>{
    if(failNextTransaction){failNextTransaction=false;throw Error('connection lost after Stripe response');}
    return base.db.runTransaction(action);
  }};
  const refunds=[];const keys=new Map();let charges=0;
  const stripe={refunds:{list:async()=>({data:[...refunds]}),create:async(payload,options)=>{
    if(keys.has(options.idempotencyKey))return keys.get(options.idempotencyKey);
    charges++;const refund={id:'re_test',status:'succeeded',metadata:payload.metadata};
    keys.set(options.idempotencyKey,refund);refunds.push(refund);return refund;
  }}};
  const args={db,stripe,shopId:'shop',saleId:'sale',reason:'test',returnToStock:true,FieldValue:{increment:n=>({increment:n}),serverTimestamp:()=>123}};
  return {args,documents,get charges(){return charges;},failNext:()=>{failNextTransaction=true;}};
}

test('concurrent online refund calls restore inventory and refund payment once',async()=>{
  const f=fixture();await Promise.all([refundSale(f.args),refundSale(f.args)]);
  assert.equal(f.charges,1);assert.equal(f.documents.get('shops/shop/products/tea').stock,5);
  assert.equal(f.documents.get('shops/shop/sales/sale').isRefunded,true);
});
test('retry after Stripe succeeded but Firestore failed recovers the same refund',async()=>{
  const f=fixture();f.failNext();await assert.rejects(refundSale(f.args),/connection lost/);
  await refundSale(f.args);await refundSale(f.args);
  assert.equal(f.charges,1);assert.equal(f.documents.get('shops/shop/products/tea').stock,5);
});

test('refund callable rejects anonymous callers and a different shop owner',async()=>{
  const endpoint=require('./index').createRefund;
  await assert.rejects(endpoint.run({data:{shopId:'shop',saleId:'sale'}}),e=>e.code==='permission-denied');
  await assert.rejects(endpoint.run({data:{shopId:'shop',saleId:'sale'},auth:{uid:'other-shop'}}),e=>e.code==='permission-denied');
});
