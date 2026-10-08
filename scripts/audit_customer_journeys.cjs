// Historical pre-fix audit (1.2.38). Expected to fail after fixes; NOT a release gate.
// Current acceptance: test_customer_recovery.cjs and test_order_browser.cjs.
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
  // Same public shape reproduced by getShopPublic for a recipe dish with ingredients available.
  {id:'recipe',name:'Recipe dish',price:60,stock:0,category:'อาหาร'},
];
let failKitchen = true, kitchenRequests = [];
let failSlip = true, slipRequests = [], checkoutRequests = [];
const fixtureOrders = [];
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
  if(url.pathname === '/api/createPromptPayOrder') {
    let body='';for await(const part of req)body+=part;
    const checkout=JSON.parse(body);checkoutRequests.push(checkout);
    fixtureOrders.push({id:`fixture-${fixtureOrders.length+1}`,status:"pendingPayment",...checkout});
    res.setHeader('Content-Type','application/json');
    return res.end(JSON.stringify({orderId:fixtureOrders.at(-1).id,pickupLabel:pickupSlots.find(s=>s.id===checkout.pickupSlot)?.label,total:25,finalAmount:25,promptpayId:'0812345678',promptpayName:'ร้านทดสอบ'}));
  }
  if(url.pathname === '/api/verifyPromptPaySlip') {
    let body='';for await(const part of req)body+=part;
    slipRequests.push(JSON.parse(body));
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
  const evidence={version:'1.2.38+55',type:'local browser fixture; no production orders',findings:[]};
  try {
    const page=await browser.newPage({viewport:{width:375,height:812}});
    await page.route('https://**/*',route=>route.abort());
    page.on('dialog',dialog=>dialog.accept());
    const base='http://127.0.0.1:'+server.address().port+'/order/?shop=pickup';
    async function create(phone='0800000000') {
      await page.goto(base);
      await page.locator('[data-id="tea"] .add-btn').click();
      await page.locator('#cartBtn').click();await page.locator('#checkoutBtn').click();
      await page.locator('#pickupHint').filter({hasText:'เวลาประเทศไทย'}).waitFor();
      await page.locator('#customerName').fill('Audit customer');
      await page.locator('#customerPhone').fill(phone);
      await page.locator('#payBtn').click();await page.locator('#payOverlay.open').waitFor();
    }
    // Customer changes their mind before transferring, then presses Cancel.
    await create();
    const before=fixtureOrders.length,requests=[];
    page.on('request',r=>{if(r.url().includes('/api/'))requests.push({url:r.url(),method:r.method()});});
    await page.locator('#payCancelBtn').click();
    await page.locator('#payOverlay.open').waitFor({state:'hidden'});
    assert.equal(requests.filter(r=>r.method==='POST').length,0);
    assert.equal(fixtureOrders.length,before);
    assert.equal(fixtureOrders.at(-1).status,'pendingPayment');
    evidence.findings.push({id:'UX-01',reproduced:true,action:'Cancel on QR payment screen',actual:'No cancellation request sent; pending fixture order remains; cart is empty. Reservation retention corroborated separately in backend tests.',requestsAfterCancel:[...requests],cartCount:await page.locator('#cartCount').textContent()});
    await page.screenshot({path:'.remember/tmp/audit56-cancel.png',fullPage:true});
    // Customer switches to bank and browser reloads before attaching receipt.
    await create();const pending=fixtureOrders.at(-1).id;
    await page.reload();await page.locator('.product-card').first().waitFor();
    assert.equal(await page.locator('#payOverlay.open').count(),0);
    assert.equal(await page.locator('#cartCount').textContent(),'0');
    evidence.findings.push({id:'UX-02',reproduced:true,action:'Reload after QR order created, before slip upload',actual:'No payment/resume screen, empty cart; original order remains pending on server',pendingOrder:pending});
    await page.screenshot({path:'.remember/tmp/audit56-payment-reload.png',fullPage:true});
    // Obvious accidental contact details should be rejected before payment.
    await create('abc');
    assert.equal(checkoutRequests.at(-1).customerPhone,'abc');
    evidence.findings.push({id:'UX-03',reproduced:true,action:'Enter abc as phone then pay',actual:'Checkout submitted and payment QR displayed',submittedPhone:checkoutRequests.at(-1).customerPhone});
    await page.goto(base);
    await page.locator('[data-id="recipe"] .add-btn').waitFor();
    assert.equal(await page.locator('[data-id="recipe"] .add-btn').isDisabled(),true);
    evidence.findings.push({id:'DATA-03',reproduced:true,action:'Open recipe dish using public-menu response shape from emulator',actual:'Add button disabled because public stock is zero; ingredient availability is not represented'});
    fs.writeFileSync('.remember/tmp/audit56-browser-findings.json',JSON.stringify(evidence,null,2));
    console.log(JSON.stringify(evidence,null,2));
  } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;}).finally(()=>server.close());
