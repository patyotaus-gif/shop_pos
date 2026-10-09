const assert = require('node:assert/strict');
const admin = require('firebase-admin');
const { initializeTestEnvironment, assertFails } = require('@firebase/rules-unit-testing');
const { doc, getDoc, setDoc } = require('firebase/firestore');
const { HttpsError } = require('firebase-functions/v2/https');
const fs = require('node:fs'), path = require('node:path');
(async () => {
  assert.match(process.env.FIRESTORE_EMULATOR_HOST || '', /^(localhost|127\.0\.0\.1):\d+$/);
  const projectId = 'demo-pokpok-admin';
  const env = await initializeTestEnvironment({projectId, firestore: {rules: fs.readFileSync(path.join(__dirname, '../firestore.rules'),'utf8')}});
  const app = admin.initializeApp({projectId}, 'line-link-test'), db = app.firestore();
  const shopId = 'line-owner';
  const request = {auth:{uid:shopId,token:{}},data:{shopId}};
  const api = require('./line_link').handlers({db,HttpsError});
  try {
    await db.doc('shops/'+shopId).set({name:'Test shop'});
    const started = await api.start(request);
    for (const ctx of [env.unauthenticatedContext(), env.authenticatedContext(shopId), env.authenticatedContext('other'), env.authenticatedContext('staff',{staffRole:'cashier',staffShopId:shopId})]) {
      const ref = doc(ctx.firestore(),'lineLinkChallenges/'+shopId);
      await assertFails(getDoc(ref));
      await assertFails(setDoc(ref,{tokenHash:'forged',expiresAt:Date.now()+10000}));
    }
    const text = decodeURIComponent(started.url.split('/?')[1]);
    const results = await Promise.all(['a','b'].map(c => api.consume({text,userId:'U'+c.repeat(32),sourceType:'user'})));
    assert.equal(results.filter(Boolean).length,1);
    const linked = (await db.doc('shops/'+shopId+'/settings/shop').get()).data();
    assert.match(linked.lineUserId,/^U[ab]{32}$/);
    assert.equal(linked.lineNotifyEnabled,true);
    assert.equal((await api.status(request)).status,'connected');
    console.log('PASS LINE linking: server-only challenges, owner authorization, atomic single-use recipient binding');
  } finally { await env.cleanup(); await app.delete(); }
})().catch(error => { console.error(error); process.exitCode=1; });
