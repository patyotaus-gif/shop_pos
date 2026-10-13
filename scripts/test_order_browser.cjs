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
const bundle={id:'tea-water',revision:'b1',name:'ชาคู่น้ำ',priceMinor:5000,maxSets:1,
  components:[{productId:'tea',quantity:2,unitPriceMinor:2500},{productId:'water',quantity:1,unitPriceMinor:1000}]};
const bundleQuote=checkout=>checkout.shopId==='bundles' && checkout.items.some(i=>i.productId==='tea'&&i.quantity>=2)&&checkout.items.some(i=>i.productId==='water'&&i.quantity>=1)
  ? [{...bundle,sets:1,discountMinor:1000}]:[];
const server = http.createServer(async (req,res) => {
  const url = new URL(req.url,'http://localhost');
  if(url.pathname === '/api/shopPublic') {
    res.setHeader('Content-Type','application/json');
    const menu = url.searchParams.get('shop') === 'weighed' ? [{id:'weighed',name:'ข้าวชั่ง',price:80,stock:2.5,isWeighed:true,unit:'กก.',category:'อาหาร'}] : url.searchParams.get('shop') === 'single' ? products.map(p=>({...p,category:'ทั่วไป'})) : url.searchParams.get('shop')==='bundles'?products.map(p=>({...p,stock:10})):products;
    return res.end(JSON.stringify({name:'ร้านทดสอบ',products:menu,bundles:url.searchParams.get('shop')==='bundles'?[bundle]:[], ...(url.searchParams.get('shop') === 'pickup' ? {pickup:{enabled:true,slots:pickupSlots}} : {}), ...(url.searchParams.has('table') ?
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
    const checkout=JSON.parse(body);
    res.setHeader('Content-Type','application/json');
    if(checkout.action==='quoteGifts') {
      const qty=checkout.items.filter(i=>i.productId==='tea').reduce((s,i)=>s+i.quantity,0);
      return res.end(JSON.stringify({bundles:bundleQuote(checkout),buyGet:checkout.shopId==='coupons' && qty>=2 ?
        [{promotionId:'tea',revision:'test',productId:'water',productName:'น้ำดื่ม',quantity:1}] : []}));
    }
    if(checkout.action==='quoteCoupon') {
      if(checkout.couponCode!=='SAVE10') {res.statusCode=400;return res.end(JSON.stringify({error:'คูปองหมดอายุแล้ว'}));}
      const subtotalMinor=checkout.items.reduce((sum,i)=>sum+products.find(p=>p.id===i.productId).price*i.quantity*100,0)-bundleQuote(checkout).reduce((s,b)=>s+b.discountMinor,0);
      return res.end(JSON.stringify({code:'SAVE10',subtotalMinor,discountMinor:1000,totalMinor:subtotalMinor-1000}));
    }
    checkoutRequests.push(checkout);
    const id='web-'+checkout.requestId;
    const coupon=checkout.couponCode ? {coupon:{code:checkout.couponCode,...checkout.couponQuote},subtotal:checkout.couponQuote.subtotalMinor/100,discount:10,total:checkout.couponQuote.subtotalMinor/100-10,finalAmount:checkout.couponQuote.subtotalMinor/100-10} : {};
    if(!fixtureOrders.has(id))fixtureOrders.set(id,{orderId:id,status:'pendingPayment',customerToken:checkout.customerToken,buyGet:checkout.buyGetQuote,bundles:checkout.bundleQuote,pickupLabel:pickupSlots.find(s=>s.id===checkout.pickupSlot)?.label,total:25,finalAmount:25,...coupon,promptpayId:'0812345678',promptpayName:'ร้านทดสอบ'});
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
      '<script type="module">import "/order/js/main.js?v=20261013b"; window.__startOrderPage();</script>'));
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
    await page.locator('#pickupHint').filter({hasText:'ร้านยังไม่เปิด'}).waitFor();
    await page.locator('#payBtn').click();await page.locator('#payOverlay.open').waitFor();
    assert.equal(await page.locator('#cartCount').textContent(),'0','accepted takeaway order clears draft');
    const png=await page.screenshot();
    const slip={name:'fixture.png',mimeType:'image/png',buffer:png};
    await page.locator('#slipFileInput').setInputFiles(slip);
    await page.locator('#paySlipStatus.err').waitFor();
    assert.ok((await page.locator('#paySlipStatus').textContent()).includes('ไม่ต้องโอนซ้ำ'));
    assert.equal(await page.locator('#paySlipBtn').isEnabled(),true);
    assert.equal(slipRequests[0].orderId,'web-'+checkoutRequests[0].requestId);
    assert.ok(slipRequests[0].slipBase64.startsWith('data:image/jpeg;base64,/9j/'),'PNG compressed to JPEG');
    failSlip=false;
    await page.locator('#slipFileInput').setInputFiles(slip);
    await page.waitForURL('**/order/success/?order=web-*&review=1');
    assert.ok((await page.locator('h1').textContent()).includes('รอร้านยืนยัน'));
    assert.ok((await page.locator('.note').textContent()).includes('ไม่ต้องโอนซ้ำ'));
    assert.equal(slipRequests.length,2,'same file can be retried');
    await page.goto(base.replace('shop=fixture&table=t1','shop=single'));
    await page.reload();await page.locator('.product-card').first().waitFor();
    assert.equal(await page.locator('#cartCount').textContent(),'0','accepted payment order is not restored as a new cart');
    await page.setViewportSize({width:1024,height:800});
    assert.equal(await page.locator('#products').evaluate(n=>getComputedStyle(n).gridTemplateColumns.split(' ').length)>=3,true);
    await page.setViewportSize({width:320,height:640});
    await page.goto(base.replace('shop=fixture&table=t1','shop=pickup'));
    await page.locator('[data-id="tea"] .add-btn').click();
    await page.locator('#cartBtn').click();await page.locator('#checkoutBtn').click();
    await page.locator('#pickupHint').filter({hasText:'เวลาประเทศไทย'}).waitFor();
    assert.ok(await page.locator('#pickupSlot').isDisabled(), 'ASAP picks first available slot');
    assert.equal(await page.locator('#pickupSlot').inputValue(),pickupSlots[0].id);
    await page.locator('#pickupMode').selectOption('scheduled');
    await page.locator('#pickupSlot').selectOption(pickupSlots[1].id);
    const modalBox = await page.locator('#modal').boundingBox();
    assert.ok(modalBox.y >= 0 && modalBox.y + modalBox.height <= 640, 'pickup form fits small mobile height');
    assert.ok(await page.locator('#modal').evaluate(n=>n.scrollWidth<=n.clientWidth), 'no pickup form horizontal overflow');
    await page.screenshot({path:'.remember/tmp/release55-pickup-form.png'});
    await page.locator('#customerName').fill('pickup fixture');await page.locator('#customerPhone').fill('0800000000');
    await page.locator('#payBtn').click();await page.locator('#payOverlay.open').waitFor();
    assert.equal(checkoutRequests.at(-1).pickupSlot,pickupSlots[1].id);
    assert.equal(checkoutRequests.at(-1).pickupMode,'scheduled');
    assert.match(checkoutRequests.at(-1).requestId,/^[a-f0-9-]{36}$/);
    assert.ok((await page.locator('#payPickup').textContent()).includes('09:45–10:00'));
    await page.screenshot({path:'.remember/tmp/release55-pickup-payment.png'});
    await page.locator('#slipFileInput').setInputFiles(slip);
    await page.waitForURL('**/order/success/**');
    assert.ok((await page.locator('#pickup').textContent()).includes('09:45–10:00'));
    await page.goto(base.replace('shop=fixture&table=t1','shop=coupons'));
    await page.locator('[data-id="tea"] .add-btn').click();
    await page.evaluate(async()=>{const cart=await import('/order/js/cart.js?v=20261013stock');cart.addOne('tea');});
    await page.locator('#cartBtn').click();await page.locator('#checkoutBtn').click();
    await page.locator('#couponCode').fill('INVALID');await page.locator('#couponApply').click();
    await page.locator('#giftStatus').filter({hasText:'ของแถม: น้ำดื่ม'}).waitFor();
    await page.locator('#couponStatus').filter({hasText:'หมดอายุ'}).waitFor();
    await page.locator('#couponCode').fill('save10');await page.locator('#couponApply').click();
    await page.locator('#couponStatus').filter({hasText:'จองสิทธิ์'}).waitFor();
    assert.equal(await page.locator('#modalTotal').textContent(),'฿40.00');
    await page.evaluate(async()=>{const cart=await import('/order/js/cart.js?v=20261013stock');cart.addOne('tea');});
    await page.locator('#couponStatus').filter({hasText:'ตะกร้าเปลี่ยน'}).waitFor();
    assert.equal(await page.evaluate(async()=>{try{(await import('/order/js/buy-get.js?v=20261013b')).giftPayload();return false;}catch{return true;}}),true);
    await page.locator('#giftRefresh').click();await page.locator('#giftStatus').filter({hasText:'ของแถม: น้ำดื่ม'}).waitFor();
    assert.equal(await page.evaluate(async()=>{try{(await import('/order/js/coupons.js?v=20261013b')).couponPayload();return false;}catch{return true;}}),true);
    await page.locator('#couponApply').click();await page.locator('#couponStatus').filter({hasText:'จองสิทธิ์'}).waitFor();
    assert.equal(await page.locator('#modalTotal').textContent(),'฿65.00');
    assert.ok(await page.locator('#modal').evaluate(n=>n.scrollWidth<=n.clientWidth),'coupon form fits 320px');
    await page.locator('#customerName').fill('Coupon test');await page.locator('#customerPhone').fill('0800000000');
    await page.locator('#payBtn').click();await page.locator('#payOverlay.open').waitFor();
    assert.equal(checkoutRequests.at(-1).couponCode,'SAVE10');
    assert.equal(checkoutRequests.at(-1).buyGetQuote[0].quantity,1);
    assert.match(await page.locator('#payGifts').textContent(),/น้ำดื่ม/);
    assert.equal(checkoutRequests.at(-1).couponQuote.discountMinor,1000);
    assert.match(await page.locator('#payCouponNote').textContent(),/SAVE10/);
    await page.reload();await page.locator('#payOverlay.open').waitFor();
    assert.match(await page.locator('#payCouponNote').textContent(),/SAVE10/,'resume keeps coupon breakdown');
    assert.match(await page.locator('#payGifts').textContent(),/น้ำดื่ม/,'resume keeps free gifts');
    await page.goto(base.replace('shop=fixture&table=t1','shop=bundles'));
    await page.locator('.bundle-card button').click();
    assert.ok(await page.locator('.bundle-card button').isDisabled(),'maximum sets cannot be added twice');
    await page.locator('#cartBtn').click();await page.locator('#checkoutBtn').click();
    await page.locator('#giftStatus').filter({hasText:'ชาคู่น้ำ'}).waitFor();
    assert.equal(await page.locator('#modalTotal').textContent(),'฿50.00');
    await page.locator('#couponCode').fill('SAVE10');await page.locator('#couponApply').click();
    await page.locator('#couponStatus').filter({hasText:'จองสิทธิ์'}).waitFor();
    assert.equal(await page.locator('#modalTotal').textContent(),'฿40.00');
    await page.locator('#couponClear').click();assert.equal(await page.locator('#modalTotal').textContent(),'฿50.00','clearing coupon keeps bundle savings');
    await page.locator('#couponCode').fill('SAVE10');await page.locator('#couponApply').click();
    await page.locator('#couponStatus').filter({hasText:'จองสิทธิ์'}).waitFor();
    await page.locator('#customerName').fill('Bundle test');await page.locator('#customerPhone').fill('0800000000');
    await page.locator('#payBtn').click();await page.locator('#payOverlay.open').waitFor();
    assert.equal(checkoutRequests.at(-1).bundleQuote[0].discountMinor,1000);
    assert.equal(checkoutRequests.at(-1).couponQuote.subtotalMinor,5000);
    await page.reload();await page.locator('#payOverlay.open').waitFor();
    assert.match(await page.locator('#payGifts').textContent(),/ชาคู่น้ำ/,'resume keeps bundle breakdown');
    assert.ok(!/NaN/.test(await page.locator('#payCouponNote').textContent()));
    await page.goto(base.replace('shop=fixture&table=t1','shop=weighed'));
    await page.locator('[data-id="weighed"] .add-btn').click();
    await page.locator('#weightQty').fill('0.250');
    await page.locator('#sheetPrimary').click();
    await page.locator('#cartBtn').click();
    assert.match(await page.locator('#cartItems').textContent(),/0.25 กก./);
    assert.equal(await page.locator('#modalTotal').textContent(),'฿20.00');
    await page.reload();
    await page.locator('#cartBtn').click();
    assert.equal(await page.locator('#modalTotal').textContent(),'฿20.00');
    await page.locator('#cartItems input').fill('0.375');
    await page.locator('#cartItems input').press('Tab');
    assert.equal(await page.locator('#modalTotal').textContent(),'฿30.00');
    await page.locator('#cartItems input').click();
    await page.waitForTimeout(350); // Finish the drawer transition for its screenshot.
    await page.screenshot({path:'.remember/tmp/inventory-weighted-web.png'});
    assert.deepEqual(errors,[]);
    console.log('PASS mobile grid, categories/search, choices, notes, drafts, kitchen retry, slips, coupons, gifts, bundles and payment recovery');
  } finally {await browser.close();}
})().catch(e=>{console.error(e);process.exitCode=1;}).finally(()=>server.close());
