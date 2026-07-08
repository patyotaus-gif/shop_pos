// Product grid cards + product quantity bottom sheet.
// DOM-free at import time (Node smoke test imports this module).
import { escHtml, fmtBaht } from './util.js';
import { addOne, getQty, setQty, onCartChange } from './cart.js';

const byId = {};      // productId -> product from shopPublic
let sheetProduct = null; // product currently shown in the sheet
let sheetQtySelected = 1;

// Promo badge math. Badge only when originalPrice > price and the rounded
// percent is at least 1 (guards tiny/garbage discounts).
// Keep in sync with Product.discountPercent (lib/models/product.dart) — the
// POS badge derives the same percent from salePrice/price.
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
