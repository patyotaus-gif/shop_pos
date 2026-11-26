// Browser evidence for the real homepage. All requests are served from disk;
// external hosts are blocked. No account, shop data, or payment services used.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE);
const root = path.resolve(__dirname, '../public');
const output = process.env.HOME_STORY_OUTPUT || path.resolve(__dirname, '../.remember/tmp/home-story');
const mime = {'.html':'text/html; charset=utf-8','.js':'text/javascript','.css':'text/css','.png':'image/png','.webp':'image/webp','.svg':'image/svg+xml'};
const origin = 'https://pokpok-home.test';
const fonts = [400,600,700].map((weight,i) => ({weight,data:fs.readFileSync(path.resolve(__dirname, `../assets/fonts/IBMPlexSansThai-${['Regular','SemiBold','Bold'][i]}.ttf`)).toString('base64')}));

async function local(route) {
  const url = new URL(route.request().url());
  if (url.origin !== origin) return route.abort();
  let file = path.resolve(root, '.' + decodeURIComponent(url.pathname));
  assert.ok(file === root || file.startsWith(root + path.sep));
  if (fs.existsSync(file) && fs.statSync(file).isDirectory()) file = path.join(file, 'index.html');
  if (!fs.existsSync(file)) return route.fulfill({status:404,body:''});
  return route.fulfill({body:fs.readFileSync(file),contentType:mime[path.extname(file)] || 'application/octet-stream'});
}
async function load(page, suffix = '/') {
  await page.goto(origin + suffix);
  await page.evaluate(async fonts => {
    for (const {weight,data} of fonts) { const font = new FontFace('IBM Plex Sans Thai', `url(data:font/ttf;base64,${data})`, {weight:String(weight)}); document.fonts.add(await font.load()); }
    await document.fonts.ready;
  }, fonts);
}
async function capture(page, name) {
  await page.evaluate(() => Promise.all([...document.querySelectorAll('.masthead-motion, .masthead-motion *')].flatMap(e => e.getAnimations()).map(a => a.finished.catch(() => {}))));
  await page.evaluate(() => Promise.all([...document.querySelectorAll('.device-model')].flatMap(e => e.getAnimations()).map(a => a.finished.catch(() => {}))));
  await page.screenshot({path:path.join(output, name + '.png')});
}
async function settleDevices(page) {
  await page.evaluate(() => Promise.all([...document.querySelectorAll('.device-model')].flatMap(e => e.getAnimations()).map(a => a.finished.catch(() => {}))));
}
async function mouseSwipe(page, dx, dy = 0) {
  await settleDevices(page);
  const box = await page.locator('.device-model[data-position="center"]').boundingBox();
  const x = box.x + box.width / 2, y = box.y + box.height / 2;
  await page.mouse.move(x,y); await page.mouse.down();
  await page.mouse.move(x+dx,y+dy,{steps:12}); await page.mouse.up();
  await settleDevices(page);
}
async function touchSwipe(page, session, dx, dy = 0, cancel = false) {
  await settleDevices(page);
  const box = await page.locator('.device-model[data-position="center"]').boundingBox();
  const x = box.x + box.width / 2, y = box.y + box.height / 2;
  const point = (px,py) => [{x:px,y:py,id:1,radiusX:4,radiusY:4,force:1}];
  await session.send('Input.dispatchTouchEvent',{type:'touchStart',touchPoints:point(x,y)});
  for (let i=1;i<=8;i++) {
    await session.send('Input.dispatchTouchEvent',{type:'touchMove',touchPoints:point(x+dx*i/8,y+dy*i/8)});
    await page.waitForTimeout(20);
  }
  await session.send('Input.dispatchTouchEvent',{type:cancel?'touchCancel':'touchEnd',touchPoints:[]});
  await settleDevices(page);
}
(async () => {
  fs.mkdirSync(output, {recursive:true});
  const browser = await chromium.launch({headless:true,executablePath:process.env.BROWSER_EXECUTABLE});
  const errors = [];
  let checks = 0;
  try {
    const context = await browser.newContext({colorScheme:'light'});
    await context.route('**/*', local);
    const page = await context.newPage();
    page.on('pageerror', e => errors.push(e.message));
    for (const width of [320,360,390,768,1024,1280,1440,1920]) {
      await page.setViewportSize({width,height:960});
      await load(page);
      assert.equal(await page.locator('h1').count(), 1);
      assert.equal(await page.locator('.device-stage img').evaluateAll(images => images.length === 12 && images.every(i => i.complete && i.naturalWidth > 0)), true);
      assert.equal(await page.locator('.device-model').evaluateAll(models => models.every(model => {
        const frame = model.querySelector('.device-hardware');
        const shell = model.querySelector('.device-shell');
        const ratio = model.dataset.model === 'tablet' ? frame.naturalHeight / frame.naturalWidth : frame.naturalWidth / frame.naturalHeight;
        return Math.abs(shell.offsetWidth / shell.offsetHeight - ratio) < .01;
      })), true, `Device photo proportions ${width}`);
      assert.equal(await page.locator('.device-picker, .device-description').count(), 0);
      assert.equal(await page.locator('.device-glass').evaluateAll(screens => screens.every(s => s.textContent.trim() === '' && getComputedStyle(s).backgroundColor === 'rgb(122, 31, 43)')), true);
      const overflow = await page.evaluate(() => document.documentElement.scrollWidth > innerWidth);
      if (overflow) {
        console.error(await page.evaluate(() => ({width:innerWidth,scroll:document.documentElement.scrollWidth,elements:[...document.querySelectorAll('body *')].map(e=>({tag:e.tagName,cls:e.className,left:e.getBoundingClientRect().left,right:e.getBoundingClientRect().right})).filter(e=>e.left<0||e.right>innerWidth)})));
        await page.screenshot({path:path.join(output, `overflow-${width}.png`)});
      }
      assert.equal(overflow, false, `Overflow ${width}`);
      const cta = await page.locator('.cinematic-hero .btn-lg').boundingBox();
      assert.ok(cta.y + cta.height <= 960, `Hero action visible ${width}`);
      for (const control of await page.locator('.business-picker button, .device-model').all()) {
        const box = await control.boundingBox(); assert.ok(box.height >= 44 && box.width >= 44);
      }
      if ([390,768,1280,1440].includes(width)) {
        await capture(page, `hero-${width}`);
        await page.locator('.cinematic-hero').screenshot({path:path.join(output, `hero-full-${width}.png`)});
      }
      // The devices themselves change position, not only a text label or screen.
      const tabletPose = await page.locator('.device-tablet').evaluate(e => getComputedStyle(e).transform);
      await page.locator('[data-model="phone"]').click();
      assert.equal(await page.locator('[data-model="phone"]').getAttribute('data-position'), 'center');
      await page.waitForFunction(pose => getComputedStyle(document.querySelector('.device-tablet')).transform !== pose, tabletPose);
      await page.evaluate(() => Promise.all([...document.querySelectorAll('.device-model')].flatMap(e => e.getAnimations()).map(a => a.finished.catch(() => {}))));
      assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true, `Phone overflow ${width}`);
      if ([390,1280,1440].includes(width)) await capture(page, `device-phone-${width}`);
      await page.locator('[data-model="kiosk"]').focus(); await page.keyboard.press('Enter');
      assert.equal(await page.locator('[data-model="kiosk"]').getAttribute('data-position'), 'center');
      assert.equal(await page.locator('.device-model[aria-pressed="true"]').count(), 1);
      assert.match(await page.locator('.device-sr-status').innerText(), /ยังไม่เปิดให้ใช้งาน/);
      assert.match(await page.locator('.hero-desc').innerText(), /แนวคิดจอกลางหน้าร้าน/);
      await page.evaluate(() => Promise.all([...document.querySelectorAll('.device-model')].flatMap(e => e.getAnimations()).map(a => a.finished.catch(() => {}))));
      assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true, `Kiosk overflow ${width}`);
      assert.equal(await page.locator('.device-kiosk').evaluate(e => Math.abs(e.querySelector('.device-shell').getBoundingClientRect().top - e.getBoundingClientRect().top) < 3), true, `Kiosk screen must start at top of its focus target ${width}`);
      if ([390,768,1280,1440].includes(width)) {
        await capture(page, `device-kiosk-${width}`);
        await page.locator('.cinematic-hero').screenshot({path:path.join(output, `kiosk-full-${width}.png`)});
      }
      await page.keyboard.press('ArrowLeft');
      assert.equal(await page.locator('[data-model="tablet"]').getAttribute('aria-pressed'), 'true');
      assert.equal(await page.locator('[data-model="tablet"]').evaluate(e => e === document.activeElement), true);
      await mouseSwipe(page, -100);
      assert.equal(await page.locator('[data-model="kiosk"]').getAttribute('aria-pressed'), 'true');
      await mouseSwipe(page, 100);
      assert.equal(await page.locator('[data-model="tablet"]').getAttribute('aria-pressed'), 'true');
      for (const type of ['retail','restaurant']) {
        const button = page.locator(`[data-business="${type}"]`);
        await button.focus();
        await page.keyboard.press('Enter');
        const panel = page.locator(`#journey-${type}`);
        assert.equal(await button.getAttribute('aria-pressed'), 'true');
        assert.equal(await page.locator('[data-journey]:visible').count(), 1);
        const shots = panel.locator('.story-shot img');
        const expected = type === 'retail' ? ['retail-checkout-1.2.84','retail-payment-1.2.84','retail-receipt-1.2.84'] : ['restaurant-table-1.2.84','kitchen-1.2.83','restaurant-bill-1.2.84'];
        assert.equal(await shots.count(), 3);
        for (let i=0; i<expected.length; i++) {
          const shot = shots.nth(i);
          await shot.scrollIntoViewIfNeeded();
          await shot.evaluate(img => img.decode());
          assert.ok((await shot.getAttribute('src')).includes('/' + expected[i] + '.'));
          const selected = await shot.evaluate(img => new URL(img.currentSrc).pathname);
          const mobile = (type === 'retail' && i === 0 && width <= 600) || (type === 'restaurant' && i !== 1 && width <= 767);
          assert.equal(selected, '/screens/story/' + (mobile ? expected[i].replace('-1.2.', '-mobile-1.2.') : expected[i]) + '.webp');
          const full = await panel.locator('.story-shot').nth(i).getAttribute('href');
          assert.ok(fs.existsSync(path.join(root, full)));
        }
        assert.equal(await panel.locator('a[href="/#download"]').isVisible(), true);
        assert.equal(await panel.locator(`a[href="/pricing/?shop=${type}"]`).isVisible(), true);
        const second = panel.locator('article').nth(1);
        const copy = await second.locator('.chapter-copy').boundingBox();
        const image = await second.locator('figure').boundingBox();
        assert.ok(width >= 768 ? image.x < copy.x : copy.y < image.y);
        if ([390,768,1280,1440].includes(width)) {
          await panel.screenshot({style: '.site-nav, .skip-link {visibility:hidden!important}',path:path.join(output, `journey-${type}-${width}.png`)});
        }
      }
      assert.equal(await page.locator('.feature-details').evaluate(d => d.open), width >= 900);
      if (width === 390) {
        await page.locator('.feature-details summary').click();
        assert.equal(await page.locator('.feature-details .feature-card:visible').count(), 4);
      }
      assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true, `Switched layout overflow ${width}`);
      checks++;
    }
    await page.setViewportSize({width:1440,height:960});
    await load(page);
    const initialPose = await page.locator('.device-tablet').evaluate(e => getComputedStyle(e).transform);
    await page.evaluate(() => scrollTo({top:400,behavior:'instant'}));
    await page.waitForFunction(pose => getComputedStyle(document.querySelector('.device-tablet')).transform !== pose, initialPose);
    for (const [hash,type] of [['tour-manage','restaurant'],['retail-receipt','retail']]) {
      await load(page, '/#' + hash);
      assert.equal(await page.locator('#' + hash).isVisible(), true);
      assert.equal(await page.locator(`[data-business="${type}"]`).getAttribute('aria-pressed'), 'true');
    }
    checks++;

    await load(page, '/#retail-report');
    assert.ok(await page.locator('#retail-report img').isVisible());
    await load(page, '/#retail-sale');
    await page.locator('[data-business="restaurant"]').click();
    await page.locator('.hero-ctas a[href="#retail-sale"]').click();
    await page.waitForFunction(() => { const rect = document.getElementById('retail-sale').getBoundingClientRect(); return rect.width > 0 && rect.height > 0 && rect.top >= -8 && rect.top < innerHeight / 2; });

    for (const type of ['restaurant','retail']) {
      await load(page);
      await page.locator(`[data-business="${type}"]`).click();
      await page.locator(`#journey-${type} a[href^="/pricing/"]`).click();
      assert.equal(await page.locator(`#type-${type}`).getAttribute('aria-pressed'), 'true');
    }
    await load(page);
    await page.locator('#journey-restaurant a[href="/#download"]').click();
    assert.ok(page.url().endsWith('/#download'));
    assert.equal(await page.locator('#download').isVisible(), true);
    // Resize and live OS setting changes must reveal all content without motion.
    await page.emulateMedia({reducedMotion:'reduce'});
    assert.equal(await page.locator('.story-shot:visible').count(), 3);
    assert.equal(await page.locator('.device-tablet').evaluate(e => getComputedStyle(e).transitionDuration), '0s');
    await load(page); await capture(page, 'reduced-motion-1440');
    await page.locator('[data-model="kiosk"]').click();
    assert.equal(await page.locator('[data-model="kiosk"]').getAttribute('data-position'), 'center');
    const reducedPose = await page.locator('.device-kiosk').evaluate(e => getComputedStyle(e).transform);
    await page.evaluate(() => scrollTo({top:200,behavior:'instant'}));
    assert.equal(await page.locator('.device-kiosk').evaluate(e => getComputedStyle(e).transform), reducedPose);
    await page.emulateMedia({reducedMotion:'no-preference'});
    await page.setViewportSize({width:1440,height:600});
    checks++;

    // Full screenshot remains available even if an optimized preview fails.
    const blockedContext = await browser.newContext({viewport:{width:1440,height:960},colorScheme:'light'});
    await blockedContext.route('**/*', route => route.request().url().includes('/screens/story/kitchen-1.2.83.webp') ? route.abort() : local(route));
    const blocked = await blockedContext.newPage();
    blocked.on('pageerror', e => errors.push(e.message));
    await load(blocked, '/#tour-manage');
    const failed = blocked.locator('#tour-manage img');
    await failed.scrollIntoViewIfNeeded();
    await failed.evaluate(i => i.decode().catch(() => {}));
    assert.equal(await failed.evaluate(i => i.naturalWidth), 0);
    assert.ok(await failed.getAttribute('alt'));
    assert.match(await blocked.locator('#tour-manage a').getAttribute('href'), /kitchen-1.2.83-tablet.png$/);
    await blockedContext.close();
    checks++;

    const noJs = await browser.newContext({javaScriptEnabled:false,viewport:{width:390,height:960},colorScheme:'light'});
    await noJs.route('**/*', local);
    const fallback = await noJs.newPage(); await fallback.goto(origin + '/');
    assert.equal(await fallback.locator('.story-chapter').count(), 6);
    assert.equal(await fallback.locator('.story-shot:visible').count(), 6);
    assert.equal(await fallback.locator('.business-picker').isVisible(), false);
    assert.equal(await fallback.locator('[data-restaurant-pricing]').getAttribute('href'), '/restaurant/#fit-heading');
    assert.equal(await fallback.locator('.device-picker').count(), 0);
    assert.equal(await fallback.locator('.device-model:visible').count(), 3);
    assert.equal(await fallback.locator('.device-model:disabled').count(), 3);
    assert.match(await fallback.locator('.hero-desc').innerText(), /แนวคิดจอกลางหน้าร้าน/);
    assert.equal(await fallback.locator('.cinematic-hero a[href="/#download"]').isVisible(), true);
    for (const [shop, anchor] of [['retail', 'retail-sale'], ['restaurant', 'tour-sale']]) {
      await fallback.goto(origin + '/' + shop + '/');
      await fallback.locator('a[href="/#' + anchor + '"]').click();
      await fallback.waitForURL('**/#' + anchor);
      const target = fallback.locator('#' + anchor);
      const deadline = Date.now() + 5000;
      await target.waitFor({state:'visible'});
      let bounds;
      do {
        bounds = await target.boundingBox();
        if (bounds && bounds.y >= -8 && bounds.y < 480) break;
        await new Promise(resolve => setTimeout(resolve, 50));
      } while (Date.now() < deadline);
      assert.ok(bounds && bounds.y >= -8 && bounds.y < 480, 'No-JS fragment scroll: ' + anchor);
    }
    await noJs.close(); checks++;
    // Real browser touch dispatch exercises native pointer cancellation/scroll,
    // instead of synthetic events that bypass touch-action and gesture routing.
    const touchContext = await browser.newContext({viewport:{width:390,height:960},hasTouch:true,isMobile:true,colorScheme:'light'});
    await touchContext.route('**/*', local);
    const touchPage = await touchContext.newPage();
    touchPage.on('pageerror', e => errors.push(e.message));
    const touchSession = await touchContext.newCDPSession(touchPage);
    await load(touchPage);
    await touchPage.locator('.device-stage').scrollIntoViewIfNeeded();
    await touchSwipe(touchPage,touchSession,-110);
    assert.equal(await touchPage.locator('[data-model="kiosk"]').getAttribute('aria-pressed'), 'true');
    await touchSwipe(touchPage,touchSession,110);
    assert.equal(await touchPage.locator('[data-model="tablet"]').getAttribute('aria-pressed'), 'true');
    await touchPage.locator('[data-model="phone"]').tap(); await settleDevices(touchPage);
    assert.equal(await touchPage.locator('[data-model="phone"]').getAttribute('aria-pressed'), 'true');
    await touchSwipe(touchPage,touchSession,110);
    assert.equal(await touchPage.locator('[data-model="kiosk"]').getAttribute('aria-pressed'), 'true', 'Wrap around on touch swipe');
    await touchSwipe(touchPage,touchSession,-12);
    assert.equal(await touchPage.locator('[data-model="kiosk"]').getAttribute('aria-pressed'), 'true', 'Small gesture must snap back');
    await touchSwipe(touchPage,touchSession,-110,0,true);
    assert.equal(await touchPage.locator('[data-model="kiosk"]').getAttribute('aria-pressed'), 'true', 'Cancelled gesture must not select');
    assert.equal(await touchPage.locator('.is-dragging').count(),0);
    const beforeScroll = await touchPage.evaluate(() => scrollY);
    await touchSwipe(touchPage,touchSession,2,-150);
    await touchPage.waitForFunction(y => scrollY > y + 30,beforeScroll);
    assert.equal(await touchPage.locator('[data-model="kiosk"]').getAttribute('aria-pressed'), 'true', 'Vertical scroll must not select');
    await touchPage.emulateMedia({reducedMotion:'reduce'});
    await touchPage.locator('.device-stage').scrollIntoViewIfNeeded();
    await touchSwipe(touchPage,touchSession,-110);
    assert.equal(await touchPage.locator('[data-model="phone"]').getAttribute('aria-pressed'), 'true');
    assert.equal(await touchPage.locator('.device-phone').evaluate(e => getComputedStyle(e).transitionDuration),'0s');
    await touchContext.close(); checks++;
    assert.deepEqual(errors, []);
    console.log(`PASS ${checks} groups: 8 widths, launch logos, direct tap/keyboard/mouse drag, native touch swipe/cancel/scroll/reduced motion, business selection, deep links, image failure, no-JS.`);
  } finally { await browser.close(); }
})().catch(error => { console.error(error.stack); process.exitCode = 1; });
