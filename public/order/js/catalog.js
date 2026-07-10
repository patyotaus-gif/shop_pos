// Product grid cards + product quantity bottom sheet.
// DOM-free at import time (Node smoke test imports this module).
import { escHtml, fmtBaht } from './util.js';
import { addOne, getQty, addLine, onCartChange } from './cart.js';

const byId = {};      // productId -> product from shopPublic
let sheetProduct = null; // product currently shown in the sheet
let sheetQtySelected = 1;
let sheetSel = {};       // groupId -> Set(optionIds) chosen in the open sheet
let allProducts = [];
let selectedCategory = 'ทั้งหมด';

// Selected option snapshots + price adjust for the open sheet.
function sheetModifiers() {
  const p = sheetProduct;
  const mods = [];
  let adjust = 0;
  for (const g of p?.modifierGroups || []) {
    const picks = sheetSel[g.id] || new Set();
    for (const o of g.options) {
      if (picks.has(o.id)) {
        mods.push({ groupId: g.id, groupName: g.name, optionId: o.id,
          optionName: o.name, priceAdjust: o.priceAdjust });
        adjust += Number(o.priceAdjust || 0);
      }
    }
  }
  return { mods, adjust };
}

function sheetRequiredMet() {
  for (const g of sheetProduct?.modifierGroups || []) {
    if (g.required && !(sheetSel[g.id]?.size)) return false;
  }
  return true;
}

// Pure category filter (Node-tested). 'ทั้งหมด' passes everything;
// products without a category group under 'ทั่วไป'.
export function filterByCategory(products, category) {
  if (category === 'ทั้งหมด') return products;
  return products.filter((p) => (p.category || 'ทั่วไป') === category);
}

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
  document.getElementById('catBar').addEventListener('click', (e) => {
    const chip = e.target.closest('.cat-chip');
    if (!chip) return;
    selectedCategory = chip.dataset.cat;
    renderCategoryBar();
    renderGrid(filterByCategory(allProducts, selectedCategory));
  });
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
  // Modifier option toggles (radio/checkbox) inside the sheet.
  document.getElementById('sheetBody').addEventListener('click', (e) => {
    const opt = e.target.closest('.opt-row');
    if (!opt || !sheetProduct) return;
    const g = sheetProduct.modifierGroups.find((x) => x.id === opt.dataset.g);
    if (!g) return;
    const set = sheetSel[g.id] || (sheetSel[g.id] = new Set());
    if (g.multiSelect) {
      set.has(opt.dataset.o) ? set.delete(opt.dataset.o) : set.add(opt.dataset.o);
    } else {
      set.clear();
      set.add(opt.dataset.o);
    }
    renderSheetOptions();
    renderSheetQty();
  });
  document.getElementById('sheetPrimary').addEventListener('click', () => {
    if (!sheetProduct || !sheetRequiredMet()) return;
    const { mods, adjust } = sheetModifiers();
    const note = (document.getElementById('sheetNote')?.value || '').trim();
    addLine({
      id: sheetProduct.id,
      name: sheetProduct.name,
      price: Math.max(0, sheetProduct.price + adjust),
      stock: sheetProduct.stock,
      optionIds: mods.map((m) => m.optionId),
      modifiers: mods,
      notes: note,
    }, sheetQtySelected);
    closeProductSheet();
  });
  onCartChange(refreshCards);
}

export function renderProducts(products) {
  allProducts = products;
  for (const p of products) byId[p.id] = p;
  renderCategoryBar();
  renderGrid(filterByCategory(products, selectedCategory));
}

// Horizontal chip strip above the grid. Hidden when the shop effectively
// has a single category.
function renderCategoryBar() {
  const bar = document.getElementById('catBar');
  const cats = [...new Set(allProducts.map((p) => p.category || 'ทั่วไป'))];
  if (cats.length <= 1) {
    bar.hidden = true;
    return;
  }
  bar.hidden = false;
  bar.innerHTML = ['ทั้งหมด', ...cats].map((c) =>
    `<button class="cat-chip${c === selectedCategory ? ' selected' : ''}" type="button" data-cat="${escHtml(c)}">${escHtml(c)}</button>`
  ).join('');
}

function renderGrid(products) {
  const container = document.getElementById('products');
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
  sheetQtySelected = 1;
  sheetSel = {};

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
    </div>
    <div id="sheetGroups"></div>
    <div class="sheet-note-label">หมายเหตุ (ถ้ามี)</div>
    <textarea id="sheetNote" class="sheet-note" rows="2" maxlength="200"
      placeholder="เช่น ไม่ใส่ผัก, ไม่เผ็ด"></textarea>`;

  renderSheetOptions();
  renderSheetQty();
  document.getElementById('sheetRemove').hidden = true; // manage qty in cart
  document.getElementById('productSheet').classList.add('open');
  document.getElementById('sheetOverlay').classList.add('open');
}

function renderSheetOptions() {
  const wrap = document.getElementById('sheetGroups');
  if (!wrap) return;
  const groups = sheetProduct?.modifierGroups || [];
  wrap.innerHTML = groups.map((g) => {
    const picks = sheetSel[g.id] || new Set();
    const unmet = g.required && picks.size === 0;
    return `
      <div class="opt-group">
        <div class="opt-title">${escHtml(g.name)}${g.required ? `<span class="opt-req${unmet ? ' unmet' : ''}">จำเป็น</span>` : ''}</div>
        ${g.options.map((o) => `
          <div class="opt-row" data-g="${escHtml(g.id)}" data-o="${escHtml(o.id)}">
            <span class="opt-mark">${picks.has(o.id) ? '●' : '○'}</span>
            <span class="opt-name">${escHtml(o.name)}</span>
            ${o.priceAdjust ? `<span class="opt-price">${o.priceAdjust > 0 ? '+' : ''}${fmtBaht(o.priceAdjust)}</span>` : ''}
          </div>`).join('')}
      </div>`;
  }).join('');
}

function closeProductSheet() {
  sheetProduct = null;
  document.getElementById('productSheet').classList.remove('open');
  document.getElementById('sheetOverlay').classList.remove('open');
}

function renderSheetQty() {
  const p = sheetProduct;
  if (!p) return;
  const room = Math.max(1, p.stock - (getQty(p.id)));
  const maxQ = Math.min(room, 20); // strip range 1..min(remaining, 20)
  sheetQtySelected = Math.min(sheetQtySelected, maxQ);

  const strip = document.getElementById('sheetQty');
  strip.innerHTML = Array.from({ length: maxQ }, (_, i) => i + 1)
    .map((q) => `<button class="qty-opt${q === sheetQtySelected ? ' selected' : ''}" type="button" data-q="${q}">${q}</button>`)
    .join('');
  strip.querySelector('.qty-opt.selected')?.scrollIntoView({ inline: 'center', block: 'nearest' });

  const { adjust } = sheetModifiers();
  const unit = Math.max(0, p.price + adjust);
  const btn = document.getElementById('sheetPrimary');
  btn.disabled = !sheetRequiredMet();
  btn.textContent = sheetRequiredMet()
    ? `เพิ่ม ${sheetQtySelected} ลงตะกร้า · ${fmtBaht(unit * sheetQtySelected)}`
    : 'กรุณาเลือกตัวเลือกที่จำเป็น';
}
