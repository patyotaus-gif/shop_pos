// Local emulator only: real Firestore transactions + client access rules.
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs');
const {randomUUID} = require('node:crypto');
const admin = require('firebase-admin');
const {HttpsError} = require('firebase-functions/v2/https');
const {initializeTestEnvironment, assertFails, assertSucceeds} = require('@firebase/rules-unit-testing');
const {doc, setDoc, getDoc} = require('firebase/firestore');
(async () => {
  assert.match(process.env.FIRESTORE_EMULATOR_HOST || '', /^(127\.0\.0\.1|localhost):\d+$/);
  const projectId = 'demo-pokpok-admin';
  const app = admin.initializeApp({projectId}, 'auto-print-test');
  const db = app.firestore(), FieldValue = admin.firestore.FieldValue;
  const env = await initializeTestEnvironment({projectId, firestore: {
    rules: fs.readFileSync(require('node:path').join(__dirname, '../firestore.rules'),'utf8'),
  }});
  const shopId = 'print-' + randomUUID(), shop = db.collection('shops').doc(shopId);
  let clock = Date.now();
  const h = require('./auto_print').handlers({db,FieldValue,HttpsError,now:()=>clock});
  const req = data => ({auth:{uid:shopId,token:{}},data:{shopId,deviceId:'one',...data}});
  try {
    const configured=await h.configure(req({enabled:true,kitchen:true,receipts:true}));
    const request=data=>req({session:configured.session,...data});
    const data={status:'open',tableName:'A1',items:[{id:'one',productName:'ข้าวผัด',quantity:1,kitchenStatus:'sent'}]};
    await shop.collection('tableOrders').doc('table').set(data);
    const event={shopId,source:'table',sourceId:'table',after:data,eventAtMs:clock+1};
    await Promise.all([h.enqueue(event),h.enqueue(event),h.enqueue(event)]);
    assert.equal((await shop.collection('autoPrintJobs').get()).size,1);
    const claims=await Promise.all([h.claim(request()),h.claim(request()),h.claim(request())]);
    const claimed=claims.filter(j=>j.attempt);assert.equal(claimed.length,1);
    const j=claimed[0];
    await h.heartbeat(request({jobId:j.jobId,attempt:j.attempt}));
    await shop.collection('tableOrders').doc('table').update({status:'cancelled'});
    await assert.rejects(()=>h.heartbeat(request({jobId:j.jobId,attempt:j.attempt})),{code:'failed-precondition'});
    await shop.collection('tableOrders').doc('table').update({status:'open'});
    const manual=require('./kitchen_print').handlers({db,FieldValue,HttpsError,now:()=>clock});
    await assert.rejects(()=>manual.claim(req({source:'table',orderId:'table'})),{code:'failed-precondition'});
    const result=request({jobId:j.jobId,attempt:j.attempt,outcome:'sent'});
    await Promise.all([h.finish(result),h.finish(result)]);
    assert.deepEqual(await manual.claim(req({source:'table',orderId:'table'})),{alreadyPrinted:true});
    // New items added after initial send are the only lines in the second job.
    const next={...data,items:[...data.items,{id:'two',productName:'ชาเย็น',quantity:2,kitchenStatus:'sent'}]};
    await shop.collection('tableOrders').doc('table').set(next);
    await h.enqueue({...event,before:data,after:next,eventAtMs:clock+2});
    const second=await h.claim(request());assert.equal(second.lines.length,1);
    assert.equal(second.lines[0].name,'ชาเย็น');
    await h.finish(request({jobId:second.jobId,attempt:second.attempt,outcome:'needsReview'}));
    assert.deepEqual(await h.claim(request()),{blocked:second.jobId});
    await h.review(req({jobId:second.jobId,action:'retry'}));
    const retry=await h.claim(request());assert.equal(retry.reprint,true);
    clock+=300001;
    await h.review(req({jobId:retry.jobId,action:'received'}));
    assert.deepEqual(await h.claim(request()),{empty:true});
    for(const collection of ['autoPrintConfig','autoPrintJobs']) {
      const id=collection==='autoPrintConfig'?'current':j.jobId;
      const path=`shops/${shopId}/${collection}/${id}`;
      await assertSucceeds(getDoc(doc(env.authenticatedContext(shopId).firestore(),path)));
      await assertFails(setDoc(doc(env.authenticatedContext(shopId).firestore(),path),{enabled:true,status:'pending'}));
      await assertFails(getDoc(doc(env.authenticatedContext('another-owner').firestore(),path)));
      await assertFails(getDoc(doc(env.unauthenticatedContext().firestore(),path)));
    }
    assert.equal((await shop.collection('sales').get()).size,0);
    assert.equal((await shop.collection('moneyMovements').get()).size,0);
    console.log('PASS auto-print real transactions, duplicate triggers, three competing consumers, manual/auto coordination, new lines, ambiguous recovery, access rules and no money changes');
  } finally {
    await db.recursiveDelete(shop); await env.cleanup(); await app.delete();
  }
})().catch(e=>{console.error(e);process.exitCode=1;});
