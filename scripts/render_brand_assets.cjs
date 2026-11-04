// Rasterize the team's canonical SVG without redrawing the artwork.
// PLAYWRIGHT_MODULE and optionally BROWSER_EXECUTABLE select local tooling.
const fs = require('node:fs');
const path = require('node:path');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const root = path.resolve(__dirname, '..');
(async () => {
  const svg = fs.readFileSync(path.join(root, 'assets/brand/pokpok-icon.svg'), 'utf8');
  const browser = await chromium.launch({headless: true, executablePath: process.env.BROWSER_EXECUTABLE});
  try {
    const page = await browser.newPage({deviceScaleFactor: 1});
    for (const [size, file] of [[1024, 'assets/icon/icon.png'], [256, 'public/favicon.png']]) {
      await page.setViewportSize({width: size, height: size});
      await page.setContent(`<style>html,body{margin:0;width:100%;height:100%}svg{display:block;width:100%;height:100%}</style>${svg}`);
      await page.screenshot({path: path.join(root, file)});
    }
    fs.copyFileSync(path.join(root, 'assets/brand/pokpok-icon.svg'), path.join(root, 'public/brand/pokpok-icon.svg'));
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
