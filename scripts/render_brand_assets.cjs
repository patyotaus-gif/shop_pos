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
    // Separate the original vector groups for the splash's pounding motion.
    const defs = svg.match(/<defs>[\s\S]*?<\/defs>/)[0];
    const background = svg.slice(svg.indexOf('</defs>') + 7, svg.indexOf('<!-- Upright handle -->'));
    const pestle = svg.slice(svg.indexOf('<!-- Upright handle -->'), svg.indexOf('<!-- Pan bowl -->'));
    const bowl = svg.slice(svg.indexOf('<!-- Pan bowl -->'), svg.lastIndexOf('</svg>'));
    fs.mkdirSync(path.join(root, 'assets/icon/splash'), {recursive: true});
    await page.setViewportSize({width: 1024, height: 1024});
    for (const [name, shapes] of Object.entries({background, pestle, bowl})) {
      await page.setContent(`<style>html,body{margin:0;background:transparent}svg{display:block}</style><svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">${defs}${shapes}</svg>`);
      await page.screenshot({path: path.join(root, `assets/icon/splash/${name}.png`), omitBackground: true});
    }
    fs.copyFileSync(path.join(root, 'assets/brand/pokpok-icon.svg'), path.join(root, 'public/brand/pokpok-icon.svg'));
  } finally { await browser.close(); }
})().catch(error => { console.error(error); process.exitCode = 1; });
