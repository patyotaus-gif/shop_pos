// Offline preview of the real landing page. Never calls live services.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../public');
const output = path.resolve(__dirname, '../.remember/tmp/brand-preview');
(async () => {
  const {chromium} = require(process.env.PLAYWRIGHT_MODULE);
  const browser = await chromium.launch({headless: true, executablePath: process.env.BROWSER_EXECUTABLE});
  fs.mkdirSync(output, {recursive: true});
  try {
    const page = await browser.newPage();
    const errors = [];
    page.on('pageerror', e => errors.push(e.message));
    await page.route('**/*', async route => {
      const url = new URL(route.request().url());
      if (url.hostname !== 'pokpok-preview.test') return route.abort();
      const file = path.resolve(root, '.' + decodeURIComponent(url.pathname === '/' ? '/index.html' : url.pathname));
      if (!file.startsWith(root + path.sep) || !fs.existsSync(file) || !fs.statSync(file).isFile()) return route.fulfill({status: 404, body: ''});
      const contentType = {'.html': 'text/html; charset=utf-8', '.css': 'text/css', '.js': 'text/javascript', '.png': 'image/png', '.svg': 'image/svg+xml'}[path.extname(file)] || 'application/octet-stream';
      await route.fulfill({body: fs.readFileSync(file), contentType});
    });
    for (const width of [320, 390, 768, 1440]) {
      await page.setViewportSize({width, height: 960});
      await page.goto('https://pokpok-preview.test/');
      // Use the same bundled brand font when the network is blocked.
      for (const [weight, name] of [[400, 'Regular'], [600, 'SemiBold'], [700, 'Bold']]) {
        const data = fs.readFileSync(path.resolve(__dirname, `../assets/fonts/IBMPlexSansThai-${name}.ttf`)).toString('base64');
        await page.evaluate(async ({weight, data}) => {
          const font = new FontFace('IBM Plex Sans Thai', `url(data:font/ttf;base64,${data})`, {weight: String(weight)});
          document.fonts.add(await font.load());
        }, {weight, data});
      }
      assert.equal(await page.locator('#story-restaurant').isVisible(), true);
      await page.locator('[data-story="retail"]').click();
      assert.equal(await page.locator('#story-retail').isVisible(), true);
      assert.equal(await page.locator('#story-restaurant').isVisible(), false);
      await page.locator('[data-story="restaurant"]').click();
      await page.locator('#type-restaurant').click();
      assert.match(await page.locator('#plan-desc-0').textContent(), /กลับบ้าน/);
      await page.locator('#type-retail').click();
      assert.match(await page.locator('#plan-desc-0').textContent(), /ขายเอง/);
      if (width <= 900) {
        await page.locator('#hamburger').click();
        assert.equal(await page.locator('#hamburger').getAttribute('aria-expanded'), 'true');
        await page.keyboard.press('Escape');
        assert.equal(await page.locator('#hamburger').getAttribute('aria-expanded'), 'false');
      }
      assert.equal(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth + 1), true, `Horizontal overflow at ${width}`);
      await page.evaluate(() => window.scrollTo(0, 0));
      await page.emulateMedia({reducedMotion: 'reduce'});
      await page.screenshot({path: path.join(output, `website-${width}.png`), fullPage: true});
      await page.screenshot({path: path.join(output, `website-${width}-first-screen.png`)});
    }
    // Progressive enhancement: both shop stories remain available without JS.
    const noJs = await browser.newContext({javaScriptEnabled: false});
    const fallback = await noJs.newPage();
    await fallback.setContent(fs.readFileSync(path.join(root, 'index.html'), 'utf8'));
    assert.equal(await fallback.locator('#story-retail').isVisible(), true);
    assert.equal(await fallback.locator('#story-restaurant').isVisible(), true);
    await noJs.close();
    assert.deepEqual(errors, []);
    console.log('PASS brand website: 320/390/768/1440 widths, no horizontal overflow, shop examples, plan selection, keyboard menu, no-JS fallback. Screenshots saved locally.');
  } finally { await browser.close(); }
})().catch(e => {console.error(e.stack); process.exitCode = 1;});
