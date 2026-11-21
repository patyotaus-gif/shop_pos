/* Progressive enhancement: every chapter and image is readable without JS. */
(() => {
  'use strict';
  const story = document.querySelector('[data-product-story]');
  if (!story) return;
  const chapters = [...story.querySelectorAll('.story-chapter')];
  const display = story.querySelector('.story-display');
  const screens = [...display.querySelectorAll('.story-screen-stack img')];
  const link = display.querySelector('.story-screen-link');
  const tabs = [...display.querySelectorAll('.story-tabs a')];
  const picker = story.querySelector('.business-picker');
  const hero = document.querySelector('.cinematic-hero');
  const device = hero.querySelector('.hero-device');
  const reduced = matchMedia('(prefers-reduced-motion: reduce)');
  const wide = matchMedia('(min-width: 1000px) and (min-height: 700px)');
  const middle = chapters[1];
  const variants = {
    restaurant: {
      title: 'ติดตามออเดอร์\nได้เป็นขั้นตอน',
      description: 'ดูรายการที่รอยืนยันและกำลังเตรียม แยกสถานะให้เห็นชัด พร้อมเปิดรายละเอียดออเดอร์ได้จากหน้าจอเดียว',
      detail: 'สำหรับร้านอาหารและคาเฟ่',
      label: 'จัดการออเดอร์', english: 'Order Management', image: 'orders',
      alt: 'หน้าจอออเดอร์ Pokpok แสดงรายการ DEMO-001 และสถานะรอชำระจากร้านทดสอบ'
    },
    retail: {
      title: 'เห็นสินค้าคงเหลือ\nก่อนสั่งเพิ่ม',
      description: 'ตรวจจำนวนสินค้าในร้าน ดูรายการที่ใกล้หมด และวางแผนรับสินค้าเข้าให้พร้อมสำหรับการขาย',
      detail: 'สำหรับร้านค้าปลีกและมินิมาร์ท',
      label: 'สินค้าคงเหลือ', english: 'Inventory Management', image: 'inventory',
      alt: 'หน้าจอสินค้าคงเหลือ Pokpok แสดงรายการสินค้าและจำนวนคงเหลือจากร้านทดสอบ'
    }
  };
  let current = 0;
  let queued = false;
  let active = true;
  let business = 'restaurant';
  const clamp = (value, min, max) => Math.max(min, Math.min(max, value));

  function updateLink() {
    const image = screens[current];
    link.href = image.dataset.full;
    link.setAttribute('aria-label', `ดู${tabs[current].textContent.trim()}ขนาดเต็ม (เปิดแท็บใหม่)`);
    link.dataset.failed = String(image.complete && !image.naturalWidth);
    display.querySelector('[data-current-caption]').textContent = image.alt;
  }
  function select(index) {
    current = index;
    display.dataset.scene = String(index);
    tabs.forEach((tab, i) => {
      if (i === index) tab.setAttribute('aria-current', 'step');
      else tab.removeAttribute('aria-current');
    });
    screens.forEach((image, i) => {
      image.classList.toggle('is-current', i === index);
      image.setAttribute('aria-hidden', String(i !== index));
    });
    updateLink();
  }
  function paint() {
    queued = false;
    if (!wide.matches || reduced.matches || !active) return;
    const heroRect = hero.getBoundingClientRect();
    const progress = clamp(-heroRect.top / heroRect.height, 0, 1);
    device.style.setProperty('--hero-progress', String(progress));
    const anchor = innerHeight * .5;
    let closest = 0;
    let distance = Infinity;
    chapters.forEach((chapter, i) => {
      const rect = chapter.getBoundingClientRect();
      const delta = Math.abs(rect.top + rect.height / 2 - anchor);
      if (delta < distance) { distance = delta; closest = i; }
    });
    if (closest !== current) select(closest);
    const rect = chapters[current].getBoundingClientRect();
    const phase = clamp((rect.top + rect.height / 2 - anchor) / innerHeight, -1, 1);
    display.style.setProperty('--story-progress', String(phase));
  }
  function schedule() {
    if (!queued) { queued = true; requestAnimationFrame(paint); }
  }
  function modeChanged() {
    device.style.removeProperty('--hero-progress');
    schedule();
  }
  function changeBusiness(type) {
    if (!variants[type]) return;
    business = type;
    const variant = variants[type];
    picker.querySelectorAll('button').forEach(button => button.setAttribute('aria-pressed', String(button.dataset.business === type)));
    middle.querySelector('h3').textContent = variant.title;
    middle.querySelector('.chapter-description').textContent = variant.description;
    middle.querySelector('.chapter-detail').textContent = variant.detail;
    middle.querySelector('[data-chapter-english]').textContent = variant.english;
    tabs[1].querySelector('span').textContent = variant.label;
    const source = `/screens/story/${variant.image}-1.2.78.webp`;
    const full = `/screens/${variant.image}-1.2.78.png`;
    screens[1].src = source; screens[1].alt = variant.alt; screens[1].dataset.full = full;
    const mobileImage = middle.querySelector('.story-mobile-image img');
    mobileImage.src = source; mobileImage.alt = variant.alt;
    middle.querySelector('.story-mobile-image a').href = full;
    middle.querySelector('.story-mobile-image a').setAttribute('aria-label', `ดู${variant.label}ขนาดเต็ม (เปิดแท็บใหม่)`);
    story.querySelector('[data-business-link]').href = `/${business}/`;
    story.querySelector('[data-business-link]').textContent = business === 'retail' ? 'ดูฟังก์ชันสำหรับร้านค้าปลีก' : 'ดูฟังก์ชันสำหรับร้านอาหาร';
    updateLink();
  }
  picker.addEventListener('click', event => {
    const button = event.target.closest('button[data-business]');
    if (button) changeBusiness(button.dataset.business);
  });
  tabs.forEach((tab, i) => tab.addEventListener('click', () => select(i)));
  screens.forEach(image => {
    image.addEventListener('load', updateLink);
    image.addEventListener('error', updateLink);
  });
  document.documentElement.classList.add('story-ready');
  picker.hidden = false;
  select(0);
  window.addEventListener('scroll', schedule, {passive: true});
  window.addEventListener('resize', schedule, {passive: true});
  reduced.addEventListener('change', modeChanged);
  wide.addEventListener('change', modeChanged);
  if ('IntersectionObserver' in window) {
    const observed = new Map([[hero, true], [story, true]]);
    const observer = new IntersectionObserver(entries => {
      entries.forEach(entry => observed.set(entry.target, entry.isIntersecting));
      active = [...observed.values()].some(Boolean);
      if (active) schedule();
    }, {rootMargin: '200px'});
    observer.observe(hero); observer.observe(story);
  }
  schedule();
})();
