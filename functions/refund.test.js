const { test } = require('node:test');
const assert = require('node:assert/strict');
const { refundSale } = require('./refund');

function fixture() {
  const documents = new Map([
    ['shops/shop/sales/sale', {items:[{productId:'tea',quantity:2}],stripePaymentIntentId:'pi_test'}],
    ['shops/shop/products/tea', {stock:3}],
  ]);
  const copy = value => structuredClone(value);
  function reference(path) {
    return {path, collection:name=>collection(path+'/'+name),
      get:async()=>({exists:documents.has(path),data:()=>copy(documents.get(path))})};
  }
  function collection(path) { return {doc:id=>reference(path+'/'+id),where:()=>({get:async()=>({docs:[]})})}; }
  let tail=Promise.resolve();
  let failNextTransaction=false;
  const db={collection,runTransaction:action=>{
    const run=tail.then(async()=>{
      if(failNextTransaction){failNextTransaction=false;throw Error('connection lost after Stripe response');}
      const writes=[];
      const value=await action({get:ref=>ref.get(),update:(ref,data)=>writes.push([ref.path,data]),delete:()=>{}});
      for(const [path,data] of writes){
        const next={...documents.get(path)};
        for(const [key,value] of Object.entries(data)) next[key]=value?.increment!==undefined?(next[key]||0)+value.increment:value;
        documents.set(path,next);
      }
      return value;
    });
    tail=run.catch(()=>{});return run;
  }};
  const refunds=[];const keys=new Map();let charges=0;
  const stripe={refunds:{list:async()=>({data:[...refunds]}),create:async(payload,options)=>{
    if(keys.has(options.idempotencyKey))return keys.get(options.idempotencyKey);
    charges++;const refund={id:'re_test',status:'succeeded',metadata:payload.metadata};
    keys.set(options.idempotencyKey,refund);refunds.push(refund);return refund;
  }}};
  const args={db,stripe,shopId:'shop',saleId:'sale',reason:'test',FieldValue:{increment:n=>({increment:n}),serverTimestamp:()=>123}};
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
