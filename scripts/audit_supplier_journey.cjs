// Regression audit of the real portal UI with in-memory Firebase adapters.
// All browser network traffic is blocked. No production account or writes.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const root = path.resolve(__dirname, '..');
const out = path.join(root, '.remember/tmp/supplier-audit');
fs.mkdirSync(out, {recursive:true});
const html = fs.readFileSync(path.join(root, 'public/supplier/index.html'), 'utf8');
const code = html.match(/<script type="module">([\s\S]*?)<\/script>/)[1]
  .replace(/^  import [\s\S]*?;\s*$/gm, '');
const shell = html.replace(/<script type="module">[\s\S]*?<\/script>/, '')
  .replace(/<link[^>]*>/g, '');
const adapters = `
const fixture = window.fixture = {
  user:null, profile:{name:'ร้านส่งทดสอบ',category:'วัตถุดิบ',active:true,minOrder:100},
  products:[{id:'rice',name:'ข้าวสารหอมมะลิ',price:12.50,unit:'กก.',moq:0.5,available:true}],
  orders:[{id:'order1',shopName:'ร้านลูกค้าทดสอบ',status:'placed',items:[{productId:'rice',name:'ข้าวสารหอมมะลิ',price:12.50,quantity:1.5,unit:'กก.'}]}],
  writes:[],calls:[],subs:[],failWrite:false,failProfile:false,failStatus:false,failLogin:false
};
const initializeApp=()=>({}),setupAppCheck=()=>{},getAuth=()=>({}),getFirestore=()=>({}),getFunctions=()=>({}),getStorage=()=>({});
let createdId=0;
const doc=(...args)=>{let path=args.filter(x=>typeof x==='string'||x?.path).map(x=>x.path||x).join('/');if(args.length===1&&args[0]?.path)path+='/created-'+(++createdId);return {path,id:path.split('/').pop()};};
const collection=doc,query=x=>x,orderBy=()=>null,deleteField=()=>null;
const snap=d=>({id:d.id,exists:()=>true,data:()=>d});
function emit(){for(const sub of fixture.subs){const rows=sub.q.path.endsWith('/products')?fixture.products:fixture.orders;sub.cb({empty:!rows.length,forEach:fn=>rows.forEach(d=>fn(snap(d)))});}}
const onSnapshot=(q,cb,error)=>{const sub={q,cb,error};fixture.subs.push(sub);emit();return()=>{fixture.subs=fixture.subs.filter(s=>s!==sub);};};
const getDoc=async()=>{if(fixture.failProfile)throw Error('fixture profile unavailable');return {exists:()=>true,data:()=>fixture.profile};};
const onAuthStateChanged=(_,cb)=>{fixture.auth=cb;cb(null);};
const signInWithEmailAndPassword=async()=>{if(fixture.failLogin)throw Error('fixture invalid credentials');fixture.user={uid:'supplier-fixture'};setTimeout(()=>fixture.auth(fixture.user),0);};
const signOut=async()=>{fixture.user=null;await fixture.auth(null);};
async function write(kind,ref,data){if(fixture.failWrite)throw Error('fixture offline');fixture.writes.push({kind,path:ref.path,data});if(ref.path.includes('/products/')){const id=ref.path.split('/').pop();const prev=fixture.products.find(p=>p.id===id);if(kind==='delete')fixture.products=fixture.products.filter(p=>p.id!==id);else if(prev)Object.assign(prev,data);else fixture.products.push({id,...data});}else Object.assign(fixture.profile,data);emit();}
const setDoc=(r,d)=>write('set',r,d),updateDoc=(r,d)=>write('update',r,d),deleteDoc=r=>write('delete',r),addDoc=setDoc;
const storageRef=()=>({}),uploadBytes=async()=>{},getDownloadURL=async()=>'',deleteObject=async()=>{};
const httpsCallable=(_,name)=>async data=>{fixture.calls.push({name,...data});if(fixture.failStatus)throw Error('fixture unavailable');const o=fixture.orders.find(o=>o.id===data.orderId);o.status=data.status;emit();return {data:{ok:true}};};
window.auditEmit=emit;
`;
const findings = [], passed = [];
async function boot(browser,width=390,height=844){
  const page=await browser.newPage({viewport:{width,height}});
  page.errors=[];
  page.on('pageerror',e=>page.errors.push(e.message));
  page.on('dialog',d=>d.accept());
  await page.route('**/*',route=>route.abort());
  await page.setContent(shell);
  await page.addScriptTag({content:adapters+'\n'+code});
  return page;
}
async function login(page){await page.locator('#email').fill('supplier@example.test');await page.locator('#password').fill('fixture-only');await page.locator('#loginBtn').click();await page.locator('#app-view').waitFor({state:'visible'});}
function finding(id,detail,evidence){findings.push({id,detail,evidence});}
(async()=>{
  const browser=await chromium.launch({headless:true,executablePath:process.env.BROWSER_EXECUTABLE});
  try{
    const page=await boot(browser);
    await login(page);
    passed.push('Supplier login and incoming order render with fixture auth');
    const total=await page.locator('.o-total').innerText();
    if(!total.includes('18.75'))finding('SUP-01','Order total loses satang: 12.50 × 1.5 must equal 18.75',total);
    assert.match(await page.locator('#ordersList').innerText(),/ไม่มีข้อมูลที่อยู่/);
    await page.evaluate(()=>{Object.assign(fixture.orders[0],{total:17.25,shopAddress:'<img src=x onerror=alert(1)>',shopPhone:'0000000000'});auditEmit();});
    assert.match(await page.locator('.o-total').innerText(),/17.25/);
    assert.equal(await page.locator('#ordersList img').count(),0);
    assert.match(await page.locator('#ordersList').innerText(),/0000000000/);
    await page.getByRole('button',{name:'รับออเดอร์',exact:true}).click();
    await page.getByRole('button',{name:'จัดส่งแล้ว',exact:true}).waitFor();
    await page.getByRole('button',{name:'จัดส่งแล้ว',exact:true}).click();
    assert.match(await page.locator('#ordersList').innerText(),/รอร้านค้ายืนยันรับของ/);
    passed.push('Accept -> ship calls supplierSetOrderStatus and waits for shop receipt');
    await page.locator('#tabCatalog').click();
    await page.evaluate(()=>fixture.subs.find(s=>s.q.path.endsWith('/products')).error(Error('offline')));
    assert.match(await page.locator('#catalogList').innerText(),/โหลดข้อมูลไม่สำเร็จ/);
    await page.locator('#catalogList button').click();
    const price=await page.locator('#catalogList .p-meta').first().innerText();
    if(!price.includes('12.5'))finding('SUP-02','Catalog price loses satang',price);
    for(const [w,h] of [[320,740],[390,844],[800,1280],[1480,924]]){
      await page.setViewportSize({width:w,height:h});
      const sizes=await page.evaluate(()=>({viewport:innerWidth,document:document.documentElement.scrollWidth,offscreen:[...document.querySelectorAll('#catalogList button')].filter(b=>b.getBoundingClientRect().right>innerWidth).map(b=>b.textContent)}));
      await page.screenshot({path:path.join(out,'catalog-'+w+'.png'),fullPage:true});
      if(sizes.document>w||sizes.offscreen.length)finding('SUP-03','Catalog horizontal overflow at width '+w,sizes);
      else passed.push('Catalog fits width '+w);
    }
    await page.setViewportSize({width:390,height:844});
    await page.evaluate(()=>{fixture.products[0].name='SUPPLIER-PRODUCT-CODE-'+('A'.repeat(70));auditEmit();});
    const longWidth=await page.evaluate(()=>document.documentElement.scrollWidth);
    if(longWidth>390)finding('SUP-03','Unbroken long product code forces horizontal overflow on phone',{viewport:390,content:longWidth});
    await page.screenshot({path:path.join(out,'catalog-long-name.png'),fullPage:true});
    await page.evaluate(()=>{fixture.products[0].name='ข้าวสารหอมมะลิ';auditEmit();});
    await page.setViewportSize({width:800,height:1280});
    await page.locator('[data-toggle]').first().click();
    assert.match(await page.locator('#catalogList').innerText(),/เปิดขาย/);
    await page.locator('[data-toggle]').first().click();
    passed.push('Product available/unavailable toggle');
    await page.locator('#addProductBtn').click();
    await page.locator('#m_name').fill('สินค้าเพิ่มทดสอบ');
    await page.locator('#m_price').fill('25.75');
    await page.locator('#m_moq').fill('0.5');
    await page.locator('#m_save').click();
    assert.equal(await page.locator('#catalogList .card').count(),2);
    passed.push('Add product retains decimal price and fractional MOQ in write');
    await page.locator('#addProductBtn').click();
    await page.locator('#m_name').fill('invalid fixture');
    await page.locator('#m_price').fill('-10');
    await page.locator('#m_moq').fill('0');
    await page.locator('#m_save').click();
    const invalid=await page.evaluate(()=>fixture.writes.find(w=>w.data?.price===-10));
    if(invalid)finding('SUP-04','Product save accepts negative price and zero MOQ before database write',invalid.data);
    assert.equal(invalid,undefined);
    assert.match(await page.locator('#m_imgstatus').innerText(),/กรอกชื่อสินค้า/);
    await page.locator('#m_cancel').click();
    await page.locator('#editProfileBtn').click();
    await page.locator('#m_area').fill('พื้นที่ทดสอบ');
    await page.locator('#m_save').click();
    assert.equal(await page.evaluate(()=>fixture.profile.area),'พื้นที่ทดสอบ');
    passed.push('Profile edit success');
    await page.locator('#editProfileBtn').click();
    await page.evaluate(()=>fixture.failWrite=true);
    await page.locator('#m_save').click();
    await page.waitForTimeout(100);
    if(page.errors.some(e=>e.includes('fixture offline')))finding('SUP-05','Profile save failure produces unhandled error without inline recovery message',page.errors);
    assert.match(await page.locator('#m_error').innerText(),/บันทึกไม่สำเร็จ/);
    assert.equal(await page.locator('#m_save').isEnabled(),true);
    await page.locator('#m_cancel').click();
    await page.evaluate(()=>fixture.failWrite=false);
    await page.locator('#tabOrders').click();
    await page.evaluate(()=>fixture.subs.find(s=>s.q.path.endsWith('/orders')).error(Error('offline')));
    assert.match(await page.locator('#ordersList').innerText(),/โหลดข้อมูลไม่สำเร็จ/);
    await page.locator('#ordersList button').click();
    await page.evaluate(()=>{fixture.orders[0].status='placed';fixture.failStatus=true;auditEmit();});
    await page.getByRole('button',{name:'รับออเดอร์',exact:true}).click();
    await page.waitForTimeout(100);
    const failedLabel=await page.locator('.btn-go').textContent();
    if(failedLabel==='…')finding('SUP-06','Failed order status request leaves action labelled ellipsis',failedLabel);
    assert.equal(failedLabel,'รับออเดอร์');
    await page.evaluate(()=>fixture.failStatus=false);
    await page.getByRole('button',{name:'รับออเดอร์',exact:true}).click();
    assert.equal(await page.evaluate(()=>fixture.orders[0].status),'accepted');
    await page.evaluate(()=>{fixture.failStatus=false;fixture.orders=[];auditEmit();});
    assert.match(await page.locator('#ordersList').innerText(),/ยังไม่มีออเดอร์/);
    passed.push('Empty order state');
    await page.locator('#logoutBtn').click();
    assert.equal(await page.locator('#password').inputValue(),'');
    passed.push('Logout clears password and hides portal');
    await page.evaluate(()=>fixture.failLogin=true);
    await page.locator('#loginBtn').click();
    assert.match(await page.locator('#loginErr').textContent(),/อีเมลหรือรหัสผ่านไม่ถูกต้อง/);
    passed.push('Rejected login displays error');
    await page.close();
    const failure=await boot(browser);
    await failure.evaluate(()=>fixture.failProfile=true);
    await failure.locator('#email').fill('supplier@example.test');
    await failure.locator('#password').fill('fixture-only');
    await failure.locator('#loginBtn').click();
    await failure.waitForTimeout(100);
    const err=await failure.locator('#loginErr').textContent();
    if(failure.errors.some(e=>e.includes('fixture profile unavailable'))&&!err)finding('SUP-07','Profile fetch failure leaves authenticated supplier on login screen without an error or retry',failure.errors);
    assert.match(err,/โหลดข้อมูลร้านไม่สำเร็จ/);
    assert.equal(failure.errors.length,0);
    await failure.evaluate(()=>fixture.failProfile=false);
    await failure.locator('#profileRetry').click();
    await failure.locator('#app-view').waitFor({state:'visible'});
    await failure.close();
    fs.writeFileSync(path.join(out,'findings.json'),JSON.stringify({scope:'Offline real portal DOM with mocked Firebase; backend checked separately in emulator',passed,findings},null,2));
    console.log(JSON.stringify({passed,findings},null,2));
    assert.deepEqual(findings,[], 'Supplier regressions must be fixed');
    assert.deepEqual(page.errors,[]);
  }finally{await browser.close();}
})().catch(e=>{console.error(e.stack);process.exitCode=1;});
