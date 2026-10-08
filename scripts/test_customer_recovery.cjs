// Local fixture only: no production orders, login or payment requests.
// PLAYWRIGHT_MODULE may point at an externally installed playwright package.
const { chromium } = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const http = require('node:http'), fs = require('node:fs'), path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(process.env.ORDER_PUBLIC_DIR || 'public');
const products = [
  {id:'rice',name:'ข้าวกะเพราหมูสับไข่ดาวชื่อยาวสำหรับทดสอบ',price:50,stock:10,category:'อาหาร',
    modifierGroups:[{id:'meat',name:'เลือกเนื้อสัตว์',required:true,multiSelect:false,options:[{id:'pork',name:'หมู',priceAdjust:5}]}]},
  {id:'tea',name:'ชาเขียว',price:25,stock:10,category:'เครื่องดื่ม'},
  {id:'water',name:'น้ำดื่ม',price:10,stock:0,category:'เครื่องดื่ม'},
];
let failKitchen = true, kitchenRequests = [];
let failSlip = true, slipRequests = [], checkoutRequests = [];
const fixtureOrders = new Map();
const pickupSlots = [{id:'1791340200000', label:'07/10/2026 09:30–09:45 น.'}, {id:'1791341100000', label:'07/10/2026 09:45–10:00 น.'}];
const server = http.createServer(async (req,res) => {
  const url = new URL(req.url,'http://localhost');
  if(url.pathname === '/api/shopPublic') {
    res.setHeader('Content-Type','application/json');
    const menu = url.searchParams.get('shop') === 'single' ? products.map(p=>({...p,category:'ทั่วไป'})) : products;
    return res.end(JSON.stringify({name:'ร้านทดสอบ',products:menu, ...(url.searchParams.get('shop') === 'pickup' ? {pickup:{enabled:true,slots:pickupSlots}} : {}), ...(url.searchParams.has('table') ?
      {table:{id:url.searchParams.get('table'),name:'A1'},tableOrderMode:'postpaid'} : {})}));
  }
  if(url.pathname === '/api/createTableOrder') {
    let body='';for await(const part of req)body+=part;
    kitchenRequests.push(JSON.parse(body));
    res.setHeader('Content-Type','application/json');res.statusCode=failKitchen?503:200;
    return res.end(JSON.stringify(failKitchen?{error:'ลองใหม่'}:{success:true}));
  }
  if(url.pathname === '/api/customerOrder') {
    let body='';for await(const part of req)body+=part;
    const r=JSON.parse(body),o=fixtureOrders.get(r.orderId);
    res.setHeader('Content-Type','application/json');
    if(!o || o.customerToken!==r.customerToken){res.statusCode=403;return res.end(JSON.stringify({error:'Access denied'}));}
    if(r.action==='cancel'){
      if(o.awaitingReview || o.status!=='pendingPayment'){res.statusCode=409;return res.end(JSON.stringify({error:'Contact shop'}));}
      o.status='cancelled';
    }
    return res.end(JSON.stringify(o));
  }
  if(url.pathname === '/api/createPromptPayOrder') {
    let body='';for await(const part of req)body+=part;
    const checkout=JSON.parse(body);checkoutRequests.push(checkout);
    res.setHeader('Content-Type','application/json');
    const id='web-'+checkout.requestId;
    if(!fixtureOrders.has(id))fixtureOrders.set(id,{orderId:id,status:'pendingPayment',customerToken:checkout.customerToken,pickupLabel:pickupSlots.find(s=>s.id===checkout.pickupSlot)?.label,total:25,finalAmount:25,promptpayId:'0812345678',promptpayName:'ร้านทดสอบ'});
    return res.end(JSON.stringify(fixtureOrders.get(id)));
  }
  if(url.pathname === '/api/verifyPromptPaySlip') {
    let body='';for await(const part of req)body+=part;
    slipRequests.push(JSON.parse(body));
    if(!failSlip){const o=fixtureOrders.get(JSON.parse(body).orderId);if(o)o.awaitingReview=true;}
    res.setHeader('Content-Type','application/json');res.statusCode=failSlip?503:200;
    return res.end(JSON.stringify(failSlip?{success:false,reason:'ลองส่งสลิปอีกครั้ง ไม่ต้องโอนซ้ำ'}:{success:true,awaitingReview:true}));
  }
  let file=path.resolve(root,'.'+url.pathname);
  if(!file.startsWith(root+path.sep)){res.statusCode=403;return res.end();}
  if(url.pathname.endsWith('/'))file=path.join(file,'index.html');
  if(!fs.existsSync(file)){res.statusCode=404;return res.end();}
  let data=fs.readFileSync(file);
  if(file.endsWith('order'+path.sep+'index.html')) {
    data=Buffer.from(data.toString().replace(/<script type="module">[\s\S]*?<\/script>/g,
      '<script type="module">import "/order/js/main.js?v=20261007"; window.__startOrderPage();</script>'));
  }
  res.setHeader('Content-Type',file.endsWith('.js')?'text/javascript; charset=utf-8':file.endsWith('.css')?'text/css; charset=utf-8':file.endsWith('.html')?'text/html; charset=utf-8':'application/octet-stream');
  res.end(data);
});
(async()=>{
  await new Promise(r=>server.listen(0,'127.0.0.1',r));
  const browser=await chromium.launch({headless:true,...(process.env.BROWSER_EXECUTABLE?{executablePath:process.env.BROWSER_EXECUTABLE}:{})});
  try{
    const page=await browser.newPage({viewport:{width:375,height:812}}),errors=[];
    await page.route('https://**/*',route=>route.abort());
    page.on('pageerror',e=>errors.push(e.message));
    page.on('dialog',d=>d.accept());
    const base='http://127.0.0.1:'+server.address().port+'/order/?shop=pickup';
    const prepare=async phone=>{
      await page.goto(base);await page.locator('[data-id="tea"] .add-btn').click();
      await page.locator('#cartBtn').click();await page.locator('#checkoutBtn').click();
      await page.locator('#pickupHint').filter({hasText:'เวลาประเทศไทย'}).waitFor();
      await page.locator('#customerName').fill('Test');await page.locator('#customerPhone').fill(phone);
      await page.locator('#payBtn').click();
    };
    await prepare('abc');
    assert.equal(checkoutRequests.length,0,'invalid phone is stopped before sending');
    await page.locator('#customerPhone').fill('0812345678');await page.locator('#payBtn').click();
    await page.locator('#payOverlay.open').waitFor();
    const original=[...fixtureOrders.values()][0];
    assert.match(original.customerToken,/^[a-f0-9]{64}$/);
    await page.reload();await page.locator('#payOverlay.open').waitFor();
    assert.equal(fixtureOrders.size,1,'refresh resumes same order');
    assert.ok((await page.locator('#payOrderId').textContent()).includes(original.orderId));
    await page.locator('#payCloseBtn').click();await page.locator('#resumePaymentBtn').click();
    await page.locator('#payOverlay.open').waitFor();
    await page.locator('#payCancelBtn').click();await page.locator('#payOverlay.open').waitFor({state:'hidden'});
    assert.equal(original.status,'cancelled','cancel reaches server');
    await page.reload();await page.locator('.product-card').first().waitFor();
    assert.equal(await page.locator('#resumePaymentBtn').isVisible(),false);
    // Drop the first response AFTER the fixture server commits the request.
    await page.route('**/api/createPromptPayOrder',async route=>{await route.fetch();await route.abort();});
    await prepare('+61 412 345 678');
    await page.waitForFunction(()=>document.getElementById('payBtn').disabled===false);
    assert.equal(fixtureOrders.size,2);
    await page.unroute('**/api/createPromptPayOrder');
    await page.reload();await page.locator('#payOverlay.open').waitFor();
    assert.equal(fixtureOrders.size,2,'ambiguous response retry does not create another order');
    const second=[...fixtureOrders.values()][1];second.awaitingReview=true;
    await page.reload();await page.locator('#payOverlay.open').waitFor();
    assert.equal(await page.locator('#payCancelBtn').isVisible(),false);
    assert.equal(await page.locator('#payQrBox').isVisible(),false,'never suggest a second transfer after slip upload');
    second.status='paid';
    await page.reload();await page.locator('#payOverlay.open').waitFor();
    assert.equal(await page.locator('#paySlipBtn').isVisible(),false);
    await page.locator('#payCloseBtn').click();
    assert.equal(await page.locator('#resumePaymentBtn').isVisible(),false);
    assert.deepEqual(errors,[]);
    console.log('PASS phone validation, secure local reference, payment reload, server cancellation, lost-response idempotency, review/paid recovery');
  }finally{await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;}).finally(()=>server.close());
