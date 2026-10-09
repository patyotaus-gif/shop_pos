// LOCAL SECURITY AUDIT ONLY: success confirms the listed vulnerabilities exist.
// Historical pre-fix reproduction, NOT a release gate; it should now fail.
// Use security_hardening.integration.cjs and scripts/test_supplier_security.cjs
// to verify protections. Demo Firestore + headless fixture; no production requests.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const admin = require('firebase-admin');
const {initializeTestEnvironment, assertFails, assertSucceeds} = require('@firebase/rules-unit-testing');
const {doc, setDoc, updateDoc, getDoc, deleteField} = require('firebase/firestore');
const {HttpsError} = require('firebase-functions/v2/https');
const root = path.join(__dirname, '..');
(async () => {
  assert.match(process.env.FIRESTORE_EMULATOR_HOST || '', /^(127\.0\.0\.1|localhost):\d+$/);
  const projectId = 'demo-pokpok-security';
  const env = await initializeTestEnvironment({projectId, firestore:{rules:fs.readFileSync(path.join(root,'firestore.rules'),'utf8')}});
  const app = admin.initializeApp({projectId}, 'local-security-audit');
  const db = app.firestore();
  const findings = [];
  const source = fs.readFileSync(path.join(__dirname,'index.js'),'utf8');
  const exports = {};
  const firestore = Object.assign(() => db, {Timestamp:admin.firestore.Timestamp, FieldValue:admin.firestore.FieldValue});
  const context = {exports, admin:{firestore}, HttpsError, REFERRAL_BONUS_DAYS:30, onCall:fn=>fn, console};
  function load(name) {
    const start = source.indexOf(`exports.${name} = onCall(`);
    assert.ok(start >= 0);
    const end = source.indexOf('\n});', start);
    assert.ok(end > start);
    vm.runInNewContext(source.slice(start, end + 4), context);
    return exports[name];
  }
  try {
    const attacker = env.authenticatedContext('audit-attacker').firestore();
    const victim = 'audit-victim';
    await db.doc(`shops/${victim}`).set({name:'Victim fixture',tier:'full'});
    await db.doc(`shops/${victim}/marketplaceOrders/audit-order`).set({status:'placed',items:[],total:100});
    await assertFails(updateDoc(doc(attacker,`shops/${victim}/marketplaceOrders/audit-order`),{status:'cancelled'}));
    await assertFails(getDoc(doc(attacker,`shops/${victim}`)));
    // A normal account with NO supplier profile can create its own supplier path.
    const supplierOrder = doc(attacker,'suppliers/audit-attacker/orders/audit-order');
    await assertSucceeds(setDoc(supplierOrder,{shopId:'audit-attacker',status:'placed',items:[]}));
    await assertSucceeds(updateDoc(supplierOrder,{shopId:victim}));
    const supplierSetOrderStatus = load('supplierSetOrderStatus');
    await supplierSetOrderStatus({auth:{uid:'audit-attacker',token:{}},data:{orderId:'audit-order',status:'cancelled'}});
    assert.equal((await db.doc(`shops/${victim}/marketplaceOrders/audit-order`).get()).data().status,'cancelled');
    findings.push({id:'SEC-01',confirmed:true,result:'Normal account with no supplier profile modified another shop marketplace status through server mirror after direct write was denied.'});

    const ownShop = db.doc('shops/audit-attacker');
    const end = admin.firestore.Timestamp.fromMillis(Date.now()+60*86400000);
    await ownShop.set({name:'Attacker fixture',tier:'full',trialEndsAt:end,referralCode:'ATTACKER'});
    await db.doc('shops/audit-referrer').set({trialEndsAt:end,referralCode:'AUDITCODE'});
    const applyReferral = load('applyReferral');
    const request = {auth:{uid:'audit-attacker',token:{}},data:{code:'AUDITCODE'}};
    assert.equal((await applyReferral(request)).applied,true);
    assert.equal((await applyReferral(request)).applied,false);
    await assertSucceeds(updateDoc(doc(attacker,'shops/audit-attacker'),{referredBy:deleteField()}));
    assert.equal((await applyReferral(request)).applied,true);
    const extraDays = ((await ownShop.get()).data().trialEndsAt.toMillis()-end.toMillis())/86400000;
    assert.equal(extraDays,60);
    findings.push({id:'SEC-02',confirmed:true,result:'Clearing client-writable referral marker allows a second 30-day reward for the same account/code.',extraDays});

    const payload='<img src="audit-missing" onerror="window.__pokpokAuditMarker=1">';
    const order = {shopId:'audit-attacker',shopName:'Audit fixture',status:'placed',items:[{name:'Fixture',quantity:payload,price:1}]};
    await db.doc('suppliers/audit-supplier').set({active:true,name:'Fixture'});
    await assertSucceeds(setDoc(doc(attacker,'suppliers/audit-supplier/orders/fixture-xss'),order));
    const browserModule = process.env.PLAYWRIGHT_MODULE;
    assert.ok(browserModule,'Set PLAYWRIGHT_MODULE to local Playwright install');
    const {chromium} = require(browserModule);
    const browser = await chromium.launch({headless:true,executablePath:process.env.BROWSER_EXECUTABLE});
    try {
      const page = await browser.newPage();
      await page.route('**/*', route => route.abort());
      await page.setContent('<main id="fixture"></main>');
      const html = fs.readFileSync(path.join(root,'public/supplier/index.html'),'utf8');
      const start = html.indexOf('  function orderCard(id, o) {');
      const end = html.indexOf('  // ── Modal helpers',start);
      assert.ok(start>=0 && end>start);
      await page.evaluate(({render,order})=>{
        const STATUS={placed:['Placed',''],accepted:['Accepted','']};
        const esc=s=>String(s).replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
        const baht=n=>Number(n).toFixed(2);
        const orderCard=new Function('STATUS','esc','baht',render+';return orderCard;')(STATUS,esc,baht);
        document.querySelector('#fixture').appendChild(orderCard('fixture-xss',order));
      },{render:html.slice(start,end),order});
      await page.waitForFunction(()=>window.__pokpokAuditMarker===1);
      findings.push({id:'SEC-03',confirmed:true,result:'Rules accepted nonnumeric quantity; actual supplier order renderer executed harmless script marker from stored quantity. No network allowed.'});
    } finally { await browser.close(); }

    await assertSucceeds(updateDoc(doc(attacker,'suppliers/audit-supplier/orders/fixture-xss'),{items:[{name:'Fixture',quantity:-50,price:-1}],takeRate:0,status:'delivered'}));
    findings.push({id:'SEC-04',confirmed:true,result:'Purchasing account can bypass marketplace quantity/price/state checks and change fee directly.'});

    const staff=env.authenticatedContext('audit-staff',{staffRole:'cashier',staffShopId:victim,staffId:'cashier',staffVersion:1}).firestore();
    for (const suffix of ['settings/shop','sales/sale','staff/cashier','inventoryControl/online','kitchenPrintJobs/job']) {
      await assertFails(setDoc(doc(staff,`shops/${victim}/${suffix}`),{role:'owner',total:0}));
    }
    const {tokenHash,authorized}=require('./customer_order');
    assert.equal(authorized({customerTokenHash:tokenHash('a'.repeat(64))},'b'.repeat(64)),false);
    findings.push({id:'GUARDS',confirmed:true,result:'Cross-shop direct read/write, direct cashier privilege/financial/print writes and incorrect customer capability denied.'});
    fs.writeFileSync(path.join(root,'.remember/tmp/security-audit-findings.json'),JSON.stringify({at:new Date().toISOString(),scope:'Local emulator + isolated supplier renderer only',findings},null,2));
    for(const finding of findings) console.log('AUDIT '+finding.id+' '+finding.result);
  } finally { await env.cleanup(); await app.delete(); }
})().catch(e=>{console.error('AUDIT FAILED '+e.message);process.exitCode=1;});
