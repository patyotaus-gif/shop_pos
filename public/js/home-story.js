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
  const showcase = hero.querySelector('[data-device-showcase]');
  const models = [...showcase.querySelectorAll('[data-model]')];
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
  let selectedDevice = 1;
  let gesture = null;
  let suppressClick = false;

  function selectDevice(index) {
    device.classList.add('devices-ready');
    selectedDevice = (index + models.length) % models.length;
    models.forEach((model, i) => {
      model.setAttribute('aria-pressed', String(i === selectedDevice));
      model.dataset.position = i === selectedDevice ? 'center' : (i === (selectedDevice + 1) % models.length ? 'right' : 'left');
    });
    showcase.querySelector('.device-sr-status').textContent = models[selectedDevice].getAttribute('aria-label');
  }
  models.forEach((button, index) => {
    button.disabled = false;
    button.addEventListener('click', () => selectDevice(index));
    button.addEventListener('keydown', event => {
      const direction = event.key === 'ArrowRight' ? 1 : event.key === 'ArrowLeft' ? -1 : 0;
      if (!direction) return;
      event.preventDefault();
      const next = (index + direction + models.length) % models.length;
      models[next].focus({preventScroll: true}); selectDevice(next);
    });
  });
  // Only horizontal intent captures the pointer. Native vertical scroll and
  // pinch zoom remain available; cancellation never commits a selection.
  function finishGesture(event, cancelled = false) {
    if (!gesture || event.pointerId !== gesture.id) return;
    const ended = gesture;
    gesture = null;
    device.classList.remove('is-dragging');
    device.style.removeProperty('--device-drag');
    if (device.hasPointerCapture(ended.id)) device.releasePointerCapture(ended.id);
    const dx = event.clientX - ended.x;
    const dy = event.clientY - ended.y;
    const threshold = Math.max(32, device.clientWidth * .08);
    if (!cancelled && ended.axis === 'x' && Math.abs(dx) >= threshold && Math.abs(dx) > Math.abs(dy) * 1.25) {
      selectDevice(ended.index + (dx < 0 ? 1 : -1));
    }
  }
  device.addEventListener('pointerdown', event => {
    if (!event.isPrimary) {
      if (gesture) finishGesture({pointerId:gesture.id}, true);
      return;
    }
    if (event.button !== 0) return;
    device.classList.add('devices-ready');
    suppressClick = false;
    gesture = {id:event.pointerId, x:event.clientX, y:event.clientY, index:selectedDevice, axis:null};
  });
  window.addEventListener('pointermove', event => {
    if (!gesture || event.pointerId !== gesture.id) return;
    const dx = event.clientX - gesture.x, dy = event.clientY - gesture.y;
    if (!gesture.axis && Math.max(Math.abs(dx), Math.abs(dy)) >= 8) {
      if (Math.abs(dx) > Math.abs(dy) * 1.25) gesture.axis = 'x';
      else if (Math.abs(dy) > Math.abs(dx)) gesture.axis = 'y';
    }
    if (gesture.axis !== 'x') return;
    suppressClick = true;
    if (!device.hasPointerCapture(event.pointerId)) device.setPointerCapture(event.pointerId);
    device.classList.add('is-dragging');
    if (!reduced.matches) {
      const limit = Math.min(32, device.clientWidth * .06);
      device.style.setProperty('--device-drag', `${clamp(dx * .35, -limit, limit)}px`);
    }
  }, {passive:true});
  window.addEventListener('pointerup', event => finishGesture(event));
  window.addEventListener('pointercancel', event => finishGesture(event, true));
  device.addEventListener('lostpointercapture', event => {
    // Touch starts with implicit capture on the device button. Its bubbled loss
    // when transferring capture to the stage is not a cancelled swipe.
    if (event.target === device) finishGesture(event, true);
  });
  device.addEventListener('click', event => {
    const wasDrag = suppressClick;
    suppressClick = false;
    if (wasDrag && event.detail !== 0) { event.preventDefault(); event.stopPropagation(); }
  }, true);

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
