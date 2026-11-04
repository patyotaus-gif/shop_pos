// Preserve the team's SVG and rasterize the same paths for Flutter offline use.
// Run with PLAYWRIGHT_MODULE and optionally BROWSER_EXECUTABLE.
const fs = require('node:fs');
const path = require('node:path');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const root = path.resolve(__dirname, '..');
(async () => {
  const source = path.join(root, 'assets/brand/source/pokpok_wordmark.svg');
  const svg = fs.readFileSync(source, 'utf8');
  if (!svg.includes('viewBox="0 0 2022 548"') || /<(script|text|image)\b|\bhref=/i.test(svg)) {
    throw new Error('Review changed wordmark source before rendering.');
  }
  fs.copyFileSync(source, path.join(root, 'public/brand/pokpok-wordmark.svg'));
  const browser = await chromium.launch({headless: true, executablePath: process.env.BROWSER_EXECUTABLE});
  try {
    const page = await browser.newPage({viewport: {width: 1011, height: 274}, deviceScaleFactor: 1});
    await page.setContent(`<style>html,body{margin:0;background:transparent}svg{display:block;width:1011px;height:274px}</style>${svg}`);
    await page.screenshot({path: path.join(root, 'assets/brand/pokpok-wordmark.png'), omitBackground: true});
  } finally { await browser.close(); }
})().catch(error => {console.error(error); process.exitCode = 1;});
