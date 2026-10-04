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
const server = http.createServer(async (req,res) => {
  const url = new URL(req.url,'http://localhost');
  if(url.pathname === '/api/shopPublic') {
    res.setHeader('Content-Type','application/json');
    const menu = url.searchParams.get('shop') === 'single' ? products.map(p=>({...p,category:'ทั่วไป'})) : products;
    return res.end(JSON.stringify({name:'ร้านทดสอบ',products:menu, ...(url.searchParams.has('table') ?
      {table:{id:url.searchParams.get('table'),name:'A1'},tableOrderMode:'postpaid'} : {})}));
  }
  if(url.pathname === '/api/createTableOrder') {
    let body='';for await(const part of req)body+=part;
    kitchenRequests.push(JSON.parse(body));
    res.setHeader('Content-Type','application/json');res.statusCode=failKitchen?503:200;
    return res.end(JSON.stringify(failKitchen?{error:'ลองใหม่'}:{success:true}));
  }
  if(url.pathname === '/api/createPromptPayOrder') {
    for await(const part of req) {} // Fixture only: no real payment created.
    res.setHeader('Content-Type','application/json');
    return res.end(JSON.stringify({orderId:'fixture-order',total:25,finalAmount:25,promptpayId:'0812345678',promptpayName:'ร้านทดสอบ'}));
  }
  let file=path.resolve(root,'.'+url.pathname);
  if(!file.startsWith(root+path.sep)){res.statusCode=403;return res.end();}
  if(url.pathname.endsWith('/'))file=path.join(file,'index.html');
  if(!fs.existsSync(file)){res.statusCode=404;return res.end();}
  let data=fs.readFileSync(file);
  if(file.endsWith('order'+path.sep+'index.html')) {
    data=Buffer.from(data.toString().replace(/<script type="module">[\s\S]*?<\/script>/g,
      '<script type="module">import "/order/js/main.js?v=20261005"; window.__startOrderPage();</script>'));
  }
  res.setHeader('Content-Type',file.endsWith('.js')?'text/javascript; charset=utf-8':file.endsWith('.css')?'text/css; charset=utf-8':file.endsWith('.html')?'text/html; charset=utf-8':'application/octet-stream');
  res.end(data);
});
(async()=>{
  await new Promise(r=>server.listen(0,'127.0.0.1',r));
  const browser=await chromium.launch({headless:true, ...(process.env.BROWSER_EXECUTABLE ? {executablePath:process.env.BROWSER_EXECUTABLE}: {})});
  try {
    const page=await browser.newPage({viewport:{width:375,height:812}});
    await page.route('https://**/*',route=>route.abort());
    const errors=[];page.on('pageerror',e=>errors.push(e.message));
    const base=`http://127.0.0.1:${server.address().port}/order/?shop=fixture&table=t1`;
    await page.goto(base);
    await page.locator('.product-card').first().waitFor();
    for(const width of [320,375,414]) {
      await page.setViewportSize({width,height:812});
      const boxes=await page.locator('.product-card').evaluateAll(nodes=>nodes.map(n=>{const b=n.getBoundingClientRect();return {x:b.x,y:b.y,width:b.width};}));
      assert.equal(boxes[0].y,boxes[1].y,'two items per mobile row');
      assert.ok(boxes[2].y>boxes[0].y);
      assert.ok(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),'no horizontal overflow');
    }
    await page.setViewportSize({width:375,height:812});
    await page.getByRole('button',{name:'เครื่องดื่ม',exact:true}).click();
    assert.equal(await page.locator('.product-card').count(),2);
    await page.locator('#productSearch').fill('ชา');
    assert.equal(await page.locator('.product-card').count(),1);
    await page.locator('#productSearch').fill('ไม่พบชื่อ');
    await page.locator('.catalog-empty').waitFor();
    await page.locator('#productSearch').fill('');
    await page.getByRole('button',{name:'ทั้งหมด',exact:true}).click();
    const addRice=async(note)=>{
      await page.locator('[data-id="rice"] .add-btn').click();
      assert.ok(await page.locator('#sheetPrimary').isDisabled(),'required selection enforced');
      await page.locator('[data-o="pork"]').click();
      await page.locator('#sheetNote').fill(note);
      await page.locator('#sheetPrimary').click();
    };
    await addRice('ไม่เผ็ด');await addRice('เผ็ดมาก');
    assert.equal(await page.locator('#cartCount').textContent(),'2');
    await page.reload();await page.locator('.product-card').first().waitFor();
    assert.equal(await page.locator('#cartCount').textContent(),'2','draft survives refresh');
    await page.locator('#cartBtn').click();
    assert.equal(await page.locator('#cartItems .cart-item').count(),2,'distinct preparation notes');
    await page.locator('#checkoutBtn').click();
    await page.locator('#kitchenSendBtn').click();
    await page.locator('#kitchenStatus.err').waitFor();
    assert.equal(await page.locator('#cartCount').textContent(),'2','failure retains cart');
    failKitchen=false;
    await page.locator('#kitchenSendBtn').click();
    await page.locator('#kitchenDone:not(.hidden)').waitFor();
    assert.equal(await page.locator('#cartCount').textContent(),'0','successful send clears all configured lines');
    assert.deepEqual(kitchenRequests[1].items.map(i=>i.notes),['ไม่เผ็ด','เผ็ดมาก']);
    assert.deepEqual(kitchenRequests[1].items[0].optionIds,['pork']);
    await page.reload();await page.locator('.product-card').first().waitFor();
    assert.equal(await page.locator('#cartCount').textContent(),'0','sent lines never return after reload');
    await page.locator('[data-id="tea"] .add-btn').click();
    await page.goto(base.replace('table=t1','table=t2'));await page.locator('.product-card').first().waitFor();
    assert.equal(await page.locator('#cartCount').textContent(),'0','table drafts stay separate');
    await page.screenshot({path:'.remember/tmp/order-mobile-two-columns.png',fullPage:true});
    await page.goto(base.replace('shop=fixture&table=t1','shop=single'));await page.locator('.product-card').first().waitFor();
    assert.ok(await page.locator('#catBar').isVisible(),'single-category shop still shows categories');
    assert.equal(await page.locator('.cat-chip').count(),2);
    await page.locator('[data-id="tea"] .add-btn').click();
    await page.locator('#cartBtn').click();await page.locator('#checkoutBtn').click();
    await page.locator('#customerName').fill('fixture');await page.locator('#customerPhone').fill('0800000000');
    await page.locator('#payBtn').click();await page.locator('#payOverlay.open').waitFor();
    assert.equal(await page.locator('#cartCount').textContent(),'0','accepted takeaway order clears draft');
    await page.reload();await page.locator('.product-card').first().waitFor();
    assert.equal(await page.locator('#cartCount').textContent(),'0','accepted payment order is not restored as a new cart');
    await page.setViewportSize({width:1024,height:800});
    assert.equal(await page.locator('#products').evaluate(n=>getComputedStyle(n).gridTemplateColumns.split(' ').length)>=3,true);
    assert.deepEqual(errors,[]);
    console.log('PASS mobile grid 320/375/414 and desktop, categories/search, required choices, notes, refresh, kitchen failure/success, table isolation and takeaway draft clearing');
  } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;}).finally(()=>server.close());
