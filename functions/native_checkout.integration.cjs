// Real callable HTTP middleware + Auth/Firestore emulators. Never production.
const assert = require('node:assert/strict');
const {randomUUID} = require('node:crypto');
const {once} = require('node:events');
const express = require('express');
const {getApp, deleteApp} = require('firebase-admin/app');
const {getAuth} = require('firebase-admin/auth');
const {getFirestore} = require('firebase-admin/firestore');

(async () => {
  for (const key of ['FIRESTORE_EMULATOR_HOST', 'FIREBASE_AUTH_EMULATOR_HOST']) {
    assert.match(process.env[key] || '', /^(localhost|127\.0\.0\.1):\d+$/);
  }
  assert.equal(process.env.GCLOUD_PROJECT, 'demo-pokpok-admin');
  const api = require('./index');
  const names = ['quoteCounterGifts', 'counterBundleCatalog', 'tablePromotions'];
  const management = ['manageCoupon', 'manageBuyGet', 'manageBundle'];
  const app = express();
  app.use(express.json());
  for (const name of [...names, ...management]) app.post('/' + name, api[name]);
  const server = app.listen(0, '127.0.0.1');
  await once(server, 'listening');
  const url = `http://127.0.0.1:${server.address().port}`;
  const db = getFirestore(), auth = getAuth();
  const shopId = 'checkout-' + randomUUID(), staffId = 'cashier';
  const staffUid = 'staff_' + randomUUID(), otherUid = 'other-' + randomUUID();
  const shop = db.doc('shops/' + shopId), other = db.doc('shops/' + otherUid);
  async function token(uid, claims = {}) {
    const customToken = await auth.createCustomToken(uid, claims);
    const r = await fetch(`http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=demo`, {
      method: 'POST', headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({token: customToken, returnSecureToken: true}),
    });
    const body = await r.json();
    assert.ok(body.idToken, 'emulator sign-in must succeed');
    return body.idToken;
  }
  async function call(name, idToken, data = {}, appToken) {
    const response = await fetch(url + '/' + name, {
      method: 'POST', headers: {'Content-Type': 'application/json',
        ...(idToken ? {Authorization: 'Bearer ' + idToken} : {}),
        ...(appToken ? {'X-Firebase-AppCheck': appToken} : {})},
      body: JSON.stringify({data}),
    });
    return {status: response.status, body: await response.json()};
  }
  const data = name => name === 'tablePromotions'
    ? {shopId, orderId: 'table', action: 'preview'}
    : {items: [{productId: 'tea', quantity: 1}]};
  try {
    // Exercise Firebase's actual verification link in the Auth emulator, with
    // the same owner both before and after verification. Nothing leaves localhost.
    const authRoot = 'http://' + process.env.FIREBASE_AUTH_EMULATOR_HOST;
    const accounts = async (method, payload) => {
      const response = await fetch(authRoot + '/identitytoolkit.googleapis.com/v1/accounts:' + method + '?key=demo', {
        method:'POST', headers:{'Content-Type':'application/json'}, body:JSON.stringify(payload)});
      assert.equal(response.status, 200, method);
      return response.json();
    };
    const credentials = {email:'verify-' + randomUUID() + '@example.test', password:randomUUID(), returnSecureToken:true};
    const pending = await accounts('signUp', credentials);
    for (const record of [pending, await accounts('signInWithPassword', credentials)]) {
      const result = await call('quoteCounterGifts', record.idToken, {items:[]});
      assert.equal(result.status, 403);
      assert.match(result.body.error.message, /ยืนยันอีเมล/);
    }
    await accounts('sendOobCode', {requestType:'VERIFY_EMAIL', idToken:pending.idToken});
    const inboxResponse = await fetch(authRoot + '/emulator/v1/projects/demo-pokpok-admin/oobCodes');
    const inbox = await inboxResponse.json();
    const verification = inbox.oobCodes.find(entry => entry.email === credentials.email && entry.requestType === 'VERIFY_EMAIL');
    assert.ok(verification);
    await accounts('update', {oobCode:verification.oobCode});
    const verified = await accounts('signInWithPassword', credentials);
    await db.doc('shops/' + pending.localId).set({name:'Verification test'});
    const verifiedResult = await call('quoteCounterGifts', verified.idToken, {items:[{productId:'tea',quantity:1}]});
    assert.equal(verifiedResult.status, 200, JSON.stringify(verifiedResult.body));
    await db.doc('shops/' + pending.localId).delete();
    await auth.deleteUser(pending.localId);
    console.log('PASS new and returning unverified password accounts, local verification email and link, verified callable access');
    await shop.set({tier: 'full', subscriptionStatus: 'active',
      subscriptionEndsAt: new Date(Date.now() + 86400000)});
    await other.set({name: 'another shop'});
    await shop.collection('staff').doc(staffId).set({active: true, sessionVersion: 1, permissions: {}});
    await shop.collection('products').doc('tea').set({name: 'Tea', price: 20, stock: 10});
    await shop.collection('tables').doc('t').set({status: 'occupied', currentOrderId: 'table'});
    await shop.collection('tableOrders').doc('table').set({tableId: 't', status: 'open', items: [
      {id: 'line', productId: 'tea', productName: 'Tea', quantity: 1, price: 20, kitchenStatus: 'pending'},
    ]});
    await auth.createUser({uid: shopId, email: shopId + '@example.test', emailVerified: true});
    await auth.createUser({uid: otherUid, email: otherUid + '@example.test', emailVerified: true});
    const ownerToken = await token(shopId, {ownerQuickUnlock: true});
    const staffToken = await token(staffUid, {staffRole: 'cashier', staffShopId: shopId, staffId, staffVersion: 1});
    const otherToken = await token(otherUid);
    for (const name of names) {
      for (const idToken of [ownerToken, staffToken]) {
        for (const appToken of [undefined, 'invalid-app-attestation']) {
          const r = await call(name, idToken, data(name), appToken);
          assert.equal(r.status, 200, name + ': valid scoped user must reach checkout');
          assert.ok(r.body.result);
        }
      }
      for (const idToken of [undefined, 'invalid-auth-token']) {
        assert.notEqual((await call(name, idToken, data(name))).status, 200, name + ': authentication still required');
      }
    }
    assert.equal((await call('tablePromotions', otherToken, data('tablePromotions'))).status, 403);
    assert.equal((await call('tablePromotions', staffToken,
      {...data('tablePromotions'), action: 'apply', couponCode: 'TEST'})).status, 403);
    // Counter pricing derives the shop from auth, ignoring a forged target shop.
    await shop.collection('buyGetPromotions').doc('tea').set({active: true, revision: 'gift',
      endsAt: new Date(Date.now() + 86400000), buyQuantity: 1, giftQuantity: 1,
      maxSets: 1, giftProductId: 'tea'});
    const own = await call('quoteCounterGifts', ownerToken, data('quoteCounterGifts'));
    assert.equal(own.body.result.buyGet.length, 1);
    const foreign = await call('quoteCounterGifts', otherToken,
      {...data('quoteCounterGifts'), shopId});
    assert.equal(foreign.status, 200);
    assert.deepEqual(foreign.body.result.buyGet, [], 'cannot quote another shop promotion');
    // Owner journey: create promotions, then turn them off from the native app.
    await shop.collection('products').doc('cake').set({name: 'Cake', price: 30, stock: 10});
    const endsAt = Date.now() + 86400000;
    const actions = {
      manageCoupon: {action: 'create', code: 'AUDIT', kind: 'fixed', value: 100,
        minSubtotalMinor: 3000, maxUses: 5, endsAt},
      manageBuyGet: {action: 'save', buyProductId: 'tea', giftProductId: 'cake',
        buyQuantity: 2, giftQuantity: 1, maxSets: 1, endsAt},
      manageBundle: {action: 'save', id: 'audit-set', name: 'Tea and cake',
        components: [{productId: 'tea', quantity: 1}, {productId: 'cake', quantity: 1}],
        priceMinor: 4000, maxSets: 1, endsAt},
    };
    for (const name of management) {
      const payload = {shopId, ...actions[name]};
      const r = await call(name, ownerToken, payload, 'invalid-app-attestation');
      assert.equal(r.status, 200, name + ': owner can create a promotion');
      assert.equal(r.body.result.success, true);
      const toggle = {...payload, action: 'toggle', active: false};
      assert.equal((await call(name, ownerToken, toggle)).status, 200);
      for (const idToken of [undefined, 'invalid-auth-token', staffToken, otherToken]) {
        assert.notEqual((await call(name, idToken, {...toggle, active: true})).status,
          200, name + ': only the owning account can manage promotions');
      }
    }
    assert.equal((await shop.collection('coupons').doc('AUDIT').get()).data().active, false);
    assert.equal((await shop.collection('buyGetPromotions').doc('tea').get()).data().active, false);
    assert.equal((await shop.collection('promotionSettings').doc('bundles').get()).data().bundles[0].active, false);
    console.log('PASS owner promotion create/toggle: coupons, buy-get, bundles; staff/other shop/invalid Auth denied');
    await shop.collection('staff').doc(staffId).update({sessionVersion: 2});
    for (const name of names) {
      assert.equal((await call(name, staffToken, data(name))).status, 403, name + ': revoked staff blocked');
    }
    await shop.collection('staff').doc(staffId).update({sessionVersion: 1, active: false});
    for (const name of names) {
      assert.equal((await call(name, staffToken, data(name))).status, 403, name + ': disabled staff blocked');
    }
    console.log('PASS native checkout HTTP: owner PIN/staff, missing/invalid App Check; invalid Auth, cross-shop, discount grants, revoked/disabled staff denied');
  } finally {
    await db.recursiveDelete(shop);
    await db.recursiveDelete(other);
    for (const uid of [shopId, staffUid, otherUid]) await auth.deleteUser(uid).catch(() => {});
    await new Promise(resolve => server.close(resolve));
    await deleteApp(getApp());
  }
})().catch(e => { console.error(e); process.exitCode = 1; });
