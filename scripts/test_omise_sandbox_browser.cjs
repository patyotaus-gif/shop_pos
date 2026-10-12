// Local browser fixture; no Firebase auth, Omise requests or real payments.
const {chromium} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const fs=require('node:fs'), path=require('node:path'), http=require('node:http'), assert=require('node:assert/strict');
const root=path.resolve('public');
const server=http.createServer((req,res)=>{
  let file=path.resolve(root,'.'+new URL(req.url,'http://localhost').pathname);
  if(!file.startsWith(root+path.sep)){res.writeHead(403);return res.end();}
  if(fs.existsSync(file)&&fs.statSync(file).isDirectory())file=path.join(file,'index.html');
  if(!fs.existsSync(file)){res.writeHead(404);return res.end();}
  res.setHeader('Content-Type',file.endsWith('.js')?'text/javascript':'text/html');res.end(fs.readFileSync(file));
});
(async()=>{
  await new Promise(r=>server.listen(0,'127.0.0.1',r));
  const base=`http://127.0.0.1:${server.address().port}`;
  const browser=await chromium.launch({channel:'msedge',headless:true});
  try{
    const context=await browser.newContext({viewport:{width:360,height:800}});
    await context.route('**/*',async route=>{
      const url=route.request().url();let body;
      if(url.endsWith('/firebase-app.js'))body='export const initializeApp=()=>({});';
      else if(url.endsWith('/firebase-auth.js'))body=`
        const auth={currentUser:{uid:'founder',email:'test@example.test'}};
        export const getAuth=()=>auth;
        export const onAuthStateChanged=(_,fn)=>queueMicrotask(()=>fn(auth.currentUser));
        export const signInWithEmailAndPassword=async()=>{},signInWithPopup=async()=>{},signOut=async()=>{};
        export class GoogleAuthProvider{};`;
      else if(url.endsWith('/firebase-functions.js'))body=`
        export const getFunctions=()=>({});
        export const httpsCallable=(_,name)=>async data=>{
          window.calls.push({name,data});
          if(name==='omiseSandboxConfig')return {data:{publicKey:'pkey_test_fixture',testMode:true,amount:10000}};
          const id=data.attemptId;
          if(name==='omiseSandboxCreate'){
            localStorage.setItem('fixture-attempt',id);
            if(window.dropCreate)throw Object.assign(Error('timeout'),{code:'functions/unavailable'});
          }
          return {data:{testMode:true,amount:10000,attemptId:id,status:window.resultStatus||'successful',chargeId:'chrg_test_fixture',
            authorizeUri:window.resultStatus==='pending'?'https://api.omise.co/payments/test':null}};
        };`;
      else if(url.endsWith('/appcheck.js'))body='export const setupAppCheck=()=>({});';
      else if(url==='https://cdn.omise.co/omise.js')body=`
        window.OmiseCard={configure(){},open(opts){window.cardOpens++;opts.onCreateTokenSuccess('tokn_test_fixture');opts.onFormClosed();}};
        window.Omise={setPublicKey(){},createSource(type,data,cb){window.sources.push({type,data});cb(200,{id:'src_test_fixture',livemode:false});}};`;
      if(body!==undefined)return route.fulfill({contentType:'text/javascript',body});
      if(url.startsWith(base))return route.continue();
      return route.abort();
    });
    const page=await context.newPage(),errors=[];
    page.on('pageerror',e=>errors.push(e.message));
    await page.addInitScript(()=>{window.calls=[];window.cardOpens=0;window.sources=[];});
    await page.goto(base+'/payment-test/');
    await page.waitForFunction(()=>document.getElementById('status').textContent.includes('พร้อมทดสอบ'));
    assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
    await page.click('#pay');await page.waitForFunction(()=>document.getElementById('startNew').hidden===false);
    assert.equal(await page.evaluate(()=>window.calls.filter(c=>c.name==='omiseSandboxCreate').length),1);
    await page.reload();await page.waitForFunction(()=>document.getElementById('startNew').hidden===false);
    assert.equal(await page.evaluate(()=>window.calls.filter(c=>c.name==='omiseSandboxCreate').length),0);
    await page.click('#startNew');await page.selectOption('#method','truemoney');
    await page.click('#pay');assert.equal(await page.evaluate(()=>window.sources.length),0);
    await page.fill('#phone','0812345678');await page.evaluate(()=>{window.resultStatus='pending';});await page.click('#pay');
    await page.waitForFunction(()=>document.getElementById('authorize').hidden===false);
    assert.equal(await page.locator('#authorize').getAttribute('href'),'https://api.omise.co/payments/test');
    assert.equal(await page.locator('#startNew').isVisible(),false);
    await page.evaluate(()=>{window.resultStatus='successful';});await page.click('#refresh');
    await page.waitForFunction(()=>document.getElementById('startNew').hidden===false);await page.click('#startNew');
    await page.selectOption('#method','card');await page.evaluate(()=>{window.dropCreate=true;});await page.click('#pay');
    await page.waitForFunction(()=>document.getElementById('status').textContent.includes('ดำเนินการไม่ได้'));
    assert.equal(await page.locator('#startNew').isVisible(),false);
    const pendingId=await page.evaluate(()=>JSON.parse(localStorage.getItem('pokpok-omise-sandbox-v1:founder')).attemptId);
    await page.reload();await page.waitForFunction(()=>document.getElementById('startNew').hidden===false);
    assert.equal(await page.evaluate(()=>window.calls.find(c=>c.name==='omiseSandboxStatus').data.attemptId),pendingId);
    assert.equal(await page.evaluate(()=>window.calls.filter(c=>c.name==='omiseSandboxCreate').length),0);
    await page.setViewportSize({width:820,height:1180});
    assert(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth));
    assert.deepEqual(errors,[]);
    console.log('PASS: card, TrueMoney, validation, reload, lost response recovery, pending lock, mobile/tablet layout; mocked providers only');
  }finally{await browser.close();server.close();}
})().catch(e=>{console.error(e);server.close();process.exitCode=1;});
