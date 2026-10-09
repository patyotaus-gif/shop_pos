// Headless local renderer only. External requests are blocked; no real accounts.
const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
(async()=>{
  const {chromium}=require(process.env.PLAYWRIGHT_MODULE);
  const browser=await chromium.launch({headless:true,executablePath:process.env.BROWSER_EXECUTABLE});
  try {
    const page=await browser.newPage();await page.route('**/*',route=>route.abort());
    await page.setContent('<main id="fixture"></main>');
    const html=fs.readFileSync(path.join(__dirname,'../public/supplier/index.html'),'utf8');
    const start=html.indexOf('  function orderCard(id, o) {'),end=html.indexOf('  // ── Modal helpers',start);
    assert.ok(start>=0&&end>start);
    const result=await page.evaluate(async render=>{
      const STATUS={placed:['Placed',''],accepted:['Accepted',''],shipped:['Shipped','']};
      const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
      const baht=n=>Number(n).toFixed(2),functions={},calls=[];
      const httpsCallable=(_,name)=>async data=>calls.push({name,...data});
      const orderCard=new Function('STATUS','esc','baht','httpsCallable','functions',render+';return orderCard;')(STATUS,esc,baht,httpsCallable,functions);
      const payload='<img src="blocked" onerror="window.__auditExecuted=1">';
      for(const id of ['normal-order','id" ><img src=x onerror="window.__auditExecuted=1">']) {
        const card=orderCard(id,{status:'placed',shopName:payload,items:[{name:payload,quantity:payload,unit:payload,price:1}]});
        document.querySelector('#fixture').appendChild(card);
        card.querySelector('.btn-go').click();
      }
      await new Promise(resolve=>requestAnimationFrame(()=>requestAnimationFrame(resolve)));
      return {executed:window.__auditExecuted===1,images:document.querySelectorAll('img').length,calls,text:document.body.textContent};
    },html.slice(start,end));
    assert.equal(result.executed,false);assert.equal(result.images,0);assert.equal(result.calls.length,2);
    assert.equal(result.calls[0].name,'supplierSetOrderStatus');assert.equal(result.calls[0].status,'accepted');
    assert.ok(result.text.includes('<img'));
    console.log('PASS supplier browser: hostile stored fields and document IDs render as text; legitimate action callbacks preserved; no external requests');
  } finally {await browser.close();}
})().catch(e=>{console.error(e.message);process.exitCode=1;});
