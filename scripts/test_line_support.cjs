// Offline operator UI checks. No production auth, data or LINE messages.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
(async()=>{
 const {chromium}=require(process.env.PLAYWRIGHT_MODULE);
 const browser=await chromium.launch({headless:true,executablePath:process.env.BROWSER_EXECUTABLE});
 try{
  const page=await browser.newPage(),errors=[];page.on('pageerror',e=>errors.push(e.message));page.on('dialog',d=>d.accept());
  await page.addInitScript(()=>{
   window.calls=[];window.testUser={uid:'founder'};window.denied=false;
   window.chats=[{userId:'U'+'a'.repeat(32),displayName:'ร้านทดสอบ <img src=x onerror=alert(1)>',preview:'ขอคุยกับเจ้าหน้าที่ค่ะ',mode:'waiting',updatedAt:Date.now()},
     {userId:'U'+'b'.repeat(32),displayName:'ร้านที่สอง',preview:'สวัสดี',mode:'bot',updatedAt:Date.now()}];
  });
  await page.route('**/*',async route=>{
   const u=new URL(route.request().url());let body;
   if(u.hostname==='www.gstatic.com'){
    if(u.pathname.endsWith('firebase-app.js'))body='export const initializeApp=()=>({});';
    if(u.pathname.endsWith('firebase-auth.js'))body=`export const getAuth=()=>({}),GoogleAuthProvider=class{};
      export const onAuthStateChanged=(a,cb)=>{window.authChanged=cb;queueMicrotask(()=>cb(window.testUser));};
      export const signOut=async()=>window.authChanged(null),signInWithPopup=async()=>{},signInWithEmailAndPassword=async()=>{};`;
    if(u.pathname.endsWith('firebase-functions.js'))body=`export const getFunctions=()=>({});export const httpsCallable=(f,name)=>async(data)=>{
      window.calls.push({name,data});if(window.denied)throw {code:'functions/permission-denied'};
      if(name==='adminLineChats')return {data:{chats:structuredClone(window.chats),next:null}};
      const row=window.chats.find(r=>r.userId===data.userId);
      if(row.mode!==data.expectedMode)throw {code:'functions/failed-precondition'};
      row.mode=data.mode;return {data:{mode:row.mode,sendingUntil:0}};
    };`;
   }else if(u.hostname==='support.test'){
    if(u.pathname==='/appcheck.js')body='export const setupAppCheck=()=>{};';
    else{const file=path.resolve(__dirname,'../public','.'+(u.pathname.endsWith('/')?u.pathname+'index.html':u.pathname));
     if(!file.startsWith(path.resolve(__dirname,'../public')+path.sep))return route.abort();
     body=fs.readFileSync(file);}
   }
   if(body===undefined)return route.abort();
   await route.fulfill({body,contentType:u.pathname.endsWith('.js')?'application/javascript':'text/html; charset=utf-8'});
  });
  const output=path.resolve(__dirname,'../.remember/tmp/line-support-preview');fs.mkdirSync(output,{recursive:true});
  for(const width of [320,390,768,1440]){
   await page.setViewportSize({width,height:960});await page.goto('https://support.test/line-support/');
   await page.locator('article').first().waitFor();assert.equal(await page.locator('article').count(),2);
   assert.equal(await page.locator('article img').count(),0);
   assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth+1),true);
   await page.locator('article').first().getByRole('button',{name:'รับช่วงแชท',exact:true}).click();
   await page.locator('article').first().getByRole('button',{name:'จบการดูแล / เปิดบอท'}).waitFor();
   assert.equal(await page.evaluate(()=>window.chats[0].mode),'human');
   await page.screenshot({path:path.join(output,`support-${width}.png`),fullPage:true});
   await page.locator('article').first().getByRole('button',{name:'จบการดูแล / เปิดบอท'}).click();
   await page.locator('article').first().getByRole('button',{name:'รับช่วงแชท',exact:true}).waitFor();
   assert.equal(await page.evaluate(()=>window.chats[0].mode),'bot');
   await page.locator('#search').fill('ร้านที่สอง');assert.equal(await page.locator('article').count(),1);
   await page.locator('#logout').click();await page.locator('#login').waitFor();assert.equal(await page.locator('article').count(),0);
  }
  await page.goto('https://support.test/line-support/');await page.locator('article').first().waitFor();
  await page.evaluate(()=>window.denied=true);await page.locator('#refresh').click();
  await page.getByText('บัญชีนี้ไม่มีสิทธิ์ดูแลแชท กรุณาใช้บัญชีผู้ดูแล Pokpok').waitFor();
  assert.equal(await page.locator('article').count(),0);assert.deepEqual(errors,[]);
  console.log('PASS 4 viewport sizes, safe rendering, takeover/resume, search, logout, revoked authorization.');
 }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;});
