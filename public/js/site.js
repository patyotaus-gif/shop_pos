
  // Preserve links already shared in LINE or bookmarked before pages were split.
  function routeLegacySection() {
    if (location.pathname !== '/' && location.pathname !== '/index.html') return;
    const legacyPages = {'#features': '/features/', '#pricing': '/pricing/', '#how': '/guides/', '#marketplace': '/marketplace/'};
    if (legacyPages[location.hash]) location.replace(legacyPages[location.hash]);
  }
  routeLegacySection();
  window.addEventListener('hashchange', routeLegacySection);
  function showStory(type) {
    if (!['retail', 'restaurant'].includes(type)) return;
    document.querySelector('.shop-stories').classList.add('is-filtered');
    for (const key of ['retail', 'restaurant']) {
      document.getElementById('story-' + key).hidden = key !== type;
      document.querySelector('[data-story="' + key + '"]').setAttribute('aria-pressed', String(key === type));
    }
  }
  if (document.getElementById('story-picker')) { document.getElementById('story-picker').hidden = false; showStory('restaurant'); }
  const planFeatures = {"retail":[["ขายเอง ดูยอดได้ทุกวัน","ขายสินค้าและรับเงิน","รายงานรายวัน","QR PromptPay","สั่งของจากร้านส่ง"],["ดูแลสินค้าและลูกหนี้","ทุกอย่างใน Solo","จัดการสต็อกและเตือนใกล้หมด","ลูกหนี้และการรับชำระ","พิมพ์ใบเสร็จด้วยอุปกรณ์ที่รองรับ"],["บริหารร้านด้วยข้อมูล","ทุกอย่างใน Lite","พนักงาน 3 ผู้ใช้","สมาชิกสะสมแต้ม","รายงานเชิงลึก"]],"restaurant":[["รับออเดอร์กลับบ้าน","ขายอาหารและรับเงิน","เมนูและตัวเลือกเสริม","รายงานรายวัน","QR PromptPay"],["ดูแลโต๊ะและครัว","ทุกอย่างใน Solo","โต๊ะและบิลค้าง","ส่งรายการเข้าครัว","QR สั่งอาหารที่โต๊ะ"],["รู้ต้นทุน ดูกำไร","ทุกอย่างใน Lite","สูตรอาหารและวัตถุดิบ","พนักงาน 3 ผู้ใช้ + สะสมแต้ม","รายงานเชิงลึก"]]};
  const planFit = {"retail":["เหมาะกับร้านเล็กที่เจ้าของขายเอง","เหมาะกับร้านที่มีสต็อกและลูกค้าค้างชำระ","เหมาะกับร้านที่มีพนักงานและอยากดูข้อมูลเชิงลึก"],"restaurant":["เหมาะกับร้านที่ขายกลับบ้านเป็นหลัก","เหมาะกับร้านที่มีโต๊ะและครัว","เหมาะกับร้านที่อยากรู้ต้นทุนและกำไรต่อจาน"]};
  function setShopType(type) {
    for (const key of ['retail', 'restaurant']) {
      const button = document.getElementById('type-' + key);
      button.classList.toggle('on', key === type);
      button.setAttribute('aria-pressed', String(key === type));
    }
    planFeatures[type].forEach((items, i) => {
      document.getElementById('plan-desc-' + i).textContent = items[0];
      const fit = document.getElementById('plan-fit-' + i);
      if (fit) fit.textContent = planFit[type][i];
      const list = document.getElementById('plan-features-' + i);
      list.replaceChildren(...items.slice(1).map(text => { const li = document.createElement('li'); li.textContent = text; return li; }));
    });
  }
  function setBill(t) {
    ['m', 'y'].forEach(v => { const button = document.getElementById('b' + v); button.classList.toggle('on', t === v); button.setAttribute('aria-pressed', String(t === v)); });
    document.querySelectorAll('.p-amt').forEach(el => { el.textContent = t === 'm' ? el.dataset.m : el.dataset.y; });
    document.querySelectorAll('.p-avg').forEach(el => { el.hidden = t !== 'y'; });
    document.querySelectorAll('.p-per').forEach(el => { const branch = el.textContent.includes('สาขา'); el.textContent = (t === 'm' ? ' /เดือน' : ' /ปี') + (branch ? '·สาขา' : ''); });
  }
  function closeMenu() { document.getElementById('mobileNav').classList.remove('open'); document.getElementById('hamburger').setAttribute('aria-expanded', 'false'); }
  function toggleMenu() { const open = document.getElementById('mobileNav').classList.toggle('open'); document.getElementById('hamburger').setAttribute('aria-expanded', String(open)); }
  document.addEventListener('click', e => { if (!document.getElementById('mobileNav').contains(e.target) && !document.getElementById('hamburger').contains(e.target)) closeMenu(); });
  document.addEventListener('keydown', e => { if (e.key === 'Escape' && document.getElementById('mobileNav').classList.contains('open')) { closeMenu(); document.getElementById('hamburger').focus(); } });
  window.matchMedia('(min-width: 901px)').addEventListener('change', e => { if (e.matches) closeMenu(); });
  function toggleFaq(btn) { const item = btn.closest('.faq-item'); const wasOpen = item.classList.contains('open'); document.querySelectorAll('.faq-item').forEach(el => { const open = el === item && !wasOpen; el.classList.toggle('open', open); el.querySelector('.faq-q').setAttribute('aria-expanded', String(open)); el.querySelector('.faq-a').hidden = !open; }); }

const search=document.getElementById('guide-search'), category=document.getElementById('guide-category');
if(search && category) {
  const cards=[...document.querySelectorAll('.guide-card')];
  function filterGuides(){const q=search.value.trim().toLocaleLowerCase('th');let count=0;for(const card of cards){const visible=(!q||(card.textContent+' '+card.dataset.keywords).toLocaleLowerCase('th').includes(q))&&(!category.value||card.dataset.category===category.value);card.hidden=!visible;if(visible)count++;}document.getElementById('guide-count').textContent='พบ '+count+' คู่มือ';document.getElementById('guide-empty').hidden=count>0;}
  search.addEventListener('input',filterGuides);category.addEventListener('change',filterGuides);filterGuides();
}
