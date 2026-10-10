// Regression for the mobile Sale serializer omitting isRefunded on new sales.
// Emulator only; include the drawer lock, ledger, stock and receipt counter.
const assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path');
const {initializeTestEnvironment,assertSucceeds,assertFails}=require('@firebase/rules-unit-testing');
const {doc,setDoc,getDoc,writeBatch,serverTimestamp,Timestamp,increment,deleteDoc}=require('firebase/firestore');
(async()=>{
  if(!process.env.FIRESTORE_EMULATOR_HOST)throw Error('Emulator required');
  const env=await initializeTestEnvironment({projectId:'demo-pokpok-admin',
    firestore:{rules:fs.readFileSync(path.join(__dirname,'../firestore.rules'),'utf8')}});
  try {
    const owner='pos-serializer-owner',root=`shops/${owner}`;
    const client=env.authenticatedContext(owner).firestore();
    await env.withSecurityRulesDisabled(async context=>{
      const db=context.firestore();
      await setDoc(doc(db,root+'/products/brownie'),{name:'Brownie',price:35,stock:20});
      await setDoc(doc(db,root+'/accountingSettings/current'),{enabled:true});
    });
    function checkout(db,id,flag){
      const batch=writeBatch(db);
      batch.set(doc(db,root+'/sales/'+id),{
        items:[{productId:'brownie',productName:'Brownie',price:35,quantity:2,subtotal:70}],
        total:70,discount:0,paid:70,change:0,createdAt:Timestamp.now(),
        isDebt:false,customerName:null,paymentMethod:'cash',salesChannel:'takeaway',
        receiptNo:'261010-001',accountingVersion:1,stockDeducted:{brownie:2},
        ingredientsDeducted:true,ingredientUsage:{},
        ...(flag==='omitted'?{}:{isRefunded:flag}),
      });
      batch.set(doc(db,root+'/moneyMovements/sale-'+id),{
        kind:'sale',saleId:id,amountMinor:7000,salesMinor:7000,debtMinor:0,
        method:'cash',occurredAt:Timestamp.now(),recordedAt:serverTimestamp(),
        sessionId:null,needsReconciliation:true,schemaVersion:1,actor:owner,
      });
      batch.set(doc(db,root+'/cashControl/current'),{revision:increment(1)},{merge:true});
      batch.update(doc(db,root+'/products/brownie'),{stock:increment(-2)});
      batch.set(doc(db,root+'/counters/receipt'),{day:'261010',seq:1});
      return batch.commit();
    }
    await assertSucceeds(checkout(client,'old-client','omitted'));
    await assertSucceeds(checkout(client,'new-client',false));
    for(const [id,value] of [['refunded',true],['null',null],['string','false']])
      await assertFails(checkout(client,id,value));
    await assertFails(checkout(env.unauthenticatedContext().firestore(),'anonymous',false));
    await assertFails(checkout(env.authenticatedContext('another-shop').firestore(),'other',false));
    await assertFails(checkout(env.authenticatedContext('cashier',{staffRole:'cashier',staffShopId:owner}).firestore(),'staff',false));
    // A duplicate batch cannot mutate a previously saved sale/ledger or deduct twice.
    await assertFails(checkout(client,'old-client','omitted'));
    await assertFails(deleteDoc(doc(client,root+'/sales/old-client')));
    assert.equal((await getDoc(doc(client,root+'/products/brownie'))).data().stock,16);
    assert.equal((await getDoc(doc(client,root+'/cashControl/current'))).data().revision,2);
    console.log('PASS POS legacy/new serializer, stock/ledger atomicity, refund and access restrictions');
  } finally {await env.cleanup();}
})().catch(e=>{console.error(e);process.exitCode=1;});
