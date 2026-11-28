const assert = require('node:assert/strict');
const {readFileSync} = require('node:fs');
const {join} = require('node:path');
const {randomUUID} = require('node:crypto');
const {initializeTestEnvironment, assertFails} = require('@firebase/rules-unit-testing');
const {doc, getDoc, setDoc} = require('firebase/firestore');
const {getFirestore, Timestamp} = require('firebase-admin/firestore');
const {deleteApp, getApp} = require('firebase-admin/app');

(async () => {
  assert.match(process.env.FIRESTORE_EMULATOR_HOST || '', /^127\.0\.0\.1:\d+$/);
  const projectId = 'demo-pokpok-admin';
  process.env.GCLOUD_PROJECT = projectId;
  const env = await initializeTestEnvironment({projectId, firestore: {
    rules:readFileSync(join(__dirname, '../firestore.rules'), 'utf8')}});
  const {merchantBranchRequests, adminBranchRequests} = require('./index');
  const db = getFirestore(), uid = randomUUID(), foreign = randomUUID();
  const owner = (data, id = uid, token = {}) => merchantBranchRequests.run({
    auth: {uid:id, token:{email_verified:true, ...token}}, data: {shopId:uid, ...data}});
  const admin = data => adminBranchRequests.run({auth:{uid:'reviewer',token:{email_verified:true,founder:true}}, data});
  try {
    const shop = db.doc('shops/' + uid);
    const end = Timestamp.fromMillis(Date.now() + 12 * 86400000);
    const original = {name:'Demo shop', email:'owner@example.test', subscriptionStatus:'trial', locations:1, trialEndsAt:end};
    await shop.set(original);
    const input = {action:'submit', revision:0, name:'สาขากลาง', address:'ที่ตั้งทดสอบ', note:''};
    await assert.rejects(owner(input), {code:'permission-denied'});
    for (const id of [uid, foreign]) await db.doc('merchantTrialContacts/' + id).set({verifiedAt:Timestamp.now()});
    await assert.rejects(owner(input,foreign), {code:'permission-denied'});
    await assert.rejects(owner(input,'staff_test',{staffRole:'cashier',staffShopId:uid,staffId:'test'}), {code:'permission-denied'});
    await assert.rejects(owner({...input,address:' '}), {code:'invalid-argument'});
    const list = () => owner({action:'list'});
    assert.equal((await list()).endsAtMs, end.toMillis());
    const [a,b] = await Promise.all([owner(input), owner(input)]);
    assert.equal(a.id,b.id);
    assert.equal((await list()).items.length,1);
    const other = env.authenticatedContext(foreign,{email_verified:true}).firestore();
    await assertFails(getDoc(doc(other,'branchRequests',a.id)));
    await assertFails(setDoc(doc(other,'shops',uid,'branches',a.id),{name:'other'}));
    const decision = {id:a.id, revision:1, action:'moreInfo', reason:'ขอเลขที่ตั้งสาขา'};
    await assert.rejects(adminBranchRequests.run({auth:{uid,token:{email_verified:true}},data:decision}), {code:'permission-denied'});
    const queued = (await admin({action:'list'})).items.find(item=>item.id === a.id);
    assert.deepEqual(queued.termsAtSubmission,{planStatus:'trial', endsAtMs:end.toMillis()});
    await admin(decision);
    const revised = {...input, revision:1, address:'เลขที่ 12 ตำบลทดสอบ'};
    await owner(revised);
    await owner(revised);
    assert.equal((await list()).items[0].previousReason,decision.reason);
    await assert.rejects(admin({...decision, action:'approved'}), {code:'failed-precondition'});
    await admin({...decision,revision:2,action:'declined',reason:'กรุณายืนยันข้อมูลกิจการ'});
    await owner({...revised,revision:2,note:'ส่งข้อมูลเพื่อขอทบทวน'});
    const accepted = {...decision,revision:3,action:'approved',reason:'ตรวจสอบเจ้าของและที่ตั้งแล้ว'};
    await Promise.all([admin(accepted), admin(accepted)]);
    await assert.rejects(adminBranchRequests.run({
      auth:{uid:'second-reviewer',token:{email_verified:true,founder:true}},data:accepted
    }), {code:'failed-precondition'});
    assert.equal((await list()).items[0].status,'approved');
    assert.equal((await shop.collection('branches').get()).size,1);
    assert.deepEqual((await shop.get()).data(),original);
    assert.equal((await list()).endsAtMs,end.toMillis());
    assert.equal((await db.doc('merchantTrialOwners/'+uid).get()).exists,false);
    assert.equal((await db.doc('branchRequests/'+a.id).collection('events').get()).size,6);
    assert.ok(!(await admin({action:'list'})).items.some(item=>item.id === a.id));
    console.log('PASS branch owner, duplicate submission, founder review, resubmission, audit and shared expiry');
  } finally {
    await env.cleanup();
    await deleteApp(getApp());
  }
})().catch(error => {console.error(error);process.exitCode=1;});
