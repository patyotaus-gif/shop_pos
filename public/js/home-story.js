/* Progressive enhancement: every chapter and image is readable without JS. */
(() => {
  'use strict';
  const story = document.querySelector('[data-product-story]');
  if (!story) return;
  const journeys = [...story.querySelectorAll("[data-journey]")];
  const picker = story.querySelector('.business-picker');
  const hero = document.querySelector('.cinematic-hero');
  const device = hero.querySelector('.hero-device');
  const showcase = hero.querySelector('[data-device-showcase]');
  const models = [...showcase.querySelectorAll('[data-model]')];
  const reduced = matchMedia('(prefers-reduced-motion: reduce)');
  const wide = matchMedia('(min-width: 1000px) and (min-height: 700px)');
  let queued = false;
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

  function selectJourney(type) {
    journeys.forEach(panel => { panel.hidden = panel.dataset.journey !== type; });
    picker.querySelectorAll('button').forEach(button => {
      button.setAttribute('aria-pressed', String(button.dataset.business === type));
    });
  }
  function selectHashJourney() {
    const panel = document.getElementById(location.hash.slice(1))?.closest('[data-journey]');
    if (panel) selectJourney(panel.dataset.journey);
    return panel;
  }
  picker.addEventListener('click', event => {
    const button = event.target.closest('button[data-business]');
    if (button) selectJourney(button.dataset.business);
  });
  selectJourney('restaurant');
  selectHashJourney();
  window.addEventListener('hashchange', () => {
    if (selectHashJourney()) document.getElementById(location.hash.slice(1)).scrollIntoView();
  });
  story.classList.add('story-ready');
  const restaurantPricing = story.querySelector('[data-restaurant-pricing]');
  if (restaurantPricing) restaurantPricing.href = '/pricing/?shop=restaurant';
  picker.hidden = false;

  const details = document.querySelector('.feature-details');
  const desktop = matchMedia('(min-width: 900px)');
  details.open = desktop.matches;

  function paintHero() {
    queued = false;
    if (!wide.matches || reduced.matches) {
      device.style.removeProperty('--hero-progress');
      return;
    }
    const rect = hero.getBoundingClientRect();
    device.style.setProperty('--hero-progress', String(clamp(-rect.top / rect.height, 0, 1)));
  }
  function schedule() {
    if (!queued) { queued = true; requestAnimationFrame(paintHero); }
  }
  window.addEventListener('scroll', schedule, {passive:true});
  window.addEventListener('resize', schedule, {passive:true});
  reduced.addEventListener('change', schedule);
  schedule();
})();
