const {test} = require('node:test');
const assert = require('node:assert/strict');
const {sendOwnerLineMessage} = require('./line_delivery');
class HttpsError extends Error { constructor(code, message) { super(message); this.code = code; } }
const id = 'U' + 'a'.repeat(32);
function fixture(settings = {lineUserId:id, lineNotifyEnabled:true}, accepted = true) {
  let reads = 0, sends = 0;
  const ref = {collection:()=>ref, doc:()=>ref, get:async()=>{reads++; return {data:()=>settings};}};
  return {
    args: {request:{auth:{uid:'owner',token:{}},data:{shopId:'owner',message:'Test'}},db:ref,HttpsError,
      push:async(to)=>{sends++; assert.equal(to,id); return accepted;}},
    counts:()=>({reads,sends}),
  };
}
test('reject anonymous, foreign owner and staff before accessing settings', async()=>{
  for(const auth of [null,{uid:'other'},{uid:'owner',token:{staffRole:'cashier'}}]) {
    const f=fixture(); f.args.request.auth=auth;
    await assert.rejects(sendOwnerLineMessage(f.args),{code:'permission-denied'});
    assert.deepEqual(f.counts(),{reads:0,sends:0});
  }
});
test('disabled connection never sends', async()=>{
  const f=fixture({lineUserId:id,lineNotifyEnabled:false});
  assert.equal((await sendOwnerLineMessage(f.args)).skipped,true);
  assert.equal(f.counts().sends,0);
});
test('ordinary LINE ID is rejected without sending',async()=>{
  const f=fixture({lineUserId:'my.line.name'});
  await assert.rejects(sendOwnerLineMessage(f.args),{code:'failed-precondition'});
  assert.equal(f.counts().sends,0);
});
test('provider rejection cannot produce success',async()=>{
  const f=fixture(undefined,false);
  await assert.rejects(sendOwnerLineMessage(f.args),{code:'unavailable'});
});
test('owner delivery succeeds only when provider accepts',async()=>{
  const f=fixture(); assert.deepEqual(await sendOwnerLineMessage(f.args),{success:true});
  assert.equal(f.counts().sends,1);
});
