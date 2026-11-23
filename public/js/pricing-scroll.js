(() => {
  const row = document.querySelector('#plan-comparison');
  if (!row) return;
  const controls = row.previousElementSibling;
  const [previous, next] = controls.querySelectorAll('button');
  const epsilon = 1;

  function update() {
    const end = row.scrollWidth - row.clientWidth;
    if (end <= epsilon && controls.contains(document.activeElement)) row.focus({preventScroll: true});
    controls.hidden = end <= epsilon;
    row.tabIndex = controls.hidden ? -1 : 0;
    previous.setAttribute('aria-disabled', String(row.scrollLeft <= epsilon));
    next.setAttribute('aria-disabled', String(row.scrollLeft >= end - epsilon));
  }

  function move(direction) {
    const left = row.getBoundingClientRect().left;
    const end = row.scrollWidth - row.clientWidth;
    const stops = Array.from(row.children, card =>
      Math.min(end, row.scrollLeft + card.getBoundingClientRect().left - left));
    const target = direction > 0
      ? stops.find(x => x > row.scrollLeft + epsilon)
      : stops.reverse().find(x => x < row.scrollLeft - epsilon);
    if (target !== undefined) row.scrollTo({left: target,
      behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'instant' : 'smooth'});
  }

  controls.addEventListener('click', event => {
    const button = event.target.closest('[data-plan-step]');
    if (button && button.getAttribute('aria-disabled') !== 'true') move(Number(button.dataset.planStep));
  });
  row.addEventListener('keydown', event => {
    if (event.target !== row || !['ArrowLeft', 'ArrowRight'].includes(event.key)) return;
    event.preventDefault();
    move(event.key === 'ArrowRight' ? 1 : -1);
  });
  row.addEventListener('scroll', update, {passive: true});
  new ResizeObserver(update).observe(row);
  update();
})();
