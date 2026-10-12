'use strict';
const test = require('node:test'), assert = require('node:assert/strict');
const {HttpsError} = require('firebase-functions/v2/https');
const {fixture} = require('./accounting_fixture.cjs');
const {client, handlers, validateCharge, PUBLIC_KEY} = require('./omise_sandbox');
const id = '00000000-0000-4000-8000-000000000001';
const nonce = 'tokn_test_123', instrumentId = 'card_test_123';
const charge = (overrides = {}) => ({object:'charge', id:'chrg_test_123', livemode:false, amount:10000,
  currency:'THB', status:'successful', paid:true, captured:true, card:{id:instrumentId},
  metadata:{pokpokSandboxAttempt:id, actor:'founder'}, ...overrides});
const request = (data = {}, uid = 'founder') => ({auth:{uid, token:{founder:uid === 'founder'}},
  data:{attemptId:id, method:'card', nonce, ...data}});
function setup(apiOverride) {
  const f = fixture({'shops/real':{balance:777}, 'shops/real/sales/existing':{total:777}}), calls = [];
  const api = async (path, body) => {
    calls.push({path,body});
    if (apiOverride) return apiOverride(path,body);
    if (path.startsWith('/tokens/')) return {object:'token', id:nonce, livemode:false, used:false, card:{id:instrumentId}};
    if (path.startsWith('/sources/')) return {object:'source', id:'src_test_123', type:'truemoney', livemode:false, amount:10000, currency:'THB'};
    return charge(body?.source ? {card:null, source:{id:body.source}} : {});
  };
  const h = handlers({...f, api, assertFounder:r => {
    if (!r.auth?.token?.founder) throw new HttpsError('permission-denied','Founder only');
  }});
  return {...f,...h,calls};
}
function response() {
  return {code:200, set(){return this;}, status(code){this.code=code;return this;}, send(body){this.body=body;return this;}, json(body){this.body=body;return this;}};
}
test('only founder can create, read config/status; staff cannot borrow a founder claim', async () => {
  const h=setup();
  for (const fn of [h.create,h.config,h.status]) await assert.rejects(fn(request({},'shop')), {code:'permission-denied'});
  const staff=request(); staff.auth.token.staffRole='cashier';
  await assert.rejects(h.create(staff), {code:'permission-denied'});
  assert.equal(h.calls.length,0);
});
test('concurrent requests and replay create one charge, fixed server amount, isolated writes', async () => {
  const h=setup();
  const results=await Promise.all([h.create(request({amount:1})), h.create(request({amount:999999}))]);
  assert(results.some(r=>r.status==='successful'));
  assert.equal(h.calls.filter(c=>c.body).length,1);
  const form=h.calls.find(c=>c.body).body;
  assert.equal(form.amount,'10000'); assert.equal(form.currency,'THB');
  assert.match(form.return_uri,/payment-test\/\?attempt=/);
  assert.equal((await h.create(request())).status,'successful');
  assert.equal(h.calls.filter(c=>c.body).length,1);
  assert.deepEqual(h.docs.get('shops/real'),{balance:777});
  assert.deepEqual(h.docs.get('shops/real/sales/existing'),{total:777});
  assert([...h.docs.keys()].every(k=>k.startsWith('omiseSandboxAttempts/') || ['shops/real','shops/real/sales/existing'].includes(k)));
});
test('TrueMoney uses validated source and stores no customer phone/card details', async () => {
  const h=setup(); const r=await h.create(request({method:'truemoney',nonce:'src_test_123'}));
  assert.equal(r.status,'successful');
  assert.equal(h.calls.find(c=>c.body).body.source,'src_test_123');
  const saved=h.docs.get(`omiseSandboxAttempts/${id}`);
  assert.equal(saved.instrumentId,'src_test_123'); assert.equal(saved.phone,undefined); assert.equal(saved.card,undefined);
});
test('live and malformed nonces are rejected before provider call', async () => {
  const h=setup();
  for (const data of [{nonce:'tokn_live_123'},{method:'stripe'},{attemptId:'../sales'},{nonce:'src_test_123'}]) {
    await assert.rejects(h.create(request(data)),{code:'invalid-argument'});
  }
  assert.equal(h.calls.length,0);
});
test('source amount, currency, provider mode/type and spent token are rejected before charge', async () => {
  for (const invalid of [{amount:1},{currency:'USD'},{livemode:true},{type:'promptpay'}]) {
    const h=setup(async () => ({object:'source', id:'src_test_123', type:'truemoney',livemode:false, amount:10000,currency:'THB',...invalid}));
    await assert.rejects(h.create(request({method:'truemoney',nonce:'src_test_123'})),{code:'failed-precondition'});
    assert.equal(h.calls.filter(c=>c.body).length,0);
  }
  const h=setup(async()=>({object:'token',id:nonce,livemode:false,used:true,card:{id:instrumentId}}));
  await assert.rejects(h.create(request()),{code:'failed-precondition'});
});
test('uncertain POST is not retried; authenticated status can recover exact matching charge', async () => {
  const h=setup(async (path,body) => {
    if(path.startsWith('/tokens')) return {object:'token',id:nonce,livemode:false,used:false,card:{id:instrumentId}};
    if(body) throw new HttpsError('unavailable','timeout');
    return charge();
  });
  await assert.rejects(h.create(request()),{code:'unavailable'});
  assert.equal((await h.create(request())).status,'unknown');
  assert.equal(h.calls.filter(c=>c.body).length,1);
  assert.equal((await h.status(request({chargeId:'chrg_test_123'}))).status,'successful');
});
test('nonce changes and other founders cannot take over an existing attempt', async () => {
  const h=setup();await h.create(request());
  await assert.rejects(h.create(request({nonce:'tokn_test_456'})),{code:'already-exists'});
  const other=request();other.auth.uid='other';
  await assert.rejects(h.create(other),{code:'already-exists'});
  await assert.rejects(h.status(other),{code:'not-found'});
});
test('provider response must match test mode, amount, currency, actor, instrument and charge', () => {
  const attempt={actor:'founder',method:'card',instrumentId,chargeId:'chrg_test_123'};
  for (const overrides of [{livemode:true},{amount:1},{currency:'USD'},{id:'chrg_test_456'},
    {metadata:{pokpokSandboxAttempt:id,actor:'other'}},{metadata:{pokpokSandboxAttempt:'wrong',actor:'founder'}},
    {card:{id:'card_test_other'}}]) assert.throws(()=>validateCharge(charge(overrides),attempt,id));
  assert.equal(validateCharge(charge({paid:false}),attempt,id).status,'pending');
  assert.equal(validateCharge(charge({captured:false}),attempt,id).status,'pending');
  assert.equal(validateCharge(charge({refunded_amount:1}),attempt,id).status,'refunded');
});
test('redirects reject non-HTTPS, credentials and lookalike domains', () => {
  for (const url of ['http://api.omise.co/a','https://omise.co.evil.test/a','https://evil.test/a','https://user@api.omise.co/a']) {
    assert.throws(()=>validateCharge(charge({status:'pending',authorize_uri:url}),{actor:'founder',method:'card',instrumentId},id));
  }
});
test('webhook verifies provider GET; forged posted success cannot mark payment successful', async () => {
  const h=setup(async path=>path.startsWith('/tokens') ? {object:'token',id:nonce,livemode:false,used:false,card:{id:instrumentId}}
    : charge({status:'pending',paid:false,captured:false}));
  await h.create(request());
  const res=response();
  await h.webhook({method:'POST',query:{attempt:id},body:{data:{id:'chrg_test_123',status:'successful',paid:true}}},res);
  assert.equal(res.code,200);
  assert.equal(h.docs.get(`omiseSandboxAttempts/${id}`).status,'pending');
  assert.equal(h.calls.at(-1).path,'/charges/chrg_test_123');
});
test('delayed pending response does not undo verified success', async () => {
  let pending=false;
  const h=setup(async path=>path.startsWith('/tokens') ? {object:'token',id:nonce,livemode:false,used:false,card:{id:instrumentId}}
    : charge(pending ? {status:'pending',paid:false} : {}));
  await h.create(request());pending=true;
  assert.equal((await h.status(request())).status,'successful');
});
test('client uses public key on vault for tokens and never sends a live key', async () => {
  const calls=[];
  const api=client({secret:()=> 'skey_test_fixture',fetchImpl:async(url,opts)=>{
    calls.push({url,opts});return {ok:true,json:async()=>({})};
  }});
  await api('/tokens/tokn_test_123');await api('/charges/chrg_test_123');
  assert.match(calls[0].url,/^https:\/\/vault.omise.co/);
  assert.equal(calls[0].opts.headers.Authorization,`Basic ${Buffer.from(`${PUBLIC_KEY}:`).toString('base64')}`);
  assert.match(calls[1].url,/^https:\/\/api.omise.co/);
  const live=client({secret:()=> 'skey_live_fixture',fetchImpl:()=>assert.fail('live request')});
  await assert.rejects(live('/charges',{}),{code:'failed-precondition'});
  await assert.rejects(api('/../balance'),{code:'invalid-argument'});
});
test('client sanitizes provider errors; 5xx and timeout stay uncertain', async () => {
  for (const status of [400,401,408,429,500]) {
    const api=client({secret:()=> 'skey_test_fixture',fetchImpl:async()=>({ok:false,status,json:async()=>({message:'private payload'})})});
    await assert.rejects(api('/charges',{}), e=>!e.message.includes('private') && e.code===(status>=500||[408,429].includes(status)?'unavailable':'failed-precondition'));
  }
});
