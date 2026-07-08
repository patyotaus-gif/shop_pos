// Cart state + cart drawer UI. State functions are DOM-free so Node can
// test them; all DOM access lives in initCartUI/renderCartUI.
import { escHtml, fmtBaht } from './util.js';

const cart = {}; // productId -> { id, name, price, stock, quantity }
const listeners = [];

export function onCartChange(fn) { listeners.push(fn); }
function emit() { for (const fn of listeners) fn(); }

export function getQty(id) { return cart[id]?.quantity || 0; }
export function items() { return Object.values(cart); }
export function count() { return items().reduce((s, i) => s + i.quantity, 0); }
export function total() { return items().reduce((s, i) => s + i.price * i.quantity, 0); }

// Absolute set, clamped to [0, stock]. meta = { name, price, stock } is
// required the first time a product enters the cart.
export function setQty(id, qty, meta) {
  const existing = cart[id];
  const stock = existing ? existing.stock : (meta?.stock ?? 0);
  const q = Math.max(0, Math.min(qty, stock));
  if (q <= 0) {
    delete cart[id];
  } else if (existing) {
    existing.quantity = q;
  } else {
    cart[id] = { id, name: meta.name, price: meta.price, stock: meta.stock, quantity: q };
  }
  emit();
}

export function addOne(id, meta) { setQty(id, getQty(id) + 1, meta); }

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
  // +/- buttons inside the drawer (event delegation)
  document.getElementById('cartItems').addEventListener('click', (e) => {
    const btn = e.target.closest('button[data-id]');
    if (!btn) return;
    setQty(btn.dataset.id, getQty(btn.dataset.id) + Number(btn.dataset.delta));
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
  cartEl.innerHTML = list.map((item) => `
    <div class="cart-item">
      <div>
        <div class="cart-item-name">${escHtml(item.name)}</div>
        <div class="cart-item-price">${fmtBaht(item.price)} × ${item.quantity} = ${fmtBaht(item.price * item.quantity)}</div>
      </div>
      <div class="qty-controls">
        <button class="qty-btn" data-id="${item.id}" data-delta="-1">−</button>
        <span class="qty-num">${item.quantity}</span>
        <button class="qty-btn" data-id="${item.id}" data-delta="1">+</button>
      </div>
    </div>`).join('');
}
