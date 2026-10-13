const assert=require('node:assert/strict');
const {randomUUID}=require('node:crypto');
const admin=require('firebase-admin');
const {HttpsError}=require('firebase-functions/v2/https');
(async()=>{
  assert.match(process.env.FIRESTORE_EMULATOR_HOST||'',/^(127\.0\.0\.1|localhost):\d+$/);
  const app=admin.initializeApp({projectId:'demo-pokpok-admin'},'cash-rollover');
  const db=app.firestore(),FieldValue=admin.firestore.FieldValue;
  const shopId='rollover-'+randomUUID(),shop=db.collection('shops').doc(shopId);
  const api=require('./cash_accounting').handlers({db,FieldValue,HttpsError});
  const req=data=>({auth:{uid:shopId,token:{}},data:{shopId,acknowledgeDeviceUpdate:true,...data}});
  try{
    await shop.set({name:'isolated cash rollover test'});
    await api.open(req({requestId:'first',openingFloat:500}));
    const result=await Promise.allSettled([
      api.close(req({sessionId:'first',countedCash:500,autoOpenNext:true})),
      api.close(req({sessionId:'first',countedCash:500,autoOpenNext:true})),
      api.recordCashMovement(req({requestId:'race',sessionId:'first',kind:'cashIn',amount:20,reason:'race'})),
      api.open(req({requestId:'competing',openingFloat:0})),
    ]);
    assert.equal(result[0].status,'fulfilled',String(result[0].reason));
    assert.equal(result[1].status,'fulfilled',String(result[1].reason));
    assert.equal(result[3].status,'rejected');
    const old=(await shop.collection('cashSessions').doc('first').get()).data();
    assert.equal(old.summary.expectedCash,result[2].status==='fulfilled'?520:500);
    const opened=await shop.collection('cashSessions').where('status','==','open').get();
    assert.equal(opened.size,1);assert.equal(opened.docs[0].id,old.nextSessionId);
    assert.equal(opened.docs[0].data().openingFloat,500);
    assert.equal((await shop.collection('cashControl').doc('current').get()).data().sessionId,old.nextSessionId);
    await api.recordCashMovement(req({requestId:'next-in',sessionId:old.nextSessionId,kind:'cashIn',amount:10,reason:'next round'}));
    const summary=await api.close(req({sessionId:old.nextSessionId,countedCash:510,autoOpenNext:true}));
    assert.equal(summary.expectedCash,510);assert.equal(summary.grossTotal,0);
    await api.close(req({sessionId:'first',countedCash:999,autoOpenNext:true}));
    assert.deepEqual((await shop.collection('cashSessions').doc('first').get()).data(),old);
    assert.equal((await shop.collection('cashSessions').get()).size,3);
    assert.equal((await shop.collection('moneyMovements').where('sessionId','==',null).get()).size,0);
    console.log('PASS atomic cash rollover, concurrent closes/drawer/open, counted carry and immutable history');
  }finally{await db.recursiveDelete(shop);await app.delete();}
})().catch(e=>{console.error(e);process.exitCode=1;});
