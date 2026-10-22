'use strict';
const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const {HttpsError}=require('firebase-functions/v2/https');
// Execute the actual deployed guard without initializing Firebase or secrets.
const source=fs.readFileSync(path.join(__dirname,'index.js'),'utf8');
const start=source.indexOf('const FOUNDER_EMAILS ='),end=source.indexOf('// Grant or revoke',start);
assert.ok(start>0 && end>start);
const context={HttpsError};vm.createContext(context);
vm.runInContext(source.slice(start,end)+'\nthis.guard=assertFounder;this.bootstrap=FOUNDER_EMAILS[0];',context);
const request=token=>({auth:{uid:'test-user',token}});
test('founder rejects unauthenticated, unverified bootstrap email and ordinary account',()=>{
  assert.throws(()=>context.guard({}),{code:'unauthenticated'});
  for(const token of [{},{email:context.bootstrap},{email:context.bootstrap,email_verified:false},
    {email:context.bootstrap,email_verified:'true'},{email:'other@example.invalid',email_verified:true},
    {founder:'true'}]) assert.throws(()=>context.guard(request(token)),{code:'permission-denied'});
});
test('verified bootstrap owner and server-issued founder claim retain access',()=>{
  context.guard(request({email:context.bootstrap.toUpperCase(),email_verified:true}));
  context.guard(request({founder:true}));
});
test('staff session cannot borrow founder claim or bootstrap email',()=>{
  for(const token of [{staffRole:'cashier',founder:true},
    {staffRole:'cashier',email:context.bootstrap,email_verified:true}])
    assert.throws(()=>context.guard(request(token)),{code:'permission-denied'});
});
