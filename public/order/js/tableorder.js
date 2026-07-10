// Dine-in table ordering (QR โต๊ะ, โหมดสั่งเข้าครัวจ่ายทีหลัง): sends the
// cart to /api/createTableOrder — no customer form, no payment. Each round
// appends to the table's open tab until staff closes the bill.
import { shopId, apiFetch, orderContext, escHtml } from './util.js';
import { items, setQty } from './cart.js';

export function initTableOrder() {
  document.getElementById('kitchenSendBtn').addEventListener('click', submitTableOrder);
  document.getElementById('kitchenDoneBtn').addEventListener('click', () => {
    document.getElementById('kitchenOverlay').classList.remove('open');
  });
}

// Opened by the checkout tap (after the upsell gate) instead of the
// customer-info modal.
export function openTableOrderSheet() {
  const list = items();
  if (!list.length) return;
  document.getElementById('kitchenItems').innerHTML = list.map((i) =>
    `<div class="cart-item"><div class="cart-item-name">${escHtml(i.name)} × ${i.quantity}</div></div>`
  ).join('');
  document.getElementById('kitchenStatus').textContent = '';
  document.getElementById('kitchenStatus').className = '';
  const btn = document.getElementById('kitchenSendBtn');
  btn.disabled = false;
  btn.textContent = '🍽️ ส่งออเดอร์เข้าครัว';
  document.getElementById('kitchenView').classList.remove('hidden');
  document.getElementById('kitchenDone').classList.add('hidden');
  document.getElementById('kitchenOverlay').classList.add('open');
}

async function submitTableOrder() {
  const note = document.getElementById('kitchenNote').value.trim();
  const list = items();
  if (!list.length) return;

  const payload = list.map((i, idx) => {
    // Each line carries its own add-ons + note; the order-level note (kitchen
    // textarea) is merged onto the first line.
    const lineNote = [idx === 0 ? note : '', i.notes || '']
      .filter(Boolean).join(' · ');
    return {
      productId: i.id,
      quantity: i.quantity,
      optionIds: i.optionIds || [],
      ...(lineNote ? { notes: lineNote } : {}),
    };
  });

  const btn = document.getElementById('kitchenSendBtn');
  const status = document.getElementById('kitchenStatus');
  btn.disabled = true;
  btn.innerHTML = '<span class="spinner"></span>กำลังส่ง…';

  try {
    const res = await apiFetch('/api/createTableOrder', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        shopId,
        tableId: orderContext.table?.id,
        items: payload,
      }),
    });
    const data = await res.json();
    if (!res.ok || data.success !== true) {
      status.className = 'err';
      status.textContent = data.error || 'ส่งไม่สำเร็จ — ลองอีกครั้ง';
      btn.disabled = false;
      btn.textContent = '🍽️ ส่งออเดอร์เข้าครัว';
      return;
    }
    // Clear the cart so the next round starts fresh (appends to same tab).
    for (const i of list) setQty(i.id, 0);
    document.getElementById('kitchenNote').value = '';
    document.getElementById('kitchenView').classList.add('hidden');
    document.getElementById('kitchenDone').classList.remove('hidden');
  } catch (e) {
    status.className = 'err';
    status.textContent = 'เชื่อมต่อไม่ได้ — ลองอีกครั้ง';
    btn.disabled = false;
    btn.textContent = '🍽️ ส่งออเดอร์เข้าครัว';
  }
}
