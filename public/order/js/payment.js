// Order form + PromptPay payment + slip verification.
// Logic moved VERBATIM from the old public/order/index.html inline script —
// do not "improve" payload/CRC/compression code here.
import { shopId, apiFetch, orderContext } from './util.js';
import { items } from './cart.js';
// Payload builder now lives in the shared module (also used by /subscribe);
// re-exported so this module's interface (and its Node tests) is unchanged.
import { crc16, buildPromptPayPayload } from '../../js/promptpay-qr.js';
export { crc16, buildPromptPayPayload };

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
      body: JSON.stringify({
        shopId,
        customerName: name,
        customerPhone: phone,
        items: orderItems,
        // Context tags from QR links (display-only on the shop side).
        ...(orderContext.mode === 'takeaway' ? { orderType: 'takeaway' } : {}),
        ...(orderContext.mode === 'prepaidTable' && orderContext.table
          ? {
              orderType: 'dineInPrepaid',
              tableId: orderContext.table.id,
              tableName: orderContext.table.name,
            }
          : {}),
      }),
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
