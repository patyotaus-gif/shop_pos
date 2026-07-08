# Product Selling UI Redesign Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rewrite the customer order page (`public/order/`) as static split files with Woolworths-style shopping UX (promo badges, per-card Add button, quantity bottom sheet), and upgrade the POS category picker from text chips to image cards.

**Architecture:** The order page becomes `index.html` + `order.css` + ES modules under `js/` (`util.js`, `cart.js`, `catalog.js`, `payment.js`, `main.js`). Payment/App Check logic is moved verbatim, not rewritten. The POS change is confined to one widget block in `pos_screen.dart` plus a `discountPercent` getter on `Product`.

**Tech Stack:** Vanilla HTML/CSS/JS (ES modules, no build step), Firebase Hosting rewrites → Cloud Functions, Flutter (POS). Tests: Node script with `node:assert` for web modules; `flutter test` for Dart.

**Spec:** `docs/superpowers/specs/2026-07-08-product-selling-ui-redesign-design.md`

## Global Constraints

- Brand colors: burgundy `#7A1F2B`, burgundy-hover `#5C1820`, cream `#F5F1EC` — NOT Woolworths green. Save-strip yellow: `#FDE047` bg / `#713F12` text.
- No build step, no framework, no new runtime dependencies. `qrcode.min.js` stays as a classic script (global `QRCode`).
- App Check contract: the inline module in `index.html` sets `window.__appCheckToken` BEFORE starting the page, so the first `/api/shopPublic` call carries a token (endpoint is enforced). All API calls go through `apiFetch` which attaches `X-Firebase-AppCheck`.
- Payment logic (PromptPay EMVCo payload, CRC16, slip compression, `verifyPromptPaySlip`) is a **verbatim move** from the old inline script — function bodies must not change.
- Promo badge only when `originalPrice > price` AND rounded percent ≥ 1. Percent = `round((1 − price/originalPrice) × 100)`; saving = `originalPrice − price`.
- Quantity strip range: 1 … `min(stock, 20)`. Quantity semantics in the sheet are **absolute set**.
- Thai copy (exact strings): "+ เพิ่ม", "เพิ่ม N ลงตะกร้า", "อัปเดตเป็น N ชิ้น", "เอาออกจากตะกร้า", "ลด X%", "ประหยัด ฿Y", "หมด", "เหลือ N".
- `escHtml` at every web render site that injects product/customer strings.
- All web JS modules must be importable in Node (no DOM/`location` access at module top level) so the smoke test can run.
- Backend untouched: no changes under `functions/`, no Firestore rules changes.

---

### Task 1: `util.js` + `cart.js` + Node smoke test

**Files:**
- Create: `public/order/js/util.js`
- Create: `public/order/js/cart.js`
- Test: `scripts/test_order_page.mjs`

**Interfaces:**
- Consumes: nothing (first task).
- Produces:
  - `util.js`: `shopId: string|null`, `escHtml(str): string`, `fmtBaht(n): string` (`"฿10.00"`), `apiFetch(url, opts): Promise<Response>`
  - `cart.js`: `getQty(id): number`, `items(): Array<{id,name,price,stock,quantity}>`, `count(): number`, `total(): number`, `setQty(id, qty, meta?)` (absolute, clamps to `[0, stock]`, `meta={name,price,stock}` required on first add), `addOne(id, meta)`, `onCartChange(fn)`, `initCartUI({onCheckout})`, `openCart()`, `closeCart()`

- [ ] **Step 1: Write the failing test**

Create `scripts/test_order_page.mjs`:

```js
// Node smoke tests for the order-page ES modules (no browser needed).
// Run: node scripts/test_order_page.mjs
import assert from 'node:assert/strict';

const { escHtml, fmtBaht, shopId } = await import('../public/order/js/util.js');
const cartMod = await import('../public/order/js/cart.js');

// ── util.js ──
assert.equal(escHtml('a<b>&"c'), 'a&lt;b&gt;&amp;&quot;c');
assert.equal(fmtBaht(10), '฿10.00');
assert.equal(fmtBaht(1.5), '฿1.50');
assert.equal(shopId, null); // no `location` in Node

// ── cart.js state ──
const { setQty, addOne, getQty, items, count, total, onCartChange } = cartMod;
let changes = 0;
onCartChange(() => changes++);

addOne('p1', { name: 'มาม่า', price: 10, stock: 3 });
assert.equal(getQty('p1'), 1);
addOne('p1', { name: 'มาม่า', price: 10, stock: 3 });
addOne('p1', { name: 'มาม่า', price: 10, stock: 3 });
addOne('p1', { name: 'มาม่า', price: 10, stock: 3 }); // 4th add — clamped
assert.equal(getQty('p1'), 3, 'addOne clamps at stock');

setQty('p2', 5, { name: 'น้ำปลา', price: 25, stock: 2 });
assert.equal(getQty('p2'), 2, 'setQty clamps at stock');

assert.equal(count(), 5);
assert.equal(total(), 3 * 10 + 2 * 25);

setQty('p2', 0);
assert.equal(getQty('p2'), 0);
assert.equal(items().length, 1, 'qty 0 removes the item');

assert.ok(changes >= 5, 'listeners fire on every change');

console.log('✓ util.js + cart.js tests passed');
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node scripts/test_order_page.mjs`
Expected: FAIL — `Cannot find module ... public/order/js/util.js`

- [ ] **Step 3: Write `util.js`**

Create `public/order/js/util.js`:

```js
// Shared helpers for the order page. Keep this module DOM-free at import
// time so the Node smoke test (scripts/test_order_page.mjs) can load it.

// `location` is absent in Node — guard so tests can import this module.
export const shopId = typeof location === 'undefined'
  ? null
  : new URLSearchParams(location.search).get('shop');

export function escHtml(str) {
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}

export const fmtBaht = (n) => '฿' + Number(n).toFixed(2);

// Wrap fetch to attach a Firebase App Check token (reCAPTCHA v3) when the
// inline SDK module in index.html has one ready. The /api endpoints enforce
// App Check, so the token is what keeps real visitors working.
export async function apiFetch(url, opts = {}) {
  const headers = { ...(opts.headers || {}) };
  try {
    const t = window.__appCheckToken ? await window.__appCheckToken() : null;
    if (t) headers['X-Firebase-AppCheck'] = t;
  } catch (_) {}
  return fetch(url, { ...opts, headers });
}
```

- [ ] **Step 4: Write `cart.js`**

Create `public/order/js/cart.js`:

```js
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
```

- [ ] **Step 5: Run test to verify it passes**

Run: `node scripts/test_order_page.mjs`
Expected: `✓ util.js + cart.js tests passed`

- [ ] **Step 6: Commit**

```bash
git add public/order/js/util.js public/order/js/cart.js scripts/test_order_page.mjs
git commit -m "feat(order-web): util + cart modules with node smoke tests"
```

---

### Task 2: `catalog.js` — product grid + promo badges + quantity bottom sheet

**Files:**
- Create: `public/order/js/catalog.js`
- Modify (append tests): `scripts/test_order_page.mjs`

**Interfaces:**
- Consumes: `cart.js` → `addOne(id, meta)`, `getQty(id)`, `setQty(id, qty, meta)`, `onCartChange(fn)`; `util.js` → `escHtml`, `fmtBaht`.
- Produces: `promoInfo(price, originalPrice): {percent:number, saving:number}|null`, `renderProducts(products)` (array from `shopPublic`: `{id,name,price,originalPrice?,stock,category,imageUrl}`), `initCatalog()` (wires grid + sheet events; call once before `renderProducts`).
- DOM ids this module owns (defined in Task 4's `index.html`): `products`, `sheetOverlay`, `productSheet`, `sheetBody`, `sheetQty`, `sheetPrimary`, `sheetRemove`.

- [ ] **Step 1: Append the failing tests**

Append to `scripts/test_order_page.mjs` (before the final `console.log`… just append at end):

```js
// ── catalog.js promoInfo ──
const { promoInfo } = await import('../public/order/js/catalog.js');

assert.deepEqual(promoInfo(10, 20), { percent: 50, saving: 10 });
assert.deepEqual(promoInfo(1.25, 3), { percent: 58, saving: 1.75 });
assert.equal(promoInfo(10, undefined), null, 'no originalPrice → no promo');
assert.equal(promoInfo(10, 0), null);
assert.equal(promoInfo(20, 20), null, 'equal price → no promo');
assert.equal(promoInfo(25, 20), null, 'originalPrice below price → no promo');
assert.equal(promoInfo(996, 1000), null, 'rounds to 0% → no badge');

console.log('✓ catalog.js promoInfo tests passed');
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node scripts/test_order_page.mjs`
Expected: FAIL — `Cannot find module ... catalog.js`

- [ ] **Step 3: Write `catalog.js`**

Create `public/order/js/catalog.js`:

```js
// Product grid cards + product quantity bottom sheet.
// DOM-free at import time (Node smoke test imports this module).
import { escHtml, fmtBaht } from './util.js';
import { addOne, getQty, setQty, onCartChange } from './cart.js';

const byId = {};      // productId -> product from shopPublic
let sheetProduct = null; // product currently shown in the sheet
let sheetQtySelected = 1;

// Promo badge math. Badge only when originalPrice > price and the rounded
// percent is at least 1 (guards tiny/garbage discounts).
export function promoInfo(price, originalPrice) {
  const orig = Number(originalPrice || 0);
  const p = Number(price || 0);
  if (!orig || orig <= p) return null;
  const percent = Math.round((1 - p / orig) * 100);
  if (percent < 1) return null;
  return { percent, saving: orig - p };
}

const meta = (p) => ({ name: p.name, price: p.price, stock: p.stock });

export function initCatalog() {
  document.getElementById('products').addEventListener('click', (e) => {
    const card = e.target.closest('.product-card');
    if (!card) return;
    const p = byId[card.dataset.id];
    if (!p || p.stock <= 0) return;
    if (e.target.closest('.add-btn')) {
      addOne(p.id, meta(p));       // Add button = instant +1
      return;
    }
    openProductSheet(p.id);        // anywhere else on the card = sheet
  });
  document.getElementById('sheetOverlay').addEventListener('click', closeProductSheet);
  document.getElementById('sheetQty').addEventListener('click', (e) => {
    const btn = e.target.closest('.qty-opt');
    if (!btn) return;
    sheetQtySelected = Number(btn.dataset.q);
    renderSheetQty();
  });
  document.getElementById('sheetPrimary').addEventListener('click', () => {
    if (!sheetProduct) return;
    setQty(sheetProduct.id, sheetQtySelected, meta(sheetProduct));
    closeProductSheet();
  });
  document.getElementById('sheetRemove').addEventListener('click', () => {
    if (!sheetProduct) return;
    setQty(sheetProduct.id, 0);
    closeProductSheet();
  });
  onCartChange(refreshCards);
}

export function renderProducts(products) {
  const container = document.getElementById('products');
  for (const p of products) byId[p.id] = p;
  if (!products.length) {
    container.innerHTML =
      '<p style="grid-column:1/-1;text-align:center;color:#A89E94;padding:40px">ยังไม่มีสินค้า</p>';
    return;
  }
  container.innerHTML = products.map((p) => {
    const out = p.stock <= 0;
    const promo = promoInfo(p.price, p.originalPrice);
    return `
      <div class="product-card${out ? ' out-of-stock' : ''}" data-id="${escHtml(p.id)}">
        <div class="qty-badge" hidden>0</div>
        <div class="card-img">
          <span class="img-fallback" aria-hidden="true">🧺</span>
          ${p.imageUrl ? `<img src="${escHtml(p.imageUrl)}" alt="" loading="lazy" onerror="this.remove()">` : ''}
          ${promo ? `<span class="badge-percent">ลด<br>${promo.percent}%</span>` : ''}
        </div>
        ${promo ? `<div class="save-strip">ประหยัด ${fmtBaht(promo.saving)}</div>` : ''}
        <div class="product-name">${escHtml(p.name)}</div>
        <div>
          <div class="product-price">${fmtBaht(p.price)}${promo ? `<span class="product-price-original">${fmtBaht(p.originalPrice)}</span>` : ''}</div>
          <div class="product-stock${!out && p.stock <= 5 ? ' low' : ''}">
            ${out ? '❌ หมด' : `📦 เหลือ ${p.stock}`}
          </div>
        </div>
        <button class="add-btn" type="button" ${out ? 'disabled' : ''}>+ เพิ่ม</button>
      </div>`;
  }).join('');
  refreshCards();
}

// Sync per-card qty badges + Add-button disabled state with the cart.
function refreshCards() {
  document.querySelectorAll('.product-card').forEach((card) => {
    const p = byId[card.dataset.id];
    if (!p) return;
    const qty = getQty(p.id);
    const badge = card.querySelector('.qty-badge');
    badge.hidden = qty === 0;
    badge.textContent = qty;
    const addBtn = card.querySelector('.add-btn');
    addBtn.disabled = p.stock <= 0 || qty >= p.stock;
  });
}

// ── Product bottom sheet ──
function openProductSheet(id) {
  const p = byId[id];
  if (!p) return;
  sheetProduct = p;
  sheetQtySelected = Math.max(1, getQty(id) || 1);

  const promo = promoInfo(p.price, p.originalPrice);
  document.getElementById('sheetBody').innerHTML = `
    <div class="sheet-product">
      <div class="card-img sheet-img">
        <span class="img-fallback" aria-hidden="true">🧺</span>
        ${p.imageUrl ? `<img src="${escHtml(p.imageUrl)}" alt="" onerror="this.remove()">` : ''}
      </div>
      <div class="sheet-info">
        ${promo ? `<div class="save-strip">ประหยัด ${fmtBaht(promo.saving)}</div>` : ''}
        <div class="sheet-name">${escHtml(p.name)}</div>
        <div class="product-price">${fmtBaht(p.price)}${promo ? `<span class="product-price-original">${fmtBaht(p.originalPrice)}</span>` : ''}</div>
        <div class="product-stock${p.stock <= 5 ? ' low' : ''}">📦 เหลือ ${p.stock}</div>
      </div>
    </div>`;

  renderSheetQty();
  document.getElementById('sheetRemove').hidden = getQty(id) === 0;
  document.getElementById('productSheet').classList.add('open');
  document.getElementById('sheetOverlay').classList.add('open');
}

function closeProductSheet() {
  sheetProduct = null;
  document.getElementById('productSheet').classList.remove('open');
  document.getElementById('sheetOverlay').classList.remove('open');
}

function renderSheetQty() {
  const p = sheetProduct;
  if (!p) return;
  const maxQ = Math.min(p.stock, 20); // spec: strip range 1..min(stock, 20)
  sheetQtySelected = Math.min(sheetQtySelected, maxQ);

  const strip = document.getElementById('sheetQty');
  strip.innerHTML = Array.from({ length: maxQ }, (_, i) => i + 1)
    .map((q) => `<button class="qty-opt${q === sheetQtySelected ? ' selected' : ''}" type="button" data-q="${q}">${q}</button>`)
    .join('');
  strip.querySelector('.qty-opt.selected')?.scrollIntoView({ inline: 'center', block: 'nearest' });

  const inCart = getQty(p.id) > 0;
  document.getElementById('sheetPrimary').textContent = inCart
    ? `อัปเดตเป็น ${sheetQtySelected} ชิ้น`
    : `เพิ่ม ${sheetQtySelected} ลงตะกร้า`;
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `node scripts/test_order_page.mjs`
Expected: both `✓` lines print, exit 0.

- [ ] **Step 5: Commit**

```bash
git add public/order/js/catalog.js scripts/test_order_page.mjs
git commit -m "feat(order-web): catalog module — promo badges, add button, qty sheet"
```

---

### Task 3: `payment.js` — verbatim move of order form + PromptPay + slip upload

**Files:**
- Create: `public/order/js/payment.js`
- Modify (append tests): `scripts/test_order_page.mjs`

**Interfaces:**
- Consumes: `util.js` → `shopId`, `apiFetch`; `cart.js` → `items()`.
- Produces: `initPayment()` (wires modal/pay/slip buttons), `openOrderModal()`, `buildPromptPayPayload(rawId, amount): string`, `crc16(data): string` (exported for tests).
- DOM ids owned: `modalOverlay`, `customerName`, `customerPhone`, `payBtn`, `cancelBtn`, `payOverlay`, `payQrCanvas`, `payAmount`, `payCentsNote`, `payReceiver`, `payReceiverId`, `paySlipBtn`, `paySlipStatus`, `slipFileInput`, `payCancelBtn`.

- [ ] **Step 1: Append the failing tests**

Append to `scripts/test_order_page.mjs`:

```js
// ── payment.js — PromptPay payload (moved verbatim; verify it still works) ──
const { crc16, buildPromptPayPayload } = await import('../public/order/js/payment.js');

// CRC-16/CCITT-FALSE known-answer test
assert.equal(crc16('123456789'), '29B1');

// Phone (10 digits) → tag 01, 0066 + drop leading 0
const phone = buildPromptPayPayload('081-234-5678', 100);
assert.ok(phone.startsWith('000201010212'), 'static header + dynamic (amount) type');
assert.ok(phone.includes('0016A000000677010111'), 'PromptPay AID');
assert.ok(phone.includes('01130066812345678'), 'phone proxy value');
assert.ok(phone.includes('5802TH'), 'country TH');
assert.ok(phone.includes('5303764'), 'currency 764');
assert.ok(phone.includes('5406100.00'), 'amount 100.00');
assert.match(phone, /6304[0-9A-F]{4}$/, 'trailing CRC');

// National ID (13 digits) → tag 02
const nid = buildPromptPayPayload('1234567890123', 50);
assert.ok(nid.includes('02131234567890123'), 'national-id proxy');

// Invalid length throws
assert.throws(() => buildPromptPayPayload('12345', 10));

console.log('✓ payment.js PromptPay tests passed');
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node scripts/test_order_page.mjs`
Expected: FAIL — `Cannot find module ... payment.js`

- [ ] **Step 3: Write `payment.js`**

Create `public/order/js/payment.js`. All function bodies below are copied verbatim from the old `public/order/index.html` inline script; only the module plumbing (imports, exports, `initPayment` event wiring, `items()` instead of the old `cart` object) is new:

```js
// Order form + PromptPay payment + slip verification.
// Logic moved VERBATIM from the old public/order/index.html inline script —
// do not "improve" payload/CRC/compression code here.
import { shopId, apiFetch } from './util.js';
import { items } from './cart.js';

let pendingOrder = null;

export function openOrderModal() {
  document.getElementById('modalOverlay').classList.add('open');
}
function closeOrderModal() {
  document.getElementById('modalOverlay').classList.remove('open');
}

export function initPayment() {
  document.getElementById('payBtn').addEventListener('click', submitOrder);
  document.getElementById('cancelBtn').addEventListener('click', closeOrderModal);
  document.getElementById('paySlipBtn').addEventListener('click', () =>
    document.getElementById('slipFileInput').click());
  document.getElementById('slipFileInput').addEventListener('change', uploadSlip);
  document.getElementById('payCancelBtn').addEventListener('click', cancelPay);
}

// ── PromptPay EMVCo QR payload (mirrors lib/utils/promptpay_qr.dart) ──
function tlv(tag, value) {
  return tag + String(value.length).padStart(2, '0') + value;
}
export function crc16(data) {
  let crc = 0xFFFF;
  for (let i = 0; i < data.length; i++) {
    crc ^= data.charCodeAt(i) << 8;
    for (let b = 0; b < 8; b++) {
      crc = (crc & 0x8000) ? ((crc << 1) ^ 0x1021) : (crc << 1);
      crc &= 0xFFFF;
    }
  }
  return crc.toString(16).toUpperCase().padStart(4, '0');
}
export function buildPromptPayPayload(rawId, amount) {
  const digits = String(rawId).replace(/\D/g, '');
  let tag, value;
  if (digits.length === 10)      { tag = '01'; value = '0066' + digits.substring(1); }
  else if (digits.length === 13) { tag = '02'; value = digits; }
  else if (digits.length === 15) { tag = '03'; value = digits; }
  else throw new Error('Invalid PromptPay ID length: ' + digits.length);

  let pp = '';
  pp += tlv('00', '01');
  pp += tlv('01', amount != null ? '12' : '11');
  pp += tlv('29', tlv('00', 'A000000677010111') + tlv(tag, value));
  pp += tlv('58', 'TH');
  pp += tlv('53', '764');
  if (amount != null) pp += tlv('54', Number(amount).toFixed(2));
  pp += '6304' + crc16(pp + '6304');
  return pp;
}

// ── Submit order ──
async function submitOrder() {
  const name = document.getElementById('customerName').value.trim();
  const phone = document.getElementById('customerPhone').value.trim();
  if (!name) { alert('กรุณากรอกชื่อ'); return; }
  if (!phone) { alert('กรุณากรอกเบอร์โทร'); return; }

  const orderItems = items().map((i) => ({
    productId: i.id,
    productName: i.name,
    price: i.price,
    quantity: i.quantity,
  }));

  const payBtn = document.getElementById('payBtn');
  payBtn.disabled = true;
  payBtn.innerHTML = '<span class="spinner"></span>กำลังดำเนินการ...';

  try {
    const res = await apiFetch('/api/createPromptPayOrder', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ shopId, customerName: name, customerPhone: phone, items: orderItems }),
    });
    const data = await res.json();
    if (!res.ok || !data.orderId) {
      alert('เกิดข้อผิดพลาด: ' + (data.error || 'กรุณาลองใหม่'));
      return;
    }
    pendingOrder = data;
    closeOrderModal();
    showPaymentScreen(data);
  } catch (e) {
    alert('เชื่อมต่อไม่ได้ กรุณาลองใหม่');
  } finally {
    payBtn.disabled = false;
    payBtn.textContent = 'ชำระเงิน';
  }
}

function showPaymentScreen({ finalAmount, total, promptpayId, promptpayName }) {
  const payload = buildPromptPayPayload(promptpayId, finalAmount);
  const qrEl = document.getElementById('payQrCanvas');
  qrEl.innerHTML = '';  // wipe any previous render
  new QRCode(qrEl, {
    text: payload,
    width: 240,
    height: 240,
    correctLevel: QRCode.CorrectLevel.M,
  });
  document.getElementById('payAmount').textContent =
    '฿' + Number(finalAmount).toFixed(2);
  const centsNote = (finalAmount > total)
    ? `ยอดสินค้า ฿${total.toFixed(2)} + เศษ ${Math.round((finalAmount - total) * 100)} สตางค์ (ใช้แยกออเดอร์)`
    : '';
  document.getElementById('payCentsNote').textContent = centsNote;
  document.getElementById('payReceiver').textContent =
    promptpayName || 'ผู้รับเงิน';
  document.getElementById('payReceiverId').textContent =
    'PromptPay ID: ' + maskPromptPayId(promptpayId);
  document.getElementById('payOverlay').classList.add('open');
}

function maskPromptPayId(id) {
  const digits = String(id).replace(/\D/g, '');
  if (digits.length <= 4) return digits;
  return digits.slice(0, 3) + '*'.repeat(digits.length - 6) + digits.slice(-3);
}

async function uploadSlip(event) {
  const file = event.target.files?.[0];
  event.target.value = '';  // allow re-picking the same file later
  if (!file || !pendingOrder) return;

  const slipBtn = document.getElementById('paySlipBtn');
  const status = document.getElementById('paySlipStatus');
  slipBtn.disabled = true;
  slipBtn.innerHTML = '<span class="spinner"></span>กำลังตรวจสลิป...';
  status.className = 'busy';
  status.textContent = 'อ่าน QR + ตรวจยอดเงิน...';

  try {
    // Convert image → base64. Compress large images first so we don't
    // POST a 10MB payload.
    const slipBase64 = await fileToBase64Compressed(file, 1600);

    const res = await apiFetch('/api/verifyPromptPaySlip', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        shopId,
        orderId: pendingOrder.orderId,
        slipBase64,
      }),
    });
    const data = await res.json();

    if (!res.ok || data.success === false) {
      status.className = 'err';
      status.textContent = data.reason || data.error || 'ตรวจสลิปไม่สำเร็จ';
      slipBtn.disabled = false;
      slipBtn.innerHTML = '📷 ลองสลิปใหม่อีกครั้ง';
      return;
    }

    status.className = 'ok';
    status.textContent = '✓ ยืนยันสำเร็จ! กำลังพาคุณไปหน้าออเดอร์...';
    setTimeout(() => {
      window.location.href = `/order/success/?order=${pendingOrder.orderId}&auto=1`;
    }, 1200);
  } catch (e) {
    status.className = 'err';
    status.textContent = 'อัปโหลดล้มเหลว — ลองอีกครั้ง';
    slipBtn.disabled = false;
    slipBtn.innerHTML = '📷 อัปโหลดสลิป — ยืนยันอัตโนมัติ';
  }
}

// Down-scale slips so the server doesn't choke on multi-MB phone photos.
function fileToBase64Compressed(file, maxDim) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = (e) => {
      const img = new Image();
      img.onload = () => {
        const scale = Math.min(1, maxDim / Math.max(img.width, img.height));
        const w = Math.round(img.width * scale);
        const h = Math.round(img.height * scale);
        const canvas = document.createElement('canvas');
        canvas.width = w; canvas.height = h;
        canvas.getContext('2d').drawImage(img, 0, 0, w, h);
        // 0.85 quality JPEG — small but QR codes still parse cleanly.
        resolve(canvas.toDataURL('image/jpeg', 0.85));
      };
      img.onerror = () => reject(new Error('image load failed'));
      img.src = e.target.result;
    };
    reader.onerror = () => reject(new Error('file read failed'));
    reader.readAsDataURL(file);
  });
}

function cancelPay() {
  if (!confirm('ยกเลิกออเดอร์นี้?')) return;
  document.getElementById('payOverlay').classList.remove('open');
  pendingOrder = null;
}
```

Note one intentional difference from the old code: the old `submitOrder` re-enabled the button in early-return paths AND in `finally` (redundant). The `finally` block covers all paths, so the early returns simply `return` — behavior is identical.

- [ ] **Step 4: Run test to verify it passes**

Run: `node scripts/test_order_page.mjs`
Expected: all three `✓` lines, exit 0.

- [ ] **Step 5: Commit**

```bash
git add public/order/js/payment.js scripts/test_order_page.mjs
git commit -m "feat(order-web): payment module (verbatim move) + promptpay payload tests"
```

---

### Task 4: `order.css` + new `index.html` + `main.js` — assemble the page

**Files:**
- Create: `public/order/order.css`
- Create: `public/order/js/main.js`
- Rewrite: `public/order/index.html` (full replacement)

**Interfaces:**
- Consumes: `initCatalog`/`renderProducts` (catalog.js), `initCartUI` (cart.js), `initPayment`/`openOrderModal` (payment.js), `shopId`/`apiFetch` (util.js).
- Produces: `window.__startOrderPage` (called by the inline App Check module once `window.__appCheckToken` is set).

- [ ] **Step 1: Write `main.js`**

Create `public/order/js/main.js`:

```js
// Entry point. The inline App Check module in index.html calls
// window.__startOrderPage() AFTER setting window.__appCheckToken, so the
// first /api/shopPublic call always carries a token (endpoint is enforced).
import { shopId, apiFetch } from './util.js';
import { initCatalog, renderProducts } from './catalog.js';
import { initCartUI } from './cart.js';
import { initPayment, openOrderModal } from './payment.js';

function showError(msg) {
  document.getElementById('loading').style.display = 'none';
  const el = document.getElementById('error');
  el.style.display = 'block';
  el.textContent = msg;
}

async function start() {
  if (!shopId) { showError('ลิงก์ไม่ถูกต้อง — ไม่พบ shop ID'); return; }
  initCatalog();
  initCartUI({ onCheckout: openOrderModal });
  initPayment();
  try {
    // Single endpoint returns the public shop name + products (whitelisted
    // fields only; promo price applied server-side).
    const res = await apiFetch(`/api/shopPublic?shop=${shopId}`);
    if (!res.ok) { showError('ไม่พบร้านค้านี้'); return; }
    const data = await res.json();
    const shopName = data.name || 'ร้านค้า';
    document.getElementById('shopName').textContent = shopName;
    document.title = `สั่งสินค้า — ${shopName}`;
    renderProducts(data.products || []);
    document.getElementById('loading').style.display = 'none';
    document.getElementById('products').style.display = 'grid';
  } catch (e) {
    showError('เกิดข้อผิดพลาดในการโหลดข้อมูล');
  }
}

window.__startOrderPage = start;
```

- [ ] **Step 2: Write `order.css`**

Create `public/order/order.css` (design tokens, header, drawer, modal, and PromptPay styles carried over from the old inline `<style>`; product-card section redesigned; product-sheet + qty-strip new):

```css
/* ── BRAND DESIGN TOKENS (Pokpok burgundy + cream) ── */
:root {
  --burgundy: #7A1F2B;
  --burgundy-hover: #5C1820;
  --burgundy-dim: #F0E2E4;
  --cream: #F5F1EC;
  --surface: #FFFFFF;
  --text-dark: #1F1A1B;
  --text-mid: #6B5E60;
  --border-color: #E5DDD3;

  --primary: var(--burgundy);
  --primary-hover: var(--burgundy-hover);
  --primary-light: var(--burgundy-dim);
  --bg-main: var(--cream);
  --text-main: var(--text-dark);
  --text-muted: var(--text-mid);

  --radius-sm: 8px;
  --radius-md: 12px;
  --radius-lg: 20px;
  --shadow-sm: 0 2px 8px rgba(31, 26, 27, 0.04);
  --shadow-md: 0 10px 25px -5px rgba(31, 26, 27, 0.08), 0 8px 10px -6px rgba(31, 26, 27, 0.08);
  --transition: all 0.2s cubic-bezier(0.4, 0, 0.2, 1);
}

* { box-sizing: border-box; margin: 0; padding: 0; }
body {
  font-family: 'IBM Plex Sans Thai', system-ui, -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
  font-weight: 400;
  background: var(--cream);
  color: var(--text-dark);
  -webkit-font-smoothing: antialiased;
}

/* ── GLASSMORPHISM HEADER ── */
header {
  background: rgba(245, 241, 236, 0.75);
  backdrop-filter: blur(10px);
  -webkit-backdrop-filter: blur(10px);
  color: var(--text-dark);
  padding: 14px 20px;
  position: sticky;
  top: 0;
  z-index: 100;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  border-bottom: 1px solid var(--border-color);
}
.brand { display: flex; align-items: center; gap: 12px; min-width: 0; }
.brand-mark { width: 36px; height: 36px; flex-shrink: 0; display: inline-flex; align-items: center; justify-content: center; }
.brand-mark svg { width: 100%; height: 100%; display: block; }
header h1 {
  font-size: 17px; font-weight: 500; letter-spacing: 0.2px;
  color: var(--text-dark);
  white-space: nowrap; overflow: hidden; text-overflow: ellipsis;
}

#cartBtn {
  background: var(--surface); color: var(--text-mid);
  border: 1px solid var(--border-color); border-radius: 12px;
  padding: 8px 14px;
  font-family: 'IBM Plex Sans Thai', sans-serif; font-size: 14px; font-weight: 500;
  cursor: pointer; display: flex; align-items: center; gap: 8px;
  transition: var(--transition); flex-shrink: 0; position: relative;
}
#cartBtn:hover { border-color: var(--burgundy); color: var(--burgundy); }
#cartCount {
  background: var(--burgundy); color: var(--cream);
  border-radius: 100px; min-width: 20px; height: 20px; padding: 0 6px;
  font-size: 11px; font-weight: 600;
  display: flex; align-items: center; justify-content: center;
  transition: var(--transition);
}
#cartBtn:hover #cartCount { background: var(--burgundy-hover); }

/* ── UTILITIES STATE ── */
#loading, #error { text-align: center; padding: 80px 20px; color: var(--text-muted); font-size: 15px; font-weight: 500; }
#error { color: var(--burgundy); background: var(--burgundy-dim); border-radius: var(--radius-md); margin: 20px; padding: 20px; }

/* ── PRODUCT GRID & CARDS ── */
#products {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(170px, 1fr));
  gap: 16px;
  padding: 24px 20px;
  max-width: 1200px;
  margin: 0 auto;
}
.product-card {
  background-color: var(--surface);
  border-radius: 14px;
  padding: 12px;
  cursor: pointer;
  box-shadow:
    0 4px 6px -1px rgba(31, 26, 27, 0.05),
    0 2px 4px -2px rgba(31, 26, 27, 0.04);
  transition: transform .2s ease, box-shadow .2s ease, border-color .2s ease;
  position: relative;
  border: 1px solid var(--border-color);
  display: flex;
  flex-direction: column;
}
.product-card:hover {
  transform: translateY(-4px);
  box-shadow:
    0 12px 20px -6px rgba(122, 31, 43, 0.14),
    0 6px 10px -6px rgba(31, 26, 27, 0.06);
  border-color: rgba(122, 31, 43, 0.22);
}
.product-card.out-of-stock {
  opacity: 0.55; cursor: not-allowed;
  transform: none !important; box-shadow: none !important;
  filter: grayscale(0.4);
}

.card-img {
  position: relative;
  aspect-ratio: 4 / 3;
  border-radius: 10px;
  overflow: hidden;
  background: var(--cream);
  display: flex; align-items: center; justify-content: center;
  margin-bottom: 10px;
}
.card-img .img-fallback { font-size: 34px; opacity: .45; }
.card-img img {
  position: absolute; inset: 0;
  width: 100%; height: 100%;
  object-fit: cover;
}
.badge-percent {
  position: absolute; top: 6px; left: 6px;
  background: var(--burgundy); color: var(--cream);
  width: 46px; height: 46px; border-radius: 50%;
  display: flex; align-items: center; justify-content: center;
  font-size: 11px; font-weight: 700; text-align: center; line-height: 1.15;
  box-shadow: 0 2px 8px rgba(122, 31, 43, 0.35);
}
.save-strip {
  background: #FDE047; color: #713F12;
  font-size: 11px; font-weight: 700;
  padding: 2px 8px; border-radius: 6px;
  width: fit-content;
  margin-bottom: 6px;
}
.product-name {
  font-weight: 500; font-size: 15px; color: var(--text-dark);
  margin-bottom: 6px; line-height: 1.35;
  display: -webkit-box;
  -webkit-line-clamp: 2;
  -webkit-box-orient: vertical;
  overflow: hidden;
  flex-grow: 1;
}
.product-price {
  font-size: 1.2rem; font-weight: 600; color: var(--burgundy);
  letter-spacing: 0.2px;
}
.product-price-original {
  font-size: 0.85rem; font-weight: 400; color: var(--text-mid);
  text-decoration: line-through;
  margin-left: 6px;
}
.product-stock {
  font-size: 11px; font-weight: 500; color: var(--text-mid);
  margin-top: 4px;
  display: flex; align-items: center; gap: 4px;
}
.product-stock.low { color: #B45309; }
.product-card.out-of-stock .product-stock { color: var(--burgundy); font-weight: 600; }

.add-btn {
  width: 100%; margin-top: 10px;
  background: var(--burgundy); color: var(--cream);
  border: none; border-radius: 10px;
  padding: 9px 0;
  font-family: inherit; font-size: 14px; font-weight: 600;
  cursor: pointer;
  transition: var(--transition);
}
.add-btn:hover:not(:disabled) { background: var(--burgundy-hover); }
.add-btn:active:not(:disabled) { transform: scale(0.97); }
.add-btn:disabled { background: #D6CDC2; color: #A89E94; cursor: not-allowed; }

.qty-badge {
  position: absolute;
  top: -6px; right: -6px;
  background: var(--burgundy); color: var(--cream);
  border-radius: 100px;
  min-width: 24px; height: 24px; padding: 0 7px;
  font-size: 12px; font-weight: 600;
  display: flex; align-items: center; justify-content: center;
  box-shadow: 0 4px 10px rgba(122, 31, 43, 0.35);
  border: 2px solid var(--cream);
  animation: popIn 0.2s cubic-bezier(0.175, 0.885, 0.32, 1.275);
  z-index: 2;
}
.qty-badge[hidden] { display: none; }
@keyframes popIn { from { transform: scale(0); } to { transform: scale(1); } }

/* ── DRAWERS & OVERLAYS ── */
#cartOverlay, #sheetOverlay {
  display: none;
  position: fixed; inset: 0;
  background: rgba(31, 26, 27, 0.3);
  backdrop-filter: blur(8px);
  z-index: 200;
}
#cartOverlay.open, #sheetOverlay.open { display: block; }

#cartDrawer, #productSheet {
  position: fixed;
  bottom: 0; left: 0; right: 0;
  background: white;
  border-radius: var(--radius-lg) var(--radius-lg) 0 0;
  padding: 24px;
  max-height: 85vh;
  overflow-y: auto;
  z-index: 201;
  transform: translateY(100%);
  transition: transform 0.35s cubic-bezier(0.4, 0, 0.2, 1);
  box-shadow: 0 -10px 40px rgba(0,0,0,0.1);
}
#cartDrawer.open, #productSheet.open { transform: translateY(0); }
@media (min-width: 640px) {
  #cartDrawer {
    top: 0; bottom: 0; right: 0; left: auto; width: 400px;
    max-height: 100vh;
    border-radius: var(--radius-lg) 0 0 var(--radius-lg);
    transform: translateX(100%);
  }
  #cartDrawer.open { transform: translateX(0); }
  #productSheet {
    left: 50%; right: auto; width: 440px;
    transform: translate(-50%, 100%);
  }
  #productSheet.open { transform: translate(-50%, 0); }
}

.drawer-handle { width: 40px; height: 5px; background: var(--border-color); border-radius: 10px; margin: -8px auto 20px; }
@media (min-width: 640px) { #cartDrawer .drawer-handle { display: none; } }
.drawer-title { font-size: 18px; font-weight: 700; margin-bottom: 20px; color: var(--text-main); }

.cart-item { display: flex; align-items: center; justify-content: space-between; padding: 14px 0; border-bottom: 1px solid var(--border-color); }
.cart-item-name { font-size: 14px; font-weight: 600; color: var(--text-main); }
.cart-item-price { font-size: 13px; color: var(--text-muted); margin-top: 2px; }

.qty-controls { display: flex; align-items: center; gap: 12px; }
.qty-btn {
  width: 32px; height: 32px;
  border: 1px solid var(--border-color); border-radius: 50%;
  background: white; cursor: pointer;
  font-size: 16px; font-weight: 600;
  display: flex; align-items: center; justify-content: center;
  transition: var(--transition);
  color: var(--text-main);
}
.qty-btn:hover { background: var(--bg-main); border-color: #D6CDC2; }
.qty-btn:active { transform: scale(0.9); }
.qty-num { font-size: 15px; font-weight: 700; min-width: 24px; text-align: center; color: var(--text-main); }

.cart-total { display: flex; justify-content: space-between; font-size: 18px; font-weight: 700; padding: 20px 0 4px; color: var(--text-main); }

#checkoutBtn {
  width: 100%;
  background: var(--primary); color: white;
  border: none; border-radius: var(--radius-md);
  padding: 16px; font-size: 16px; font-weight: 600;
  cursor: pointer; margin-top: 16px;
  transition: var(--transition);
  box-shadow: 0 4px 12px rgba(122, 31, 43, 0.15);
}
#checkoutBtn:hover:not(:disabled) { background: var(--primary-hover); transform: translateY(-1px); box-shadow: 0 6px 20px rgba(122, 31, 43, 0.25); }
#checkoutBtn:disabled { background: #D6CDC2; color: #A89E94; cursor: not-allowed; box-shadow: none; }
.empty-cart { text-align: center; color: var(--text-muted); padding: 30px 0; font-size: 14px; font-weight: 500; }

/* ── PRODUCT SHEET ── */
.sheet-product { display: flex; gap: 14px; margin-bottom: 18px; }
.sheet-img { width: 110px; flex-shrink: 0; aspect-ratio: 1 / 1; margin-bottom: 0; }
.sheet-info { min-width: 0; }
.sheet-info .save-strip { margin-bottom: 4px; }
.sheet-name { font-size: 16px; font-weight: 600; color: var(--text-dark); line-height: 1.35; margin-bottom: 4px; }

.qty-strip {
  display: flex; gap: 8px;
  overflow-x: auto;
  padding: 4px 2px 14px;
  -webkit-overflow-scrolling: touch;
}
.qty-opt {
  min-width: 44px; height: 44px;
  border-radius: 10px;
  border: 1.5px solid var(--border-color);
  background: white;
  font-family: inherit; font-size: 16px; font-weight: 600;
  color: var(--text-main);
  cursor: pointer;
  flex-shrink: 0;
  transition: var(--transition);
}
.qty-opt.selected {
  background: var(--burgundy); color: var(--cream);
  border-color: var(--burgundy);
}

#sheetPrimary {
  width: 100%;
  background: var(--primary); color: white;
  border: none; border-radius: var(--radius-md);
  padding: 16px; font-family: inherit; font-size: 16px; font-weight: 600;
  cursor: pointer;
  transition: var(--transition);
  box-shadow: 0 4px 12px rgba(122, 31, 43, 0.15);
}
#sheetPrimary:hover { background: var(--primary-hover); }
#sheetRemove {
  width: 100%;
  background: none; border: none;
  color: var(--burgundy);
  padding: 12px; margin-top: 6px;
  font-family: inherit; font-size: 14px; font-weight: 600;
  cursor: pointer; border-radius: var(--radius-sm);
  transition: var(--transition);
}
#sheetRemove:hover { background: var(--burgundy-dim); }
#sheetRemove[hidden] { display: none; }

/* ── MODAL OVERLAY (ORDER FORM) ── */
#modalOverlay {
  display: none;
  position: fixed; inset: 0;
  background: rgba(31, 26, 27, 0.4);
  backdrop-filter: blur(8px);
  z-index: 300;
  align-items: center; justify-content: center;
  padding: 20px;
}
#modalOverlay.open { display: flex; }
#modal {
  background: white;
  border-radius: var(--radius-lg);
  padding: 28px;
  width: 100%; max-width: 420px;
  box-shadow: var(--shadow-md);
  animation: modalPop 0.3s cubic-bezier(0.34, 1.56, 0.64, 1);
}
@keyframes modalPop { from { transform: scale(0.95); opacity: 0; } to { transform: scale(1); opacity: 1; } }

#modal h2 { font-size: 19px; font-weight: 700; margin-bottom: 6px; color: var(--text-main); }
#modal .subtitle { font-size: 13px; color: var(--text-muted); margin-bottom: 24px; }

.field { margin-bottom: 18px; }
.field label { font-size: 13px; font-weight: 600; color: var(--text-main); display: block; margin-bottom: 8px; }
.field input {
  width: 100%;
  border: 1.5px solid var(--border-color); border-radius: var(--radius-sm);
  padding: 12px 14px; font-size: 15px;
  outline: none;
  transition: var(--transition);
  background: #FBF8F3;
  font-family: inherit;
}
.field input:focus { border-color: var(--burgundy); background: white; box-shadow: 0 0 0 4px var(--burgundy-dim); }

.modal-total {
  background: var(--burgundy-dim);
  border-radius: var(--radius-md);
  padding: 14px 16px;
  display: flex; justify-content: space-between;
  font-weight: 600; font-size: 16px;
  margin-bottom: 20px;
  color: var(--burgundy);
}

#payBtn {
  width: 100%;
  background: var(--primary); color: white;
  border: none; border-radius: var(--radius-md);
  padding: 16px; font-size: 16px; font-weight: 600;
  cursor: pointer;
  transition: var(--transition);
  box-shadow: 0 4px 12px rgba(122, 31, 43, 0.15);
  font-family: inherit;
}
#payBtn:hover:not(:disabled) { background: var(--primary-hover); }
#payBtn:disabled { background: #D6CDC2; cursor: not-allowed; box-shadow: none; }

#cancelBtn {
  width: 100%;
  background: none; border: none;
  color: var(--text-muted);
  padding: 12px; font-size: 14px; font-weight: 500;
  cursor: pointer; margin-top: 8px;
  transition: var(--transition);
  border-radius: var(--radius-sm);
  font-family: inherit;
}
#cancelBtn:hover { background: var(--bg-main); color: var(--text-main); }

.spinner {
  display: inline-block; width: 18px; height: 18px;
  border: 2.5px solid rgba(255,255,255,0.3); border-top-color: white;
  border-radius: 50%;
  animation: spin 0.6s linear infinite;
  margin-right: 8px; vertical-align: middle;
}
@keyframes spin { to { transform: rotate(360deg); } }

/* ── PromptPay payment screen ── */
#payOverlay {
  position: fixed; inset: 0;
  background: rgba(31, 26, 27, 0.6); backdrop-filter: blur(4px);
  z-index: 400;
  display: none; align-items: center; justify-content: center;
  padding: 20px;
}
#payOverlay.open { display: flex; }
#payCard {
  background: white; border-radius: var(--radius-lg);
  max-width: 420px; width: 100%;
  padding: 28px 24px;
  box-shadow: var(--shadow-md);
  text-align: center;
  max-height: 90vh; overflow-y: auto;
}
#payCard h2 { color: var(--primary); font-size: 22px; margin-bottom: 4px; }
#payCard .pay-subtitle { color: var(--text-muted); font-size: 14px; margin-bottom: 20px; }
#payQrBox {
  background: white; border: 2px solid var(--border-color);
  border-radius: var(--radius-md); padding: 16px;
  display: inline-block; margin-bottom: 16px;
}
#payQrBox canvas, #payQrBox img { display: block; }
.pp-logo { font-size: 11px; font-weight: 700; color: #00509a; letter-spacing: 2px; margin-bottom: 4px; }
.pp-amount { font-size: 32px; font-weight: 800; color: var(--text-main); margin: 12px 0 4px; }
.pp-cents-note { font-size: 12px; color: var(--text-muted); margin-bottom: 16px; }
.pp-receiver {
  background: var(--bg-main); border-radius: var(--radius-sm);
  padding: 10px 14px; margin-bottom: 16px; text-align: left;
  font-size: 13px;
}
.pp-receiver strong { display: block; color: var(--text-main); }
.pp-receiver span { color: var(--text-muted); }
.pp-steps {
  text-align: left; font-size: 13px; color: var(--text-muted);
  background: #fef3c7; border-radius: var(--radius-sm);
  padding: 12px 14px; margin-bottom: 16px;
}
.pp-steps ol { padding-left: 20px; }
.pp-steps li { margin: 4px 0; }
#paySlipBtn {
  width: 100%; background: #2563eb; color: white;
  border: none; border-radius: var(--radius-md);
  padding: 14px; font-size: 16px; font-weight: 700;
  cursor: pointer; transition: var(--transition);
  margin-bottom: 10px;
  box-shadow: 0 4px 12px rgba(37, 99, 235, 0.25);
  font-family: inherit;
}
#paySlipBtn:hover:not(:disabled) { background: #1d4ed8; }
#paySlipBtn:disabled { background: #A89E94; cursor: not-allowed; box-shadow: none; }
#paySlipStatus { font-size: 13px; margin: 4px 0 12px; min-height: 18px; }
#paySlipStatus.ok { color: #16a34a; font-weight: 600; }
#paySlipStatus.err { color: var(--primary); }
#paySlipStatus.busy { color: var(--text-muted); }
#payCancelBtn {
  width: 100%; background: none; border: none;
  color: var(--text-muted); padding: 10px; font-size: 14px;
  cursor: pointer; font-family: inherit;
}
```

- [ ] **Step 3: Rewrite `index.html`**

Replace `public/order/index.html` entirely:

```html
<!DOCTYPE html>
<html lang="th">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>สั่งสินค้าออนไลน์</title>
  <link rel="canonical" href="https://pok-pok.app/order" />
  <link rel="icon" type="image/png" href="/favicon.png" />
  <link rel="preconnect" href="https://fonts.googleapis.com" />
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
  <link
    href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans+Thai:wght@300;400;500;600;700&display=swap"
    rel="stylesheet"
  />
  <link rel="stylesheet" href="/order/order.css" />
  <!-- Self-hosted qrcodejs (davidshimjs) — avoids CDN/CORB blocks -->
  <script src="qrcode.min.js"></script>
</head>
<body>

<header>
  <div class="brand">
    <span class="brand-mark" aria-hidden="true">
      <svg viewBox="0 0 100 100" xmlns="http://www.w3.org/2000/svg">
        <rect x="45.5" y="6" width="9" height="42" fill="#7A1F2B" rx="4.5"/>
        <circle cx="50" cy="41" r="3.4" fill="#F5F1EC"/>
        <path d="M 14 56 A 36 32 0 0 0 86 56 L 14 56 Z" fill="#7A1F2B"/>
        <rect x="40" y="90" width="20" height="3" fill="#7A1F2B" rx="1.5"/>
        <line x1="30" y1="90" x2="70" y2="90" stroke="#7A1F2B" stroke-width="2" stroke-linecap="round"/>
      </svg>
    </span>
    <h1 id="shopName">กำลังโหลด...</h1>
  </div>
  <button id="cartBtn" type="button">
    🛒 ตะกร้า <span id="cartCount">0</span>
  </button>
</header>

<div id="loading">กำลังโหลดสินค้า...</div>
<div id="error" style="display:none"></div>
<div id="products" style="display:none"></div>

<footer style="text-align:center;padding:28px 16px;color:#6B5E60;font-size:.78rem;line-height:1.8">
  <a href="/privacy" style="color:#7A1F2B;text-decoration:none">นโยบายความเป็นส่วนตัว</a>
  &nbsp;·&nbsp;
  <a href="/terms" style="color:#7A1F2B;text-decoration:none">เงื่อนไขการใช้บริการ</a>
  <br>ขับเคลื่อนโดย Pokpok
</footer>

<!-- Cart drawer -->
<div id="cartOverlay"></div>
<div id="cartDrawer">
  <div class="drawer-handle"></div>
  <div class="drawer-title">ตะกร้าสินค้า</div>
  <div id="cartItems"></div>
  <div class="cart-total">
    <span>ยอดรวม</span>
    <span id="cartTotal">฿0.00</span>
  </div>
  <button id="checkoutBtn" type="button" disabled>สั่งและชำระเงิน</button>
</div>

<!-- Product quantity bottom sheet -->
<div id="sheetOverlay"></div>
<div id="productSheet">
  <div class="drawer-handle"></div>
  <div id="sheetBody"></div>
  <div id="sheetQty" class="qty-strip"></div>
  <button id="sheetPrimary" type="button"></button>
  <button id="sheetRemove" type="button" hidden>เอาออกจากตะกร้า</button>
</div>

<!-- Order form modal -->
<div id="modalOverlay">
  <div id="modal">
    <h2>ข้อมูลผู้สั่ง</h2>
    <p class="subtitle">กรอกข้อมูลเพื่อให้ร้านติดต่อกลับเมื่อสินค้าพร้อม</p>
    <div class="field">
      <label>ชื่อ-นามสกุล</label>
      <input id="customerName" type="text" placeholder="ชื่อของคุณ" />
    </div>
    <div class="field">
      <label>เบอร์โทรศัพท์</label>
      <input id="customerPhone" type="tel" placeholder="08X-XXX-XXXX" />
    </div>
    <p style="font-size:.72rem;color:#6B5E60;line-height:1.5;margin:2px 0 10px">
      การสั่งซื้อถือว่าคุณยอมรับ
      <a href="/privacy" target="_blank" rel="noopener" style="color:#7A1F2B">นโยบายความเป็นส่วนตัว</a>
      และ
      <a href="/terms" target="_blank" rel="noopener" style="color:#7A1F2B">เงื่อนไขการใช้บริการ</a>
    </p>
    <div class="modal-total">
      <span>ยอดชำระ</span>
      <span id="modalTotal">฿0.00</span>
    </div>
    <button id="payBtn" type="button">ชำระเงิน</button>
    <button id="cancelBtn" type="button">ยกเลิก</button>
  </div>
</div>

<!-- PromptPay payment screen -->
<div id="payOverlay">
  <div id="payCard">
    <div class="pp-logo">PROMPT PAY</div>
    <h2>สแกนเพื่อชำระเงิน</h2>
    <p class="pay-subtitle">เปิดแอปธนาคารแล้วสแกน QR ด้านล่าง</p>

    <div id="payQrBox">
      <div id="payQrCanvas"></div>
    </div>

    <div class="pp-amount" id="payAmount">฿0.00</div>
    <div class="pp-cents-note" id="payCentsNote"></div>

    <div class="pp-receiver">
      <strong id="payReceiver">—</strong>
      <span id="payReceiverId">PromptPay ID: —</span>
    </div>

    <div class="pp-steps">
      <ol>
        <li>เปิดแอปธนาคาร → สแกน QR</li>
        <li>ตรวจชื่อผู้รับ + จำนวนเงิน ให้ตรงด้านบน</li>
        <li>กดยืนยันโอน + บันทึกสลิป</li>
        <li>กลับมา <strong>อัปโหลดสลิป</strong> ด้านล่างเพื่อยืนยัน</li>
      </ol>
    </div>

    <input type="file" id="slipFileInput" accept="image/*" capture="environment" style="display:none" />
    <button id="paySlipBtn" type="button">
      📷 อัปโหลดสลิปเพื่อยืนยันการชำระเงิน
    </button>
    <div id="paySlipStatus"></div>
    <p style="font-size:.72rem;color:#6B5E60;line-height:1.5;margin:6px 2px 0">
      โอนแล้วต้องอัปโหลดสลิปทุกครั้งเพื่อยืนยันออเดอร์ — ระบบตรวจยอดให้อัตโนมัติ
    </p>

    <button id="payCancelBtn" type="button">ยกเลิกออเดอร์</button>
  </div>
</div>

<!-- Page entry. Module scripts execute in document order, so main.js runs
     first (defines window.__startOrderPage), then the App Check module below
     starts the page once a token getter is ready. -->
<script type="module" src="/order/js/main.js"></script>

<!-- App Check (reCAPTCHA v3). This page talks to HTTP functions with plain
     fetch(), so we run the SDK in a module and expose a best-effort token
     getter that util.js attaches as an X-Firebase-AppCheck header. -->
<script type="module">
  import { initializeApp } from "https://www.gstatic.com/firebasejs/10.12.5/firebase-app.js";
  import { getToken } from "https://www.gstatic.com/firebasejs/10.12.5/firebase-app-check.js";
  import { setupAppCheck } from "/appcheck.js";

  const app = initializeApp({
    apiKey: "AIzaSyDfkL865SPzygJ0Kcqb4l0UaoXaSuz63F0",
    authDomain: "shop-pos-89294.firebaseapp.com",
    projectId: "shop-pos-89294",
    storageBucket: "shop-pos-89294.firebasestorage.app",
    messagingSenderId: "1010156115465",
    appId: "1:1010156115465:web:01f80dfe21f2767ea68ad8",
  });
  const appCheck = setupAppCheck(app);
  window.__appCheckToken = async () => {
    try { return (await getToken(appCheck, false)).token; } catch (_) { return null; }
  };
  // Start the page only once App Check is ready. This guarantees the first
  // /api/shopPublic call carries a token — the endpoint enforces App Check.
  window.__startOrderPage?.();
</script>
</body>
</html>
```

- [ ] **Step 4: Run the Node smoke test (regression)**

Run: `node scripts/test_order_page.mjs`
Expected: all `✓` lines, exit 0.

- [ ] **Step 5: Deploy to a Hosting preview channel and verify manually**

Run: `firebase hosting:channel:deploy order-redesign --expires 7d`

Open the printed preview URL + `/order/?shop=<real-shop-id>` on a phone-sized viewport and walk through:

1. Products load; shop name in header. **If `shopPublic` returns 401:** the preview domain isn't in the reCAPTCHA v3 allowed-domains list — either add the preview domain in the reCAPTCHA admin console, or (owner's call) deploy to production and verify there.
2. Promo item shows: circular "ลด X%" on image, yellow "ประหยัด ฿Y", struck-through original price. Non-promo items show none of these.
3. "+ เพิ่ม" adds 1 instantly; corner qty badge appears; button disables when cart qty reaches stock.
4. Tapping image/name opens the sheet; qty strip caps at `min(stock, 20)`; selecting a number updates the primary label; confirm sets absolute qty; reopening preselects current qty and shows "เอาออกจากตะกร้า".
5. Out-of-stock card is faded, Add disabled, sheet does not open.
6. Cart drawer: +/- works, totals correct; checkout opens the form; submitting reaches the PromptPay QR screen (do NOT transfer money; cancel the order).
7. No console errors.

- [ ] **Step 6: Commit**

```bash
git add public/order/index.html public/order/order.css public/order/js/main.js
git commit -m "feat(order-web): rewrite order page — split files, woolworths-style cards + qty sheet"
```

---

### Task 5: `Product.discountPercent` getter (Flutter)

**Files:**
- Modify: `lib/models/product.dart` (after the `effectivePrice` getter, ~line 55)
- Test: `test/product_test.dart` (create)

**Interfaces:**
- Consumes: existing `Product` fields/getters (`price`, `salePrice`, `saleUntil`, `isOnSale`, `effectivePrice`).
- Produces: `int get discountPercent` — `0` when not on sale or when the rounded percent is `< 1`; otherwise `round((1 − salePrice/price) × 100)`. Task 6 renders the POS badge only when `discountPercent > 0`.

- [ ] **Step 1: Write the failing test**

Create `test/product_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:shop_pos/models/product.dart';

Product _p({
  double price = 20,
  double? salePrice,
  DateTime? saleUntil,
}) =>
    Product(
      id: 'p1',
      name: 'มาม่า',
      barcode: '885',
      price: price,
      stock: 10,
      salePrice: salePrice,
      saleUntil: saleUntil,
    );

void main() {
  group('Product promo', () {
    test('active sale: isOnSale, effectivePrice, discountPercent', () {
      final p = _p(price: 20, salePrice: 10);
      expect(p.isOnSale, isTrue);
      expect(p.effectivePrice, 10);
      expect(p.discountPercent, 50);
    });

    test('expired saleUntil → no sale', () {
      final p = _p(
        price: 20,
        salePrice: 10,
        saleUntil: DateTime.now().subtract(const Duration(days: 1)),
      );
      expect(p.isOnSale, isFalse);
      expect(p.effectivePrice, 20);
      expect(p.discountPercent, 0);
    });

    test('future saleUntil → sale active', () {
      final p = _p(
        price: 20,
        salePrice: 15,
        saleUntil: DateTime.now().add(const Duration(days: 1)),
      );
      expect(p.isOnSale, isTrue);
      expect(p.discountPercent, 25);
    });

    test('salePrice >= price → no sale', () {
      expect(_p(price: 20, salePrice: 20).isOnSale, isFalse);
      expect(_p(price: 20, salePrice: 25).discountPercent, 0);
    });

    test('tiny discount rounds to 0% → badge hidden', () {
      final p = _p(price: 1000, salePrice: 996);
      expect(p.isOnSale, isTrue); // still charged the sale price
      expect(p.discountPercent, 0); // but no badge
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/product_test.dart`
Expected: FAIL — `The getter 'discountPercent' isn't defined for the class 'Product'`

- [ ] **Step 3: Add the getter**

In `lib/models/product.dart`, directly below the `effectivePrice` getter:

```dart
  /// Rounded percent off while a sale is active — for "ลด X%" badges.
  /// 0 when there is no active sale or the discount rounds below 1%.
  int get discountPercent {
    if (!isOnSale) return 0;
    final pct = ((1 - salePrice! / price) * 100).round();
    return pct < 1 ? 0 : pct;
  }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `flutter test`
Expected: all tests pass (including the placeholder `widget_test.dart`).

- [ ] **Step 5: Commit**

```bash
git add lib/models/product.dart test/product_test.dart
git commit -m "feat(pos): Product.discountPercent getter for promo badges"
```

---

### Task 6: POS category picker — chips → image cards

**Files:**
- Modify: `lib/screens/pos_screen.dart` — replace the `if (_selectedCategory != 'ทั้งหมด')` StreamBuilder block (~lines 451-495, the `Wrap` of `ActionChip`s), and add `_PickerProductCard` in the sub-widgets section.

**Interfaces:**
- Consumes: `Product.discountPercent` (Task 5), `Product.effectivePrice`, `Product.isOnSale`, existing `_addToCart(Product)`; `dart:io` `File` (already imported in this file).
- Produces: private widget `_PickerProductCard({required Product product, VoidCallback? onAdd})` — tap = add 1 to cart; `onAdd == null` renders the out-of-stock state.

- [ ] **Step 1: Replace the category picker block**

In `pos_screen.dart`, replace this block:

```dart
          // Category-filtered product picker (only when a specific
          // category is selected — keeps "ทั้งหมด" view clean and lets
          // pinned + search carry the load there).
          if (_selectedCategory != 'ทั้งหมด')
            StreamBuilder<List<Product>>(
              stream: ProductService.watchAll(),
              builder: (ctx, snap) {
                final all = snap.data ?? [];
                final inCategory = all
                    .where((p) => p.category == _selectedCategory)
                    .toList()
                  ..sort((a, b) => a.name.compareTo(b.name));
                if (inCategory.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'ยังไม่มีสินค้าในหมวด "$_selectedCategory"',
                      style: const TextStyle(
                          color: Colors.grey, fontSize: 12),
                    ),
                  );
                }
                return Container(
                  margin: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 4),
                  constraints: const BoxConstraints(maxHeight: 160),
                  child: SingleChildScrollView(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: inCategory.map((p) {
                        final outOfStock = p.stock <= 0;
                        return ActionChip(
                          label: Text(
                            '${p.name} · ฿${p.effectivePrice.toStringAsFixed(0)}'
                            '${p.isOnSale ? " (โปร)" : ""}'
                            '${outOfStock ? " (หมด)" : ""}',
                            style: const TextStyle(fontSize: 12),
                          ),
                          onPressed:
                              outOfStock ? null : () => _addToCart(p),
                        );
                      }).toList(),
                    ),
                  ),
                );
              },
            ),
```

with:

```dart
          // Category-filtered product picker (only when a specific
          // category is selected — keeps "ทั้งหมด" view clean and lets
          // pinned + search carry the load there). Image cards with promo
          // badges; tap = add 1 to cart (no sheet — cashier speed).
          if (_selectedCategory != 'ทั้งหมด')
            StreamBuilder<List<Product>>(
              stream: ProductService.watchAll(),
              builder: (ctx, snap) {
                final all = snap.data ?? [];
                final inCategory = all
                    .where((p) => p.category == _selectedCategory)
                    .toList()
                  ..sort((a, b) => a.name.compareTo(b.name));
                if (inCategory.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(12),
                    child: Text(
                      'ยังไม่มีสินค้าในหมวด "$_selectedCategory"',
                      style: const TextStyle(
                          color: Colors.grey, fontSize: 12),
                    ),
                  );
                }
                return SizedBox(
                  height: 132,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    itemCount: inCategory.length,
                    itemBuilder: (ctx, i) {
                      final p = inCategory[i];
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _PickerProductCard(
                          product: p,
                          onAdd: p.stock <= 0 ? null : () => _addToCart(p),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
```

- [ ] **Step 2: Add `_PickerProductCard`**

In the `// --- Sub-widgets ---` section of `pos_screen.dart` (e.g. right after `_CartItemTile`), add:

```dart
/// Compact product card for the POS category picker. Tap = add 1 to cart.
/// [onAdd] == null renders the out-of-stock state (faded + "หมด").
class _PickerProductCard extends StatelessWidget {
  const _PickerProductCard({required this.product, this.onAdd});
  final Product product;
  final VoidCallback? onAdd;

  Widget _fallbackIcon(ColorScheme cs) => Container(
        color: cs.surfaceContainerHighest,
        child: Icon(Icons.inventory_2_outlined,
            size: 24, color: cs.onSurface.withValues(alpha: 0.3)),
      );

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final out = onAdd == null;
    final pct = product.discountPercent;

    Widget image;
    if (product.imagePath != null) {
      image = Image.file(
        File(product.imagePath!),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallbackIcon(cs),
      );
    } else if ((product.imageUrl ?? '').isNotEmpty) {
      image = Image.network(
        product.imageUrl!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _fallbackIcon(cs),
      );
    } else {
      image = _fallbackIcon(cs);
    }

    return SizedBox(
      width: 110,
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onAdd,
          child: Opacity(
            opacity: out ? 0.45 : 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 64,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      image,
                      if (pct > 0)
                        Positioned(
                          left: 4,
                          top: 4,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF7A1F2B),
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: Text(
                              'ลด $pct%',
                              style: const TextStyle(
                                color: Color(0xFFF5F1EC),
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      if (out)
                        Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF7A1F2B),
                              borderRadius: BorderRadius.circular(100),
                            ),
                            child: const Text(
                              'หมด',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(6, 4, 6, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        height: 27,
                        child: Text(
                          product.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 11, height: 1.2),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '฿${product.effectivePrice.toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: cs.primary,
                            ),
                          ),
                          if (product.isOnSale)
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Text(
                                '฿${product.price.toStringAsFixed(0)}',
                                style: TextStyle(
                                  fontSize: 9,
                                  decoration: TextDecoration.lineThrough,
                                  color: cs.onSurface.withValues(alpha: 0.45),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 3: Analyze + test**

Run: `flutter analyze`
Expected: No issues found.

Run: `flutter test`
Expected: all tests pass.

- [ ] **Step 4: Manual verification on a device/emulator**

Run the app → POS → pick a category:
1. Horizontal card row appears (images, names, prices).
2. A product with an active sale shows the "ลด X%" badge + struck-through regular price.
3. Tapping a card adds 1 to the cart (existing snack/cart behavior).
4. An out-of-stock product is faded with "หมด" and does not respond to taps.
5. "ทั้งหมด" view unchanged (no picker row); pinned chips + search unchanged.

- [ ] **Step 5: Commit**

```bash
git add lib/screens/pos_screen.dart
git commit -m "feat(pos): category picker as image cards with promo badges"
```

---

### Task 7: Final verification + production deploy (owner gate)

**Files:** none (verification only)

- [ ] **Step 1: Full test sweep**

```bash
node scripts/test_order_page.mjs
flutter analyze
flutter test
```
Expected: all pass, no analyzer issues.

- [ ] **Step 2: Ask the owner before production deploy**

Production deploy is outward-facing — confirm with the owner first. On approval:

```bash
firebase deploy --only hosting
```

(Functions untouched — do NOT deploy functions.)

- [ ] **Step 3: Post-deploy smoke check**

Open `https://pok-pok.app/order/?shop=<real-shop-id>`: products load (App Check token works on the production domain), promo badges render, add-to-cart + sheet work, PromptPay QR renders (cancel the order; no real transfer).

- [ ] **Step 4: Clean up the preview channel**

```bash
firebase hosting:channel:delete order-redesign --force
```
