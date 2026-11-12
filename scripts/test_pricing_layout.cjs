// Public pricing only, served from this checkout; every external request is blocked.
// Run manually with PLAYWRIGHT_MODULE and BROWSER_EXECUTABLE (same as test_brand_site).
const fs = require('node:fs');
const path = require('node:path');
const assert = require('node:assert/strict');
const root = path.resolve(process.env.PRICING_TEST_ROOT || path.join(__dirname, '../public'));
const widths = [320, 360, 390, 768, 1024, 1440, 1920];
function contrast(a,b) {
  const light = color => {
    const c = color.match(/[\d.]+/g).slice(0,3).map(Number).map(v => {v/=255; return v<=.04045?v/12.92:((v+.055)/1.055)**2.4;});
    return .2126*c[0]+.7152*c[1]+.0722*c[2];
  };
  const x=light(a),y=light(b); return (Math.max(x,y)+.05)/(Math.min(x,y)+.05);
}
(async () => {
  assert.ok(process.env.PLAYWRIGHT_MODULE, 'Set PLAYWRIGHT_MODULE to the installed Playwright module');
  const {chromium} = require(process.env.PLAYWRIGHT_MODULE);
  const browser = await chromium.launch({headless:true, executablePath:process.env.BROWSER_EXECUTABLE});
  let states=0;
  try {
    const context = await browser.newContext({colorScheme:'light', reducedMotion:'reduce'});
    await context.route('**/*', async route => {
      const url = new URL(route.request().url());
      if (url.hostname !== 'pricing.test') return route.abort();
      let file=path.resolve(root,'.'+decodeURIComponent(url.pathname));
      assert.ok(file===root || file.startsWith(root+path.sep));
      if (fs.existsSync(file) && fs.statSync(file).isDirectory()) file=path.join(file,'index.html');
      await route.fulfill({status:fs.existsSync(file)?200:404,body:fs.existsSync(file)?fs.readFileSync(file):'',contentType:({'.html':'text/html; charset=utf-8','.css':'text/css','.js':'application/javascript','.svg':'image/svg+xml','.png':'image/png','.webp':'image/webp'})[path.extname(file)]||'application/octet-stream'});
    });
    const page = await context.newPage(), errors=[];
    page.on('pageerror', e=>errors.push(e.message));
    async function fonts() {
      for (const [weight,name] of [[400,'Regular'],[500,'Medium'],[600,'SemiBold'],[700,'Bold']]) {
        const data=fs.readFileSync(path.resolve(__dirname,`../assets/fonts/IBMPlexSansThai-${name}.ttf`)).toString('base64');
        await page.evaluate(async ({weight,data})=>{const f=new FontFace('IBM Plex Sans Thai',`url(data:font/ttf;base64,${data})`,{weight:String(weight)});document.fonts.add(await f.load());},{weight,data});
      }
    }
    async function geometry(label) {
      const measured=await page.locator('.pricing').evaluate(section=>{
        const rect=e=>{const b=e.getBoundingClientRect();return {x:b.x,y:b.y,width:b.width,height:b.height,right:b.right,bottom:b.bottom};};
        // Baseline-aligned glyphs can extend a few pixels below their line box;
        // they are clipped only if an ancestor actually clips the vertical overflow.
        const clipped=[...section.querySelectorAll('.p-card, .p-list li, .p-desc, .p-fit, .p-btn, .bill-btn, .p-price')].filter(e=>e.scrollWidth>e.clientWidth+1 || (e.scrollHeight>e.clientHeight+1 && getComputedStyle(e).overflowY!=='visible')).map(e=>({name:e.className,sw:e.scrollWidth,cw:e.clientWidth,sh:e.scrollHeight,ch:e.clientHeight}));
        return {pageWidth:document.documentElement.scrollWidth,viewport:innerWidth,section:rect(section),cards:[...section.querySelectorAll('.p-card')].map(rect),targets:[...section.querySelectorAll('.bill-btn,.p-btn')].map(rect),clipped};
      });
      assert.ok(measured.pageWidth<=measured.viewport+1, 'Page overflow '+label);
      assert.ok(measured.section.width<=1061, 'Pricing comparison too wide '+label);
      assert.deepEqual(measured.clipped, [], 'Clipped pricing content '+label);
      assert.equal(measured.cards.length,3);
      for (const r of measured.targets) assert.ok(r.height>=44 && r.width>=44, 'Small target '+label);
      if (measured.viewport>=1024) {
        assert.ok(measured.cards.every(c=>Math.abs(c.y-measured.cards[0].y)<1),'Cards not aligned '+label);
        assert.ok(measured.cards[1].x>measured.cards[0].right,'Cards not separated '+label);
      } else {
        assert.ok(measured.cards.every(c=>c.width<=481),'Stacked card too wide '+label);
        assert.ok(measured.cards[1].y>measured.cards[0].bottom,'Stacked cards overlap '+label);
      }
    }
    for (const width of widths) {
      await page.setViewportSize({width,height:960});
      for (const route of ['/','/pricing/']) {
        await page.goto('https://pricing.test'+route); await fonts();
        for (const shop of ['restaurant','retail']) {
          await page.locator('#type-'+shop).click();
          assert.equal(await page.locator('#type-'+shop).getAttribute('aria-pressed'),'true');
          const lite=await page.locator('#plan-features-1').innerText();
          assert.match(lite,shop==='retail'?/สินค้าคงเหลือ/:/หน้าจอครัว/);
          assert.doesNotMatch(lite,shop==='retail'?/หน้าจอครัว/:/สินค้าใกล้หมด/);
          assert.match(await page.locator('.p-card').nth(1).innerText(),/รวมฟีเจอร์ Solo และเพิ่ม/);
          assert.match(await page.locator('.p-card').nth(2).innerText(),/รวมฟีเจอร์ Lite และเพิ่ม/);
          for (const bill of ['y','m']) {
            await page.locator('#b'+bill).focus(); await page.keyboard.press('Enter');
            assert.deepEqual(await page.locator('.p-amt').allTextContents(),bill==='m'?['199','399','599']:['1,990','3,990','5,990']);
            assert.ok((await page.locator('.p-per').allTextContents()).every(t=>t.trim()===(bill==='m'?'/เดือน':'/ปี')));
            assert.equal(await page.locator('.p-avg:visible').count(),bill==='m'?0:3);
            await geometry(`${route} ${shop} ${bill} ${width}`); states++;
          }
        }
        const samples=await page.locator('.pricing .p-desc,.pricing .p-fit,.pricing .p-list li,.pricing .period,.pricing .p-avg,.pricing .p-btn,.pricing .bill-btn,.pricing-trial,.pricing-terms').evaluateAll(nodes=>nodes.filter(e=>e.getClientRects().length).map(e=>{
          let parent=e,bg;
          while(parent) {bg=getComputedStyle(parent).backgroundColor;if(bg!=='rgba(0, 0, 0, 0)')break;parent=parent.parentElement;}
          return {color:getComputedStyle(e).color,bg,size:parseFloat(getComputedStyle(e).fontSize),role:e.className||e.tagName};
        }));
        for(const s of samples)assert.ok(contrast(s.color,s.bg)>=4.5,`Contrast ${s.role} ${route}`);
        assert.ok(samples.filter(s=>['p-desc','p-fit','LI'].includes(s.role)).every(s=>s.size>=16),'Core feature text below 16px');
        if(width===390) {
          await page.locator('#by').click();
          await page.evaluate(()=>{const nodes=[...document.querySelectorAll('.pricing *')];const sizes=nodes.map(e=>parseFloat(getComputedStyle(e).fontSize));nodes.forEach((e,i)=>e.style.fontSize=sizes[i]*2+'px');});
          await geometry('200% text '+route);
        }
      }
    }
    // Focus and the selected choice must still be identifiable in Windows high contrast.
    await page.goto('https://pricing.test/pricing/');
    await page.emulateMedia({forcedColors:'active'});
    await page.locator('#by').focus(); await page.keyboard.press('Space');
    assert.equal(await page.locator('#by').getAttribute('aria-pressed'),'true');
    const focus=await page.locator('#by').evaluate(e=>({outline:getComputedStyle(e).outlineStyle,selected:getComputedStyle(e,'::before').content}));
    assert.notEqual(focus.outline,'none');assert.match(focus.selected,/✓/);
    await page.emulateMedia({forcedColors:'none'});
    for (const route of ['/','/pricing/']) {
      await page.goto('https://pricing.test'+route);
      await page.locator('.p-btn').first().click();
      assert.ok(new URL(page.url()).hash==='#download','Trial CTA misses download');
      assert.equal(await page.locator('#download').isVisible(),true);
    }
    assert.deepEqual(errors,[]);
    console.log(`PASS ${states} pricing states; 7 widths; both routes; all prices, feature switches, keyboard, 200% text, contrast, forced colours and trial CTA.`);
  } finally {await browser.close();}
})().catch(e=>{console.error(e.stack);process.exitCode=1;});
