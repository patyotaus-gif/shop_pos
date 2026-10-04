'use strict';
const test=require('node:test'), assert=require('node:assert/strict');
const {Jimp}=require('jimp');
const {createSlipUpload,decodeSlip,MAX_BYTES}=require('./slip_upload');
const imagePromise=new Jimp({width:8,height:8,color:0xffffffff}).getBuffer('image/jpeg');
async function image(){return 'data:image/jpeg;base64,'+(await imagePromise).toString('base64');}
function fixture({status='pendingPayment',exists=true,appCheck=true,saveError=false,race=false,txError=false,lostResponse=false}={}) {
  let data={status,total:75,finalAmount:75.91};
  const saves=[],updates=[],deletes=[],logs=[];
  const snap=()=>({exists,data:()=>({...data})});
  const ref={get:async()=>snap()};
  const db={collection:()=>({doc:()=>({collection:()=>({doc:()=>ref})})}),
    runTransaction:async fn=>{if(txError)throw Error('private provider detail');const result=await fn({get:async()=>snap(),update:(_,patch)=>{updates.push(patch);data={...data,...patch};}});if(lostResponse)throw Error('response lost');return result;}};
  const bucket={name:'fixture-bucket',file:name=>({name,save:async(bytes,options)=>{
    if(saveError)throw Error('private provider detail');saves.push({bytes,options,name});if(race)data.status='paid';
  },delete:async()=>deletes.push(name)})};
  const handler=createSlipUpload({db,getBucket:()=>bucket,FieldValue:{serverTimestamp:()=>1234},
    verifyAppCheck:async(_,res)=>{if(!appCheck)res.status(401).json({error:'unauthorized'});return appCheck;},logger:{error:(...args)=>logs.push(args)}});
  const call=async(body,method='POST')=>{
    const res={statusCode:200,headers:{},set(k,v){this.headers[k]=v;return this;},status(n){this.statusCode=n;return this;},json(x){this.body=x;return this;},send(x){this.body=x;return this;}};
    await handler({method,body},res);return res;
  };
  return {call,saves,updates,deletes,logs,data:()=>data};
}
const body=async()=>({shopId:'fixture-shop',orderId:'fixture-order',slipBase64:await image()});

test('installed Jimp decodes a valid browser JPEG',async()=>{
  assert.equal(typeof require('jimp').read,'undefined');
  assert.ok((await decodeSlip(await image())).length>0);
});
test('accepts a slip without a readable QR as evidence, never marks paid',async()=>{
  const f=fixture(),res=await f.call(await body());
  assert.deepEqual(res.body,{success:true,awaitingReview:true});
  assert.equal(f.data().status,'pendingPayment');assert.equal(f.data().paidAt,undefined);
  assert.equal(f.data().slipReviewStatus,'awaitingOwner');assert.equal(f.saves.length,1);
  const saved=f.saves[0],url=new URL(f.data().slipUrl);
  assert.equal(url.searchParams.get('token'),saved.options.metadata.metadata.firebaseStorageDownloadTokens);
  assert.ok(decodeURIComponent(url.pathname).endsWith(saved.name));
  assert.deepEqual(Object.keys(f.updates[0]).sort(),['slipReviewStatus','slipSubmittedAt','slipUrl']);
});
test('invalid App Check is rejected before saving any image',async()=>{
  const f=fixture({appCheck:false});assert.equal((await f.call(await body())).statusCode,401);assert.equal(f.saves.length,0);
});
test('invalid document path rejected',async()=>{
  const f=fixture();assert.equal((await f.call({...await body(),shopId:'../shop'})).statusCode,400);assert.equal(f.saves.length,0);
});
test('oversized input returns a size error',async()=>{
  const f=fixture(),res=await f.call({...await body(),slipBase64:'A'.repeat(Math.ceil(MAX_BYTES/3)*4+101)});
  assert.equal(res.statusCode,413);assert.equal(res.body.error,'image_too_large');assert.equal(f.saves.length,0);
});
test('corrupt JPEG and non-images rejected with readable error',async()=>{
  for(const slipBase64 of ['@@@','data:image/jpeg;base64,/9gAAAA=',null]){
    const f=fixture(),res=await f.call({...await body(),slipBase64});assert.equal(res.statusCode,400);assert.equal(f.saves.length,0);
  }
});
test('missing and already processed orders cannot upload',async()=>{
  for(const [options,code] of [[{exists:false},404],[{status:'paid'},409],[{status:'cancelled'},409]]){
    const f=fixture(options);assert.equal((await f.call(await body())).statusCode,code);assert.equal(f.saves.length,0);
  }
});
test('confirmation racing with upload leaves paid evidence untouched',async()=>{
  const f=fixture({race:true}),res=await f.call(await body());assert.equal(res.statusCode,409);
  assert.equal(f.data().status,'paid');assert.equal(f.updates.length,0);assert.equal(f.deletes.length,1);
});
test('storage and database failures do not report success or leak provider details',async()=>{
  for(const options of [{saveError:true},{txError:true}]){
    const f=fixture(options),res=await f.call(await body());assert.equal(res.statusCode,503);
    assert.equal(f.data().status,'pendingPayment');assert.ok(!JSON.stringify(res.body).includes('private provider'));
    assert.equal(f.deletes.length,0);assert.equal(f.logs.length,1);
  }
});
test('retry uses a separate object, preserving previous evidence',async()=>{
  const f=fixture();await f.call(await body());const first=f.data().slipUrl;await f.call(await body());
  assert.notEqual(f.data().slipUrl,first);assert.notEqual(f.saves[0].name,f.saves[1].name);assert.equal(f.data().status,'pendingPayment');
});
test('ambiguous database response preserves possibly attached evidence',async()=>{
  const f=fixture({lostResponse:true}),res=await f.call(await body());
  assert.equal(res.statusCode,503);assert.ok(f.data().slipUrl);assert.equal(f.deletes.length,0);
  assert.equal(f.data().status,'pendingPayment');
});
test('GET and preflight never process an upload',async()=>{
  const f=fixture();assert.equal((await f.call({},'GET')).statusCode,405);assert.equal((await f.call({},'OPTIONS')).statusCode,204);assert.equal(f.saves.length,0);
});
