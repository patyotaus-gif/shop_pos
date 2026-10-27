const assert = require('node:assert/strict');
const {randomUUID} = require('node:crypto');
const {initializeApp, deleteApp} = require('firebase-admin/app');
const {getFirestore, Timestamp} = require('firebase-admin/firestore');
const {initializeTestEnvironment, assertFails} = require('@firebase/rules-unit-testing');
const {doc, getDoc, setDoc} = require('firebase/firestore');
const {readFileSync} = require('node:fs');
(async () => {
  assert.match(process.env.FIRESTORE_EMULATOR_HOST || '', /^(127\.0\.0\.1|localhost):\d+$/);
  const projectId = 'demo-pokpok-admin';
  const app = initializeApp({projectId}, 'owner-unlock'), db = getFirestore(app);
  let time = Date.now(), user = {disabled: false, tokensValidAfterTime: 'original'}, issued = [];
  const uid = 'owner-unlock-' + randomUUID();
  const other = 'other-' + uid, staffId = 'staff1';
  const service = require('./owner_unlock').createOwnerUnlock({db, Timestamp, now: () => time,
    auth: {getUser: async () => user, createCustomToken: async (owner, claims) => {
      issued.push({owner, claims}); return 'test-token';
    }}});
  const data = {deviceId: 'a'.repeat(32), secret: 'b'.repeat(64), pin: '827364'};
  const owner = (payload = data, token = {}) => ({auth: {uid, token: {
    auth_time: Math.floor(time / 1000), firebase: {sign_in_provider: 'password'}, ...token}}, data: payload});
  const staff = (payload = data) => ({auth: {uid: 'staff_employee', token: {
    staffRole: 'cashier', staffShopId: uid, staffId, staffVersion: 0}}, data: payload});
  const denied = e => e.code === 'permission-denied';
  const invalid = e => e.code === 'invalid-argument';
  const device = db.collection('ownerUnlockDevices').doc(uid).collection('devices').doc(data.deviceId);
  let env;
  try {
    await db.collection('shops').doc(uid).set({name: 'Test'});
    await db.collection('shops').doc(uid).collection('staff').doc(staffId).set({active: true, sessionVersion: 0});
    await assert.rejects(service.setup(staff()), denied);
    await assert.rejects(service.setup({data}), e => e.code === 'unauthenticated');
    for (const token of [{auth_time: 0}, {auth_time: Math.floor(time / 1000) + 120},
      {ownerQuickUnlock: true}, {firebase: {sign_in_provider: 'custom'}}]) {
      await assert.rejects(service.setup(owner(data, token)), e => e.code === 'failed-precondition');
    }
    for (const pin of ['1234', 123456, '123456789', 'abcdef']) await assert.rejects(service.setup(owner({...data, pin})), invalid);
    await service.setup(owner());
    const stored = (await device.get()).data();
    assert.equal(stored.pin, undefined); assert.equal(stored.secret, undefined);
    assert.notEqual(stored.pinHash, data.pin); assert.notEqual(stored.secretHash, data.secret);
    assert.equal((await service.unlock(staff())).token, 'test-token');
    assert.deepEqual(issued[0], {owner: uid, claims: {ownerQuickUnlock: true}});
    await service.unlock(owner()); // Persisted owner session, after relaunch.
    await assert.rejects(service.unlock({...owner(), auth: {uid: other, token: {}}}), denied);
    await assert.rejects(service.unlock(staff({...data, secret: 'c'.repeat(64)})), denied);
    await assert.rejects(service.unlock({...staff(), auth: {uid: 'staff_x', token: {}}}), denied);
    await assert.rejects(service.disable(staff()), denied);
    // Five concurrent wrong PINs commit exactly five failures despite retries.
    await Promise.allSettled(Array.from({length: 5}, () => service.unlock(staff({...data, pin: '000000'}))));
    assert.equal((await device.get()).data().failedAttempts, 5);
    await assert.rejects(service.unlock(staff()), e => e.code === 'resource-exhausted');
    time += 15 * 60000 + 1;
    await service.unlock(staff());
    assert.equal((await device.get()).data().failedAttempts, 0);
    await db.collection('shops').doc(uid).collection('staff').doc(staffId).update({active: false});
    await assert.rejects(service.unlock(staff()), denied);
    await db.collection('shops').doc(uid).collection('staff').doc(staffId).update({active: true, sessionVersion: 1});
    await assert.rejects(service.unlock(staff()), denied);
    user = {...user, disabled: true};
    await assert.rejects(service.unlock(owner()), denied);
    user = {...user, disabled: false, multiFactor: {enrolledFactors: [{}]}};
    await assert.rejects(service.setup(owner()), denied);
    await assert.rejects(service.unlock(owner()), denied);
    user = {disabled: false, tokensValidAfterTime: 'password-reset'};
    await assert.rejects(service.unlock(owner()), denied);
    await service.setup(owner());
    await service.unlock(owner());
    time += 90 * 86400000 + 1;
    await assert.rejects(service.unlock(owner()), denied);
    await service.setup(owner());
    await service.disable(owner({deviceId: data.deviceId}));
    await assert.rejects(service.unlock(owner()), denied);
    await service.setup(owner());
    // Binding secrets and hashes must be inaccessible even to owner clients.
    env = await initializeTestEnvironment({projectId, firestore: {
      rules: readFileSync(require('node:path').join(__dirname, '../firestore.rules'), 'utf8')}});
    for (const context of [env.unauthenticatedContext(), env.authenticatedContext(uid), env.authenticatedContext('staff_employee', staff().auth.token)]) {
      const ref = doc(context.firestore(), 'ownerUnlockDevices', uid, 'devices', data.deviceId);
      await assertFails(getDoc(ref)); await assertFails(setDoc(ref, {pinHash: 'fake'}));
    }
    console.log('PASS owner PIN: enrollment, device binding, scope, concurrent lockout, expiry, revocation, MFA and rules');
  } finally {
    if (env) await env.cleanup();
    await db.recursiveDelete(db.collection('ownerUnlockDevices').doc(uid));
    await db.recursiveDelete(db.collection('shops').doc(uid));
    await deleteApp(app);
  }
})().catch(e => {console.error(e); process.exitCode = 1;});
