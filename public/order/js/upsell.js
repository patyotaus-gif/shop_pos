// Pre-checkout upsell popup: the shop's pinned products + live promos the
// customer hasn't added yet. Shown at most once per page load; skipped
// silently when there are no candidates. DOM-free at import time.
import { escHtml, fmtBaht } from './util.js';
import { addOne, getQty } from './cart.js';

let shown = false;
let candidates = [];
let onContinue = null;
let continueLabel = 'ไปชำระเงินต่อ';

// Pure picker (Node-tested): products not in cart, in stock, pinned first
// then on-sale, capped at 4.
export function pickUpsell(products, inCartIds) {
  const inCart = new Set(inCartIds);
  return products
    .filter((p) => p.stock > 0 && !inCart.has(p.id) && (p.pinned || p.originalPrice))
    .sort((a, b) => (b.pinned === true ? 1 : 0) - (a.pinned === true ? 1 : 0))
    .slice(0, 4);
}

export function initUpsell({ products, label }) {
  candidates = products;
  if (label) continueLabel = label;
  document.getElementById('upsellSkip').addEventListener('click', proceed);
  document.getElementById('upsellOverlay').addEventListener('click', proceed);
  document.getElementById('upsellItems').addEventListener('click', (e) => {
    const btn = e.target.closest('button[data-id]');
    if (!btn) return;
    const p = candidates.find((x) => x.id === btn.dataset.id);
    if (!p) return;
    addOne(p.id, { name: p.name, price: p.price, stock: p.stock });
    btn.disabled = true;
    btn.textContent = '✓ เพิ่มแล้ว';
  });
}

// Gate the checkout tap: first tap may show the popup; the popup's actions
// (or having nothing to show) fall through to `next`.
export function maybeShowUpsell(next) {
  if (shown) { next(); return; }
  shown = true;
  const picks = pickUpsell(candidates, Object.keys(cartIds()));
  if (!picks.length) { next(); return; }
  onContinue = next;

  document.getElementById('upsellItems').innerHTML = picks.map((p) => `
    <div class="upsell-item">
      <div class="card-img upsell-img">
        <span class="img-fallback" aria-hidden="true">🧺</span>
        ${p.imageUrl ? `<img src="${escHtml(p.imageUrl)}" alt="" loading="lazy" onerror="this.remove()">` : ''}
      </div>
      <div class="upsell-info">
        <div class="upsell-name">${escHtml(p.name)}</div>
        <div class="product-price">${fmtBaht(p.price)}${p.originalPrice ? `<span class="product-price-original">${fmtBaht(p.originalPrice)}</span>` : ''}</div>
      </div>
      <button class="upsell-add" type="button" data-id="${escHtml(p.id)}">+ เพิ่ม</button>
    </div>`).join('');
  document.getElementById('upsellSkip').textContent = continueLabel;
  document.getElementById('upsellSheet').classList.add('open');
  document.getElementById('upsellOverlay').classList.add('open');
}

function proceed() {
  document.getElementById('upsellSheet').classList.remove('open');
  document.getElementById('upsellOverlay').classList.remove('open');
  const next = onContinue;
  onContinue = null;
  if (next) next();
}

function cartIds() {
  const ids = {};
  for (const p of candidates) if (getQty(p.id) > 0) ids[p.id] = true;
  return ids;
}
