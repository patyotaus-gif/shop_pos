'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const {runTransaction}=require('./transaction_retry');
const {fixture}=require('./accounting_fixture.cjs');
const {HttpsError}=require('firebase-functions/v2/https');
const expired=()=>Object.assign(new Error('3 INVALID_ARGUMENT: Transaction is invalid or closed.'),{code:3});
test('closed transaction restarts with fresh data and a fresh transaction object',async()=>{
  let attempts=0;const transactions=[];
  const db={runTransaction:async action=>action({revision:++attempts})};
  const result=await runTransaction(db,async tx=>{
    transactions.push(tx);if(tx.revision===1)throw expired();return tx.revision;
  });
  assert.equal(result,2);assert.notEqual(transactions[0],transactions[1]);
});
test('bounded retries preserve the failure instead of reporting success',async()=>{
  let attempts=0;
  await assert.rejects(runTransaction({runTransaction:async()=>{attempts++;throw expired();}},()=>{}),{code:3});
  assert.equal(attempts,3);
});
test('permission, validation, unknown commit and unrelated code 3 errors are not retried',async()=>{
  for(const error of [new HttpsError('permission-denied','denied'),new HttpsError('failed-precondition','closed'),
    Object.assign(new Error('invalid query'),{code:3}),Object.assign(new Error('network'),{code:14})]){
    let attempts=0;await assert.rejects(runTransaction({runTransaction:async()=>{attempts++;throw error;}},()=>{}),e=>e===error);
    assert.equal(attempts,1);
  }
});
test('drawer retry does not duplicate a committed movement when the first result is lost',async()=>{
  const root='shops/s';
  const f=fixture({[root+'/cashControl/current']:{sessionId:'day',revision:0},
    [root+'/cashSessions/day']:{status:'open',accountingVersion:1}});
  const original=f.db.runTransaction;let first=true;
  f.db.runTransaction=async action=>{const value=await original(action);if(first){first=false;throw expired();}return value;};
  const h=require('./cash_accounting').handlers({...f,HttpsError});
  const result=await h.recordCashMovement({auth:{uid:'s',token:{}},data:{shopId:'s',requestId:'one',sessionId:'day',kind:'cashIn',amount:20,reason:'change'}});
  assert.equal(result.id,'cash-one');
  assert.equal([...f.docs.keys()].filter(p=>p.includes('/moneyMovements/')).length,1);
  assert.equal(f.docs.get(root+'/moneyMovements/cash-one').amountMinor,2000);
  assert.equal(f.docs.get(root+'/cashControl/current').revision,1);
});
