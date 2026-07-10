// Cart state + cart drawer UI. State functions are DOM-free so Node can
// test them; all DOM access lives in initCartUI/renderCartUI.
//
// A cart LINE is keyed by productId + its sorted option ids, so the same
// dish with different add-ons stays on separate lines (mirrors the Dart
// modifiersEqual rule). Products with no add-ons key by productId alone,
// preserving the original merge-by-product behaviour.
import { escHtml, fmtBaht } from './util.js';

const cart = {}; // lineKey -> { key, id, name, price, stock, quantity, optionIds, modifiers, notes }
const listeners = [];

export function onCartChange(fn) { listeners.push(fn); }
function emit() { for (const fn of listeners) fn(); }

export function lineKey(id, optionIds = []) {
  return optionIds.length ? id + '|' + [...optionIds].sort().join(',') : id;
}

export function items() { return Object.values(cart); }
export function count() { return items().reduce((s, i) => s + i.quantity, 0); }
export function total() { return items().reduce((s, i) => s + i.price * i.quantity, 0); }

// Total quantity of a product across all its lines — for the card badge +
// stock cap.
export function getQty(id) {
  return items().reduce((s, i) => (i.id === id ? s + i.quantity : s), 0);
}

// Absolute set on the PLAIN line (no add-ons), clamped to [0, stock].
// meta = { name, price, stock } required on first add. Kept for the card
// "+ เพิ่ม" button and upsell (both add plain lines).
export function setQty(id, qty, meta) {
  const key = id;
  const existing = cart[key];
  const stock = existing ? existing.stock : (meta?.stock ?? 0);
  const q = Math.max(0, Math.min(qty, stock));
  if (q <= 0) {
    delete cart[key];
  } else if (existing) {
    existing.quantity = q;
  } else {
    cart[key] = {
      key, id, name: meta.name, price: meta.price, stock: meta.stock,
      quantity: q, optionIds: [], modifiers: [], notes: '',
    };
  }
  emit();
}

export function addOne(id, meta) { setQty(id, cart[id]?.quantity ? cart[id].quantity + 1 : 1, meta); }

// Add a configured line (add-ons + optional note). qty is added to whatever
// that exact configuration already holds; total product qty is capped at
// stock. meta = { id, name, price(unit), stock, optionIds, modifiers, notes }.
export function addLine(meta, qty = 1) {
  const key = lineKey(meta.id, meta.optionIds);
  const existing = cart[key];
  const otherQty = getQty(meta.id) - (existing?.quantity ?? 0);
  const room = Math.max(0, meta.stock - otherQty);
  const q = Math.min((existing?.quantity ?? 0) + qty, room);
  if (q <= 0) { emit(); return; }
  if (existing) {
    existing.quantity = q;
    if (meta.notes) existing.notes = meta.notes;
  } else {
    cart[key] = {
      key, id: meta.id, name: meta.name, price: meta.price, stock: meta.stock,
      quantity: q, optionIds: meta.optionIds || [],
      modifiers: meta.modifiers || [], notes: meta.notes || '',
    };
  }
  emit();
}

// Absolute set on a specific line key (drawer +/−). Removes at 0.
export function setLineQty(key, qty) {
  const line = cart[key];
  if (!line) return;
  const otherQty = getQty(line.id) - line.quantity;
  const q = Math.max(0, Math.min(qty, line.stock - otherQty));
  if (q <= 0) delete cart[key]; else line.quantity = q;
  emit();
}

// ── Drawer UI ──
export function openCart() {
  document.getElementById('cartDrawer').classList.add('open');
  document.getElementById('cartOverlay').classList.add('open');
}
export function closeCart() {
  document.getElementById('cartDrawer').classList.remove('open');
  document.getElementById('cartOverlay').classList.remove('open');
}

export function initCartUI({ onCheckout }) {
  document.getElementById('cartBtn').addEventListener('click', openCart);
  document.getElementById('cartOverlay').addEventListener('click', closeCart);
  document.getElementById('checkoutBtn').addEventListener('click', () => {
    closeCart();
    onCheckout();
  });
  // +/- buttons inside the drawer (event delegation, per line key)
  document.getElementById('cartItems').addEventListener('click', (e) => {
    const btn = e.target.closest('button[data-key]');
    if (!btn) return;
    const line = cart[btn.dataset.key];
    if (line) setLineQty(btn.dataset.key, line.quantity + Number(btn.dataset.delta));
  });
  onCartChange(renderCartUI);
  renderCartUI();
}

function renderCartUI() {
  const list = items();
  document.getElementById('cartCount').textContent = count();
  document.getElementById('cartTotal').textContent = fmtBaht(total());
  document.getElementById('modalTotal').textContent = fmtBaht(total());
  document.getElementById('checkoutBtn').disabled = list.length === 0;

  const cartEl = document.getElementById('cartItems');
  if (!list.length) {
    cartEl.innerHTML = '<div class="empty-cart">ยังไม่มีสินค้าในตะกร้า</div>';
    return;
  }
  cartEl.innerHTML = list.map((item) => {
    const mods = (item.modifiers || []).map((m) => escHtml(m.optionName)).join(' · ');
    return `
    <div class="cart-item">
      <div>
        <div class="cart-item-name">${escHtml(item.name)}</div>
        ${mods ? `<div class="cart-item-mods">${mods}</div>` : ''}
        ${item.notes ? `<div class="cart-item-mods">📝 ${escHtml(item.notes)}</div>` : ''}
        <div class="cart-item-price">${fmtBaht(item.price)} × ${item.quantity} = ${fmtBaht(item.price * item.quantity)}</div>
      </div>
      <div class="qty-controls">
        <button class="qty-btn" data-key="${escHtml(item.key)}" data-delta="-1">−</button>
        <span class="qty-num">${item.quantity}</span>
        <button class="qty-btn" data-key="${escHtml(item.key)}" data-delta="1">+</button>
      </div>
    </div>`;
  }).join('');
}
