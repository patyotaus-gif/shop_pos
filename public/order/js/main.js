// Entry point. The inline App Check module in index.html calls
// window.__startOrderPage() AFTER setting window.__appCheckToken, so the
// first /api/shopPublic call always carries a token (endpoint is enforced).
import { shopId, tableParam, takeawayParam, orderContext, apiFetch, escHtml } from './util.js';
import { initCatalog, renderProducts } from './catalog.js';
import { initCartUI } from './cart.js';
import { initPayment, openOrderModal } from './payment.js';
import { initUpsell, maybeShowUpsell } from './upsell.js';
import { initTableOrder, openTableOrderSheet } from './tableorder.js';

function showError(msg) {
  document.getElementById('loading').style.display = 'none';
  const el = document.getElementById('error');
  el.style.display = 'block';
  el.textContent = msg;
}

async function start() {
  if (!shopId) { showError('ลิงก์ไม่ถูกต้อง — ไม่พบ shop ID'); return; }
  try {
    // Single endpoint returns the public shop name + products (whitelisted
    // fields only; promo price applied server-side). `table` adds the
    // dine-in context (mode + table name).
    const url = `/api/shopPublic?shop=${shopId}` +
      (tableParam ? `&table=${encodeURIComponent(tableParam)}` : '');
    const res = await apiFetch(url);
    if (!res.ok) {
      const body = await res.json().catch(() => ({}));
      showError(body.error === 'table_not_found'
        ? 'ไม่พบโต๊ะนี้ — กรุณาแจ้งพนักงาน'
        : 'ไม่พบร้านค้านี้');
      return;
    }
    const data = await res.json();

    // Resolve the ordering mode from the QR link + shop settings.
    if (data.table) {
      orderContext.table = data.table;
      orderContext.mode =
        data.tableOrderMode === 'prepaid' ? 'prepaidTable' : 'dineIn';
    } else if (takeawayParam) {
      orderContext.mode = 'takeaway';
    }
    const dineIn = orderContext.mode === 'dineIn';

    initCatalog();
    initCartUI({
      onCheckout: () =>
        maybeShowUpsell(dineIn ? openTableOrderSheet : openOrderModal),
    });
    initPayment();
    initTableOrder();

    const shopName = data.name || 'ร้านค้า';
    document.getElementById('shopName').textContent = shopName;
    document.title = `สั่งสินค้า — ${shopName}`;

    // Context badge + checkout label per mode.
    const badge = document.getElementById('modeBadge');
    if (orderContext.table) {
      badge.hidden = false;
      badge.innerHTML = `🍽️ โต๊ะ ${escHtml(orderContext.table.name)}`;
    } else if (orderContext.mode === 'takeaway') {
      badge.hidden = false;
      badge.textContent = '🛍️ รับกลับบ้าน';
    }
    if (dineIn) {
      document.getElementById('checkoutBtn').textContent = 'ส่งออเดอร์เข้าครัว';
    }

    renderProducts(data.products || []);
    initUpsell({
      products: data.products || [],
      label: dineIn ? 'ส่งออเดอร์ต่อ' : 'ไปชำระเงินต่อ',
    });
    document.getElementById('loading').style.display = 'none';
    document.getElementById('products').style.display = 'grid';
  } catch (e) {
    showError('เกิดข้อผิดพลาดในการโหลดข้อมูล');
  }
}

window.__startOrderPage = start;
