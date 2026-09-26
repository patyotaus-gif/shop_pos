// Run against the Firestore emulator only; never production.
const { initializeTestEnvironment, assertFails, assertSucceeds } = require('@firebase/rules-unit-testing');
const { doc, setDoc, updateDoc, deleteDoc, Timestamp } = require('firebase/firestore');
const fs = require('node:fs');
(async () => {
  if (!process.env.FIRESTORE_EMULATOR_HOST) throw Error('Firestore emulator required');
  const env = await initializeTestEnvironment({ projectId: 'demo-pokpok-admin', firestore: { rules: fs.readFileSync(require('node:path').join(__dirname, '..', 'firestore.rules'), 'utf8') } });
  try {
    const owner = env.authenticatedContext('owner').firestore();
    const other = env.authenticatedContext('other').firestore();
    const anonymous = env.unauthenticatedContext().firestore();
    const data = { name: 'Shop', email: 'owner@example.com', tier: 'full', shopType: 'retail', plan: 'monthly', locations: 1,
      subscriptionStatus: 'trial', subscriptionEndsAt: null, createdAt: Timestamp.now(),
      trialEndsAt: Timestamp.fromMillis(Date.now() + 60 * 86400000) };
    await assertSucceeds(setDoc(doc(owner, 'shops/owner'), data));
    for (const shopType of ['retail', 'restaurant']) {
      for (const tier of ['solo', 'lite', 'full']) {
        const id = `${shopType}-${tier}`;
        await assertSucceeds(setDoc(doc(env.authenticatedContext(id).firestore(), `shops/${id}`), {...data, shopType, tier}));
      }
    }
    await assertFails(setDoc(doc(other, 'shops/other'), {...data, shopType:'unknown'}));
    await assertSucceeds(updateDoc(doc(owner, 'shops/owner'), { name: 'Renamed', fcmToken: 'test' }));
    for (const change of [{ tier: 'restaurant' }, { plan: 'yearly' }, { locations: 5 }, { shopType: 'restaurant' },
      { subscriptionStatus: 'active' }, { trialEndsAt: Timestamp.fromMillis(Date.now() + 90 * 86400000) },
      { subscriptionEndsAt: Timestamp.now() }, { createdAt: Timestamp.now() }]) {
      await assertFails(updateDoc(doc(owner, 'shops/owner'), change));
    }
    await assertFails(deleteDoc(doc(owner, 'shops/owner')));
    await assertFails(updateDoc(doc(other, 'shops/owner'), { tier: 'solo' }));
    await assertFails(updateDoc(doc(anonymous, 'shops/owner'), { name: 'Anonymous' }));
    await assertFails(setDoc(doc(other, 'shops/other'), { ...data, subscriptionStatus: 'active' }));
    await assertFails(setDoc(doc(other, 'shops/other'), { ...data, trialEndsAt: Timestamp.fromMillis(Date.now() + 90 * 86400000) }));
    await assertFails(setDoc(doc(owner, 'shops/owner/planChanges/forged'), { actor: 'admin' }));
    await assertFails(setDoc(doc(owner, 'shops/owner/offlinePermits/forged'), { expiresAt: Timestamp.fromMillis(Date.now()+86400000) }));
    const cashier = env.authenticatedContext('staff_test_uid', {staffRole:'cashier',staffShopId:'owner',staffId:'cashier',staffVersion:1}).firestore();
    for (const path of ['shops/owner','shops/owner/settings/shop','shops/owner/products/item','shops/owner/sales/bill','shops/owner/staff/cashier','shops/owner/aiUsage/today','shops/owner/offlinePermits/forged']) {
      const {getDoc} = require('firebase/firestore');
      await assertFails(getDoc(doc(cashier,path)));
      await assertFails(setDoc(doc(cashier,path),{name:'forged',role:'owner'}));
    }
    await env.withSecurityRulesDisabled(async context => {
      await assertSucceeds(updateDoc(doc(context.firestore(), 'shops/owner'), { tier: 'restaurant', shopType: 'restaurant' }));
    });
    console.log('Admin plan rules: signup/profile allowed; client entitlement edits, deletion, forged audit and unauthorized writes denied; server update allowed.');
  } finally { await env.cleanup(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
