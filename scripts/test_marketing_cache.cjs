// Run with MINIMATCH_MODULE (Firebase CLI dependency), PLAYWRIGHT_MODULE and
// BROWSER_EXECUTABLE. Set CACHE_CHECK_URL for a read-only Hosting smoke check.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const http = require('node:http');
const { once } = require('node:events');
const root = path.resolve(__dirname, '..');
const config = JSON.parse(fs.readFileSync(path.join(root, 'firebase.json'))).hosting;
const marketing = ['features', 'pricing', 'marketplace', 'guides', 'blog', 'privacy', 'terms'];
const minimatch = require(process.env.MINIMATCH_MODULE);
function cachePolicy(route) {
  let policy = 'max-age=3600'; // Observed default on live Hosting before this fix.
  for (const rule of config.headers) {
    if (!minimatch(route, rule.source)) continue;
    for (const header of rule.headers) {
      if (header.key.toLowerCase() === 'cache-control') policy = header.value;
    }
  }
  return policy;
}
async function stop(server) {
  server.closeAllConnections();
  await new Promise(resolve => server.close(resolve));
}
function directories(dir, prefix) {
  return [prefix, ...fs.readdirSync(dir, { withFileTypes: true })
    .filter(entry => entry.isDirectory())
    .flatMap(entry => directories(path.join(dir, entry.name), `${prefix}/${entry.name}`))];
}

(async () => {
  const base = process.env.CACHE_CHECK_URL;
  async function policyFor(route) {
    if (!base) return cachePolicy(new URL(route, 'http://localhost').pathname);
    const response = await fetch(base + route, { signal: AbortSignal.timeout(20000) });
    await response.arrayBuffer();
    assert.equal(response.status, 200, route);
    return response.headers.get('cache-control') || '';
  }
  const dirs = marketing.flatMap(name => directories(path.join(root, 'public', name), `/${name}`));
  const routes = ['/', '/?copy-check=1', '/index.html',
    ...dirs.flatMap(dir => [dir, `${dir}/`, `${dir}/index.html`])];
  for (const route of routes) {
    assert.match(await policyFor(route), /\bno-cache\b/, `Revalidate ${route}`);
  }
  // Shared assets keep their existing cache policy.
  for (const route of ['/site-pages.css', '/js/site.js', '/robots.txt']) {
    assert.doesNotMatch(await policyFor(route), /\bno-cache\b/, route);
  }
  for (const route of ['/order/', '/app/version.json']) {
    assert.match(await policyFor(route), /\bno-cache\b/, route);
  }
  for (const route of ['/api/shopPublic', '/api/createOrderCheckout', '/r/test', '/payment-test/', '/supplier/']) {
    assert.equal(cachePolicy(route), 'max-age=3600', `No new override for ${route}`);
  }
  console.log(`PASS: ${routes.length} marketing URLs revalidate; other policies preserved (${base || 'local config'}).`);

  // A real HTTP cache, without Playwright route interception (which disables it).
  // This fixture exercises browser behavior with the configured policy; the
  // live URL mode above separately proves Firebase applies the same headers.
  let copy = 'Previous website copy';
  let policy;
  const server = http.createServer((req, res) => {
    res.writeHead(200, { 'Content-Type': 'text/html', 'Cache-Control': policy });
    res.end(`<h1>${copy}</h1>`);
  }).listen(0, '127.0.0.1');
  await once(server, 'listening');
  const url = `http://127.0.0.1:${server.address().port}`;
  let browser;
  try {
    const { chromium } = require(process.env.PLAYWRIGHT_MODULE);
    browser = await chromium.launch({ headless: true, executablePath: process.env.BROWSER_EXECUTABLE });
    for (const [header, expected] of [
      ['max-age=3600', 'Previous website copy'],
      [cachePolicy('/'), 'Updated website copy after release'],
    ]) {
      policy = header;
      copy = 'Previous website copy';
      const context = await browser.newContext();
      try {
        const page = await context.newPage();
        await page.goto(url);
        assert.equal(await page.locator('h1').textContent(), 'Previous website copy');
        await page.goto('about:blank');
        copy = 'Updated website copy after release';
        await page.goto(url);
        assert.equal(await page.locator('h1').textContent(), expected, header);
      } finally { await context.close(); }
    }
    console.log('PASS: old policy reproduces stale copy; fixed policy refreshes on return without clearing cache.');
  } finally {
    if (browser) await browser.close();
    await stop(server);
  }
})().catch(error => { console.error(error); process.exitCode = 1; });
