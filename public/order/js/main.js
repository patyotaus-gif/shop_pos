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
