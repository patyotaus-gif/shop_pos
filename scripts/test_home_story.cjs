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
  await page.waitForFunction(() => [...document.querySelectorAll('.story-screen-stack img')].every(i => Number(getComputedStyle(i).opacity) === (i.classList.contains('is-current') ? 1 : 0)));
  await page.evaluate(() => Promise.all([...document.querySelectorAll('.device-model')].flatMap(e => e.getAnimations()).map(a => a.finished.catch(() => {}))));
  await page.screenshot({path:path.join(output, name + '.png')});
}
async function scene(page, index) {
  try {
    await page.evaluate(() => new Promise(resolve => {
      let previous = scrollY, stable = 0;
      function frame() { const y = scrollY; stable = Math.abs(y - previous) < .5 ? stable + 1 : 0; previous = y; if (stable >= 8) resolve(); else requestAnimationFrame(frame); }
      requestAnimationFrame(frame);
    }));
    await page.waitForFunction(i => document.querySelector('.story-display').dataset.scene === String(i), index, {timeout:10000});
  }
  catch (error) {
    console.error(await page.evaluate(() => ({hash:location.hash, y:scrollY,scene:document.querySelector('.story-display').dataset.scene,chapters:[...document.querySelectorAll('.story-chapter')].map(e=>({id:e.id,top:e.getBoundingClientRect().top,height:e.getBoundingClientRect().height}))})));
    await page.screenshot({path:path.join(output,'failed-scene.png')}); throw error;
  }
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
      assert.equal(await page.locator('.device-tablet img').evaluate(i => i.complete && i.naturalWidth > 0), true);
      const overflow = await page.evaluate(() => document.documentElement.scrollWidth > innerWidth);
      if (overflow) {
        console.error(await page.evaluate(() => ({width:innerWidth,scroll:document.documentElement.scrollWidth,elements:[...document.querySelectorAll('body *')].map(e=>({tag:e.tagName,cls:e.className,left:e.getBoundingClientRect().left,right:e.getBoundingClientRect().right})).filter(e=>e.left<0||e.right>innerWidth)})));
        await page.screenshot({path:path.join(output, `overflow-${width}.png`)});
      }
      assert.equal(overflow, false, `Overflow ${width}`);
      const cta = await page.locator('.cinematic-hero .btn-lg').boundingBox();
      assert.ok(cta.y + cta.height <= 960, `Hero action visible ${width}`);
      for (const control of await page.locator('.business-picker button, .device-picker button').all()) {
        const box = await control.boundingBox(); assert.ok(box.height >= 44 && box.width >= 44);
      }
      if ([390,768,1280,1440].includes(width)) {
        await capture(page, `hero-${width}`);
        await page.locator('.cinematic-hero').screenshot({path:path.join(output, `hero-full-${width}.png`)});
      }
      // The devices themselves change position, not only a text label or screen.
      const tabletPose = await page.locator('.device-tablet').evaluate(e => getComputedStyle(e).transform);
      await page.locator('[data-device="phone"]').click();
      assert.equal(await page.locator('[data-model="phone"]').getAttribute('data-position'), 'center');
      assert.match(await page.locator('#device-description').innerText(), /มือถือ.*งานร้าน/s);
      assert.match(await page.locator('[data-device-detail]').innerText(), /ภาพจำลอง/);
      await page.waitForFunction(pose => getComputedStyle(document.querySelector('.device-tablet')).transform !== pose, tabletPose);
      await page.evaluate(() => Promise.all([...document.querySelectorAll('.device-model')].flatMap(e => e.getAnimations()).map(a => a.finished.catch(() => {}))));
      assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true, `Phone overflow ${width}`);
      if ([390,1280,1440].includes(width)) await capture(page, `device-phone-${width}`);
      await page.locator('[data-device="kiosk"]').focus(); await page.keyboard.press('Enter');
      assert.equal(await page.locator('[data-model="kiosk"]').getAttribute('data-position'), 'center');
      assert.equal(await page.locator('.device-picker [aria-pressed="true"]').count(), 1);
      assert.match(await page.locator('#device-description').innerText(), /ยังไม่เปิดให้ใช้งาน/);
      assert.equal(await page.locator('.device-concept-note').isVisible(), true);
      await page.evaluate(() => Promise.all([...document.querySelectorAll('.device-model')].flatMap(e => e.getAnimations()).map(a => a.finished.catch(() => {}))));
      assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true, `Kiosk overflow ${width}`);
      if ([390,768,1280,1440].includes(width)) {
        await capture(page, `device-kiosk-${width}`);
        await page.locator('.cinematic-hero').screenshot({path:path.join(output, `kiosk-full-${width}.png`)});
      }
      await page.keyboard.press('ArrowLeft');
      assert.equal(await page.locator('[data-device="tablet"]').getAttribute('aria-pressed'), 'true');
      assert.equal(await page.locator('[data-device="tablet"]').evaluate(e => e === document.activeElement), true);
      assert.match(await page.locator('[data-device-detail] a').getAttribute('href'), /pos-1.2.78.png$/);
      await page.locator('[data-business="retail"]').click();
      assert.equal(await page.locator('[data-business="retail"]').getAttribute('aria-pressed'), 'true');
      assert.match(await page.locator('#tour-manage h3').innerText(), /สินค้าคงเหลือ/);
      assert.match(await page.locator('#tour-manage img').getAttribute('src'), /inventory/);
      assert.equal(await page.locator('[data-business-link]').getAttribute('href'), '/retail/');
      await page.locator('[data-business="restaurant"]').focus();
      await page.keyboard.press('Enter');
      assert.match(await page.locator('#tour-manage h3').innerText(), /ออเดอร์/);
      assert.match(await page.locator('#tour-manage img').getAttribute('src'), /orders/);
      if (width < 1000) {
        assert.equal(await page.locator('.story-display').isVisible(), false);
        assert.equal(await page.locator('.story-mobile-image:visible').count(), 3);
        await page.locator('#tour-manage').scrollIntoViewIfNeeded();
        if ([390,768].includes(width)) await capture(page, `story-${width}`);
      }
      assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth), true, `Switched layout overflow ${width}`);
      checks++;
    }
    await page.setViewportSize({width:1440,height:960});
    await load(page);
    const initialPose = await page.locator('.device-tablet').evaluate(e => getComputedStyle(e).transform);
    await page.evaluate(() => scrollTo({top:400,behavior:'instant'}));
    await page.waitForFunction(pose => getComputedStyle(document.querySelector('.device-tablet')).transform !== pose, initialPose);
    await load(page, '/#tour-manage'); await scene(page, 1);
    assert.match(await page.locator('.story-screen-link').getAttribute('href'), /orders/);
    await capture(page, 'story-orders-1440');
    await page.locator('.story-tabs a[href="#tour-report"]').click(); await scene(page, 2);
    assert.match(await page.locator('.story-screen-link').getAttribute('href'), /overview/);
    assert.equal(await page.locator('.story-tabs a[aria-current="step"]').count(), 1);
    await capture(page, 'story-report-1440');
    await page.locator('.story-tabs a[href="#tour-sale"]').focus(); await page.keyboard.press('Enter'); await scene(page, 0);
    assert.match(await page.locator('.story-screen-link').getAttribute('href'), /pos/);
    await capture(page, 'story-sales-1440');
    checks++;

    // Resize and live OS setting changes must reveal all content without motion.
    await page.emulateMedia({reducedMotion:'reduce'});
    assert.equal(await page.locator('.story-display').isVisible(), false);
    assert.equal(await page.locator('.story-mobile-image:visible').count(), 3);
    assert.equal(await page.locator('.device-tablet').evaluate(e => getComputedStyle(e).transitionDuration), '0s');
    await load(page); await capture(page, 'reduced-motion-1440');
    await page.locator('[data-device="kiosk"]').click();
    assert.equal(await page.locator('[data-model="kiosk"]').getAttribute('data-position'), 'center');
    const reducedPose = await page.locator('.device-kiosk').evaluate(e => getComputedStyle(e).transform);
    await page.evaluate(() => scrollTo({top:200,behavior:'instant'}));
    assert.equal(await page.locator('.device-kiosk').evaluate(e => getComputedStyle(e).transform), reducedPose);
    await page.emulateMedia({reducedMotion:'no-preference'});
    await page.setViewportSize({width:1440,height:600});
    assert.equal(await page.locator('.story-display').isVisible(), false);
    checks++;

    // Full screenshot remains available even if an optimized preview fails.
    const blockedContext = await browser.newContext({viewport:{width:1440,height:960},colorScheme:'light'});
    await blockedContext.route('**/*', route => route.request().url().includes('/screens/story/orders-1.2.78.webp') ? route.abort() : local(route));
    const blocked = await blockedContext.newPage();
    blocked.on('pageerror', e => errors.push(e.message));
    await load(blocked, '/#tour-manage'); await scene(blocked, 1);
    await blocked.waitForFunction(() => document.querySelector('.story-screen-link').dataset.failed === 'true');
    assert.match(await blocked.locator('.story-screen-link').getAttribute('href'), /screens\/orders-1.2.78.png$/);
    await blockedContext.close();
    checks++;

    const noJs = await browser.newContext({javaScriptEnabled:false,viewport:{width:390,height:960},colorScheme:'light'});
    await noJs.route('**/*', local);
    const fallback = await noJs.newPage(); await fallback.goto(origin + '/');
    assert.equal(await fallback.locator('.story-chapter').count(), 3);
    assert.equal(await fallback.locator('.story-mobile-image:visible').count(), 3);
    assert.equal(await fallback.locator('.business-picker').isVisible(), false);
    assert.equal(await fallback.locator('.device-picker').isVisible(), false);
    assert.equal(await fallback.locator('.device-model:visible').count(), 3);
    assert.match(await fallback.locator('.device-concept-note').innerText(), /ยังไม่เปิดให้ใช้งาน/);
    assert.equal(await fallback.locator('.cinematic-hero a[href="/#download"]').isVisible(), true);
    await noJs.close(); checks++;
    assert.deepEqual(errors, []);
    console.log(`PASS ${checks} groups: 8 widths, physical device selection/keyboard/concept status, business selection, scroll/deep-link stages, reduced motion/short viewport, image failure, no-JS.`);
  } finally { await browser.close(); }
})().catch(error => { console.error(error.stack); process.exitCode = 1; });
