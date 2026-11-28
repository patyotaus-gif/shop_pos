// Exercise the exported callable using only localhost Firebase test services.
const assert = require('node:assert/strict');
const {randomUUID, createHash} = require('node:crypto');
const {once} = require('node:events');
const express = require('express');
const {getApp, deleteApp} = require('firebase-admin/app');
const {getFirestore} = require('firebase-admin/firestore');
const {getAuth} = require('firebase-admin/auth');

(async () => {
  for (const key of ['FIRESTORE_EMULATOR_HOST', 'FIREBASE_AUTH_EMULATOR_HOST']) {
    assert.match(process.env[key] || '', /^(127\.0\.0\.1|localhost):\d+$/);
  }
  const project = 'demo-pokpok-admin';
  assert.equal(process.env.GCLOUD_PROJECT, project);
  const api = require('./index');
  const auth = getAuth(), db = getFirestore(), app = express();
  app.use(express.json());
  app.post('/branch', api.merchantBranchRequests);
  app.post('/status', api.getMerchantPhoneStatus);
  app.post('/verify', api.verifyMerchantPhone);

  const server = app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const base = 'http://' + process.env.FIREBASE_AUTH_EMULATOR_HOST;
  const phone = '+12025550147', users = [], numbers = new Set();
  const phoneRef = number => db.doc('merchantTrialPhones/' + createHash('sha256').update(number).digest('hex'));
  async function accounts(method, data) {
    const r = await fetch(base + '/identitytoolkit.googleapis.com/v1/accounts:' + method + '?key=demo', {
      method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(data),
    });
    const body = await r.json();
    assert.equal(r.status, 200, method + ': ' + (body.error?.message || 'unknown error'));
    return body;
  }
  async function newAccount() {
    const credentials = {email:randomUUID() + '@example.test', password:randomUUID(), returnSecureToken:true};
    const {localId, idToken} = await accounts('signUp', credentials);
    users.push(localId);
    await auth.updateUser(localId, {emailVerified:true});
    const signIn = async () => (await accounts('signInWithPassword', credentials)).idToken;
    return {uid:localId, email:credentials.email, unverified:idToken, signIn,
      token:await signIn()};
  }
  async function smsIdentity(number = phone) {
    numbers.add(number);
    const {sessionInfo} = await accounts('sendVerificationCode', {phoneNumber:number});
    const r = await fetch(base + '/emulator/v1/projects/' + project + '/verificationCodes');
    const entries = (await r.json()).verificationCodes;
    const verification = entries.find(e => e.sessionInfo === sessionInfo);
    assert.ok(verification, 'SMS code available in the local emulator inbox');
    const account = await accounts('signInWithPhoneNumber', {sessionInfo, code:verification.code});
    if (!users.includes(account.localId)) users.push(account.localId);
    return account;
  }
  async function call(route, token, data) {
    const response = await fetch('http://127.0.0.1:' + server.address().port + route, {
      method: 'POST', headers: {'Content-Type':'application/json', Authorization:'Bearer ' + token},
      body: JSON.stringify({data}),
    });
    return {status: response.status, body: await response.json()};
  }
  try {
    const owner = await newAccount(), shop = db.doc('shops/' + owner.uid);
    await shop.set({name:'Branch OTP test',subscriptionStatus:'active',locations:1});
    const identity = {ownerUid: owner.uid}, list = {shopId:owner.uid, action:'list'};
    assert.equal((await call('/status',owner.token,{})).body.result.state,'required');
    assert.equal((await call('/branch',owner.token,list)).status,403);
    assert.equal((await call('/verify',owner.token,identity)).body.error.details.reason,'phone-proof-required');
    const {idToken} = await smsIdentity();
    assert.equal((await call('/verify',owner.token,{...identity,phoneProof:idToken})).body.result.verified,true);
    assert.equal((await call('/status',owner.token,{})).body.result.state,'verified');
    assert.equal((await call('/branch',owner.token,list)).status,200);
    assert.equal((await auth.getUser(owner.uid)).phoneNumber,undefined);
    assert.deepEqual((await shop.get()).data(),{name:'Branch OTP test',subscriptionStatus:'active',locations:1});
    console.log('PASS existing owner enrolls via isolated SMS identity; original sign-in and shop preserved; branch becomes accessible.');
  } finally {
    for (const uid of users) {
      await db.doc('shops/' + uid).delete();
      await db.doc('merchantTrialOwners/' + uid).delete();
      await db.doc('merchantTrialContacts/' + uid).delete();
      await auth.deleteUser(uid);
    }
    for (const number of numbers) await phoneRef(number).delete();
    await new Promise(resolve => server.close(resolve));
    await deleteApp(getApp());
  }
})().catch(e => { console.error(e); process.exitCode = 1; });
