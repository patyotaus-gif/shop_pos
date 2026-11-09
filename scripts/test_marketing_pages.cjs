// Exercise real static pages offline; never contact live services.
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(__dirname, '../public');
const output = path.resolve(__dirname, '../.remember/tmp/brand-preview');
const paths = ['/', '/features/', '/pricing/', '/marketplace/', '/guides/', '/blog/', '/privacy/', '/terms/',
  '/blog/free-pos-thailand/', '/blog/manage-shop-credit/',
  ...fs.readdirSync(path.join(root, 'guides'), {withFileTypes:true}).filter(d=>d.isDirectory()).map(d=>'/guides/'+d.name+'/')];
function localFile(url) {
  let file=path.resolve(root, '.'+decodeURIComponent(url.pathname));
  if(file!==root && !file.startsWith(root+path.sep)) throw Error('Outside public');
  if(fs.existsSync(file)&&fs.statSync(file).isDirectory()) file=path.join(file,'index.html');
  return file;
}
(async()=>{
  const {chromium}=require(process.env.PLAYWRIGHT_MODULE);
  const browser=await chromium.launch({headless:true,executablePath:process.env.BROWSER_EXECUTABLE});
  fs.mkdirSync(output,{recursive:true});
  try {
    const context=await browser.newContext();
    async function routeLocal(route){const url=new URL(route.request().url());if(url.hostname!=='pokpok-preview.test')return route.abort();const file=localFile(url);if(!fs.existsSync(file))return route.fulfill({status:404,body:''});return route.fulfill({body:fs.readFileSync(file),contentType:({'.html':'text/html; charset=utf-8','.css':'text/css','.js':'text/javascript','.png':'image/png','.svg':'image/svg+xml'})[path.extname(file)]||'application/octet-stream'});}
    await context.route('**/*',routeLocal);
    const page=await context.newPage(),errors=[];
    page.on('pageerror',e=>errors.push(e.message));
    async function fonts(){for(const [weight,name] of [[400,'Regular'],[600,'SemiBold'],[700,'Bold']]){const data=fs.readFileSync(path.resolve(__dirname,`../assets/fonts/IBMPlexSansThai-${name}.ttf`)).toString('base64');await page.evaluate(async({weight,data})=>{const f=new FontFace('IBM Plex Sans Thai',`url(data:font/ttf;base64,${data})`,{weight:String(weight)});document.fonts.add(await f.load());},{weight,data});}}
    for(const width of [320,390,768,1024,1440]) {
      await page.setViewportSize({width,height:960});
      for(const url of paths){
        await page.goto('https://pokpok-preview.test'+url);await fonts();
        assert.equal(await page.locator('h1').count(),1,'One h1 '+url);
        assert.equal(await page.locator('#main').count(),1,'Skip target '+url);
        const duplicates=await page.evaluate(()=>{const ids=[...document.querySelectorAll('[id]')].map(e=>e.id);return ids.filter((v,i)=>ids.indexOf(v)!==i);});assert.deepEqual(duplicates,[],url);
        const broken=await page.locator('img:not([loading="lazy"])').evaluateAll(imgs=>imgs.filter(i=>!i.complete||!i.naturalWidth).map(i=>i.src));assert.deepEqual(broken,[],url);
        const overflow=await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth+1);assert.equal(overflow,false,`Overflow ${url} at ${width}`);
        const hrefs=await page.locator('a[href^="/"]').evaluateAll(nodes=>nodes.map(n=>n.getAttribute('href')));for(const href of hrefs){const u=new URL(href,'https://pokpok-preview.test');assert.ok(fs.existsSync(localFile(u)),`Missing ${href} from ${url}`);}
        assert.equal(await page.locator('#mobileNav').isVisible(),false,'Menu starts closed '+url);
        if(width<=900){await page.locator('#hamburger').click();assert.equal(await page.locator('#mobileNav').isVisible(),true);await page.keyboard.press('Escape');assert.equal(await page.locator('#hamburger').getAttribute('aria-expanded'),'false');assert.equal(await page.locator('#mobileNav').isVisible(),false);}
        if(width===390||width===1440){
          await page.evaluate(async()=>{const imgs=[...document.querySelectorAll('img')];for(const img of imgs)img.loading='eager';await Promise.all(imgs.map(img=>img.decode()));});
          await page.screenshot({path:path.join(output,`pages-${url.replace(/\//g,'_')}-${width}.png`),fullPage:true});
        }
      }
    }
    await page.goto('https://pokpok-preview.test/features/');
    assert.equal(await page.locator('#story-restaurant').isVisible(),true);await page.locator('[data-story="retail"]').click();assert.equal(await page.locator('#story-restaurant').isVisible(),false);assert.equal(await page.locator('#story-retail').isVisible(),true);
    await page.goto('https://pokpok-preview.test/pricing/');
    await page.locator('#type-restaurant').click();assert.match(await page.locator('#plan-desc-0').textContent(),/กลับบ้าน/);
    await page.locator('#by').click();assert.equal(await page.locator('.p-amt').first().textContent(),'1,990');
    await page.locator('#bm').click();assert.equal(await page.locator('.p-amt').first().textContent(),'199');
    await page.locator('#type-retail').click();assert.match(await page.locator('#plan-desc-0').textContent(),/ขายเอง/);
    await page.goto('https://pokpok-preview.test/');
    assert.match(await page.locator('h1').textContent(),/POS/);
    assert.equal(await page.locator('#plans .p-card').count(),3);
    assert.equal(await page.locator('.p-avg').first().isVisible(),false);
    await page.locator('#by').click();assert.equal(await page.locator('.p-amt').first().textContent(),'1,990');assert.match(await page.locator('.p-avg').first().textContent(),/฿166/);
    await page.locator('#type-restaurant').click();assert.match(await page.locator('#plan-fit-1').textContent(),/โต๊ะและครัว/);
    await page.locator('#bm').click();assert.equal(await page.locator('.p-avg').first().isVisible(),false);
    await page.goto('https://pokpok-preview.test/guides/');
    await page.locator('#guide-search').fill('หมวดหมู่');assert.equal(await page.locator('.guide-card:visible').count(),1);
    await page.locator('#guide-search').fill('ไม่มีผลลัพธ์xyz');assert.equal(await page.locator('#guide-empty').isVisible(),true);
    await page.locator('#guide-search').fill('');await page.locator('#guide-category').selectOption({label:'ขายและรับเงิน'});assert.equal(await page.locator('.guide-card:visible').count(),2);
    await page.locator('#guide-category').selectOption('');await page.locator('.guide-card').first().click();assert.match(page.url(),/getting-started/);
    await page.goBack();assert.match(page.url(),/\/guides\/$/);
    await page.goto('https://pokpok-preview.test/#download');assert.equal(await page.locator('#download').isVisible(),true);
    await page.locator('.faq-q').first().click();assert.equal(await page.locator('#faq-answer-1').isVisible(),true);
    for(const [hash,destination] of [['#features','/features/'],['#pricing','/pricing/'],['#how','/guides/'],['#marketplace','/marketplace/']]){await page.goto('https://pokpok-preview.test/'+hash);await page.waitForURL('**'+destination);}
    const noJs=await browser.newContext({javaScriptEnabled:false,viewport:{width:390,height:900}});await noJs.route('**/*',routeLocal);const fallback=await noJs.newPage();await fallback.goto('https://pokpok-preview.test/features/');assert.equal(await fallback.locator('#story-retail').isVisible(),true);assert.equal(await fallback.locator('#story-restaurant').isVisible(),true);assert.equal(await fallback.locator('#mobileNav').isVisible(),true);await noJs.close();
    assert.deepEqual(errors,[]);
    console.log(`PASS ${paths.length} pages × 5 widths: links/assets, headings/IDs, overflow, menu/Escape, pricing, guide search/categories/empty state/navigation, FAQ, no-JS feature content.`);
  } finally {await browser.close();}
})().catch(e=>{console.error(e.stack);process.exitCode=1;});
