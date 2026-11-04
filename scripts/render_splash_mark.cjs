// Derive transparent white splash layers from the original vector geometry.
// Launcher icons remain independent. PLAYWRIGHT_MODULE selects local tooling.
const fs = require('node:fs');
const path = require('node:path');
const {chromium} = require(process.env.PLAYWRIGHT_MODULE || 'playwright');
const root = path.resolve(__dirname, '..');
(async () => {
  const source = fs.readFileSync(path.join(root, 'assets/brand/pokpok-icon.svg'), 'utf8');
  const pestle = source.slice(source.indexOf('<!-- Upright handle -->'), source.indexOf('<!-- Pan bowl -->'));
  const bowl = source.slice(source.indexOf('<!-- Pan bowl -->'), source.lastIndexOf('</svg>'));
  // Cut out the original handle dot instead of painting a white dot on white.
  const hole = pestle.match(/<circle\b[^>]*\/>/)[0].replace(/fill="[^"]*"/, 'fill="black"');
  const defs = `<defs><mask id="handle-hole" maskUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024"><rect width="1024" height="1024" fill="white"/>${hole}</mask></defs>`;
  const white = s => s.replace(/fill="[^"]*"/g, 'fill="#FFFFFF"');
  const layers = {
    pestle: `<g mask="url(#handle-hole)">${white(pestle.replace(/<circle\b[^>]*\/>/, ''))}</g>`,
    bowl: white(bowl),
  };
  const svg = (content, viewBox='0 0 1024 1024') => `<svg xmlns="http://www.w3.org/2000/svg" viewBox="${viewBox}">${defs}${content}</svg>`;
  const browser = await chromium.launch({headless: true, executablePath: process.env.BROWSER_EXECUTABLE});
  try {
    const page = await browser.newPage({viewport:{width:1024,height:1024},deviceScaleFactor:1});
    for (const [name, content] of Object.entries(layers)) {
      await page.setContent(`<style>html,body{margin:0;background:transparent}svg{display:block;width:1024px;height:1024px}</style>${svg(content)}`);
      await page.screenshot({path:path.join(root,`assets/icon/splash/white-${name}.png`),omitBackground:true});
    }
  } finally {await browser.close();}
  const preview = path.join(root,'.remember/tmp/splash-preview/pokpok-splash.html');
  if (fs.existsSync(preview)) {
    let html=fs.readFileSync(preview,'utf8');
    const mark=svg(`<g id="pestle">${layers.pestle}</g><g id="bowl">${layers.bowl}</g>`,'0 0 1024 860.16').replace('<svg ', '<svg class="icon" role="img" aria-label="Pokpok" ');
    html=html.replace(/<svg class="icon"[\s\S]*?<\/svg>/,mark)
      .replace('.icon{width:200px;height:200px;border-radius:36px;', '.icon{width:200px;height:168px;')
      .replace('.word{margin-top:22px;', '.word{margin-top:12px;');
    fs.writeFileSync(preview,html);
  }
})().catch(e=>{console.error(e);process.exitCode=1});
