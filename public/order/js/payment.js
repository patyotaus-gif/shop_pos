import { initPickup, refreshPickup, pickupPayload } from './pickup.js?v=20261009';
// Order form + PromptPay payment + slip verification.
// Logic moved VERBATIM from the old public/order/index.html inline script —
// do not "improve" payload/CRC/compression code here.
import { shopId, apiFetch, orderContext } from './util.js?v=20261009';
import { items, clearCart } from './cart.js?v=20261009';
// Payload builder now lives in the shared module (also used by /subscribe);
// re-exported so this module's interface (and its Node tests) is unchanged.
import { crc16, buildPromptPayPayload } from '../../js/promptpay-qr.js';
export { crc16, buildPromptPayPayload };

let pendingOrder = null;
let lastRequest = null;
let paymentBusy = false;
const pendingKey = `pokpok-payment-v1:${shopId}:${new URLSearchParams(location.search).get('table') || 'takeaway'}`;
function savedPayment() { try { return JSON.parse(localStorage.getItem(pendingKey) || 'null'); } catch (_) { return null; } }
function savePayment(value) { localStorage.setItem(pendingKey, JSON.stringify(value)); }
function forgetPayment() { localStorage.removeItem(pendingKey); pendingOrder = null; document.getElementById('resumePaymentBtn').hidden = true; }
const phoneValid = value => /^(?:0\d{8,9}|\+[1-9]\d{7,14})$/.test(value.replace(/[\s().-]/g,''));
async function customerAction(action, saved = savedPayment()) {
  const res = await apiFetch('/api/customerOrder', {method:'POST',headers:{'Content-Type':'application/json'},
    body:JSON.stringify({shopId,orderId:saved.orderId,customerToken:saved.customerToken,action})});
  const result = await res.json();
  if(!res.ok) throw Error(result.error || 'ตรวจออเดอร์ไม่ได้ กรุณาลองใหม่ โดยไม่ต้องโอนซ้ำ');
  return result;
}
async function resumePayment() {
  if(paymentBusy) return;
  const saved=savedPayment(); if(!saved) return;
  paymentBusy=true;
  try {
    let data;
    if(saved.request) {
      // A response can disappear after the commit. Replay the SAME protected ID.
      const res=await apiFetch('/api/createPromptPayOrder',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(saved.request)});
      data=await res.json();
      if(!res.ok || !data.orderId) {
        if([400,409].includes(res.status) && !data.existingOrder) {forgetPayment();throw Error(data.error || 'กรุณาเลือกสินค้าใหม่');}
        // Already paid/processed requests cannot create another order.
        data=await customerAction('status',saved);
      }
    } else data=await customerAction('status',saved);
    const next={orderId:data.orderId,customerToken:saved.customerToken};
    savePayment(next); pendingOrder={...data,...next};
    clearCart(); closeOrderModal(); showPaymentScreen(pendingOrder);
  } catch(e) {alert(e.message || 'ตรวจออเดอร์ไม่ได้ กรุณาลองใหม่ โดยไม่ต้องโอนซ้ำ');}
  finally {paymentBusy=false;}
}

export function openOrderModal() {
  if(savedPayment()) {resumePayment(); return;}
  document.getElementById('modalOverlay').classList.add('open');
  refreshPickup();
}
function closeOrderModal() {
  document.getElementById('modalOverlay').classList.remove('open');
}

export function initPayment() {
  initPickup();
  document.getElementById('payBtn').addEventListener('click', submitOrder);
  document.getElementById('cancelBtn').addEventListener('click', closeOrderModal);
  document.getElementById('paySlipBtn').addEventListener('click', () =>
    document.getElementById('slipFileInput').click());
  document.getElementById('slipFileInput').addEventListener('change', uploadSlip);
  document.getElementById('payCancelBtn').addEventListener('click', cancelPay);
  document.getElementById('payCloseBtn').addEventListener('click', () => {
    if(paymentBusy) return;
    if(pendingOrder?.status && pendingOrder.status !== 'pendingPayment') forgetPayment();
    document.getElementById('payOverlay').classList.remove('open');
  });
  document.getElementById('resumePaymentBtn').hidden = !savedPayment();
  document.getElementById('resumePaymentBtn').addEventListener('click', resumePayment);
  if(savedPayment()) resumePayment();
}

// ── Submit order ──
async function submitOrder() {
  const name = document.getElementById('customerName').value.trim();
  const phone = document.getElementById('customerPhone').value.trim();
  if (!name) { alert('กรุณากรอกชื่อ'); return; }
  if (!phone) { alert('กรุณากรอกเบอร์โทร'); return; }
  if (!phoneValid(phone)) { alert('กรุณากรอกเบอร์โทรให้ถูกต้อง เช่น 0812345678 หรือ +66812345678'); return; }
  if(savedPayment()) {await resumePayment(); return;}

  let pickup;
  try { pickup = pickupPayload(); } catch (error) { alert(error.message); return; }
  const orderItems = items().map((i) => ({
    productId: i.id,
    quantity: i.quantity,
    optionIds: i.optionIds || [],
    ...(i.notes ? { notes: i.notes } : {}),
  }));

  const signature = JSON.stringify({ name, phone, orderItems, pickup });
  if (!lastRequest || lastRequest.signature !== signature) lastRequest = { signature, id: crypto.randomUUID() };
  const payBtn = document.getElementById('payBtn');
  payBtn.disabled = true;
  payBtn.innerHTML = '<span class="spinner"></span>กำลังดำเนินการ...';

  try {
    const customerToken=Array.from(crypto.getRandomValues(new Uint8Array(32)), v=>v.toString(16).padStart(2,'0')).join('');
    const request = {
        shopId, ...pickup, requestId:lastRequest.id, customerToken,
        customerName:name, customerPhone:phone, items:orderItems,
        ...(orderContext.mode === 'takeaway' ? {orderType:'takeaway'} : {}),
        ...(orderContext.mode === 'prepaidTable' && orderContext.table ? {orderType:'dineInPrepaid',tableId:orderContext.table.id,tableName:orderContext.table.name} : {}),
    };
    savePayment({orderId:`web-${lastRequest.id}`,customerToken,request});
    document.getElementById('resumePaymentBtn').hidden=false;
    const res = await apiFetch('/api/createPromptPayOrder', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(request),
    });
    const data = await res.json();
    if (!res.ok || !data.orderId) {
      if((res.status===400 || res.status===409) && !data.existingOrder) {forgetPayment(); lastRequest=null;}
      alert('เกิดข้อผิดพลาด: ' + (data.error || 'กรุณาลองใหม่'));
      if (res.status === 409) await refreshPickup();
      return;
    }
    pendingOrder = {...data,customerToken};
    savePayment({orderId:data.orderId,customerToken});
    lastRequest = null;
    // The server accepted these items. Do not restore them as a new draft.
    clearCart();
    closeOrderModal();
    showPaymentScreen(data);
  } catch (e) {
    alert(['SecurityError','QuotaExceededError'].includes(e.name)
      ? 'เบราว์เซอร์บันทึกออเดอร์ไม่ได้ กรุณาอนุญาตการจัดเก็บข้อมูลเว็บไซต์หรือเปิดด้วยเบราว์เซอร์อื่น'
      : 'เชื่อมต่อไม่ได้ กรุณากดเปิดออเดอร์เดิมเพื่อตรวจสอบ โดยไม่ต้องโอนซ้ำ');
  } finally {
    payBtn.disabled = false;
    payBtn.textContent = 'ชำระเงิน';
  }
}

function showPaymentScreen({ finalAmount, total, promptpayId, promptpayName, pickupLabel }) {
  const waiting = !pendingOrder.status || pendingOrder.status === 'pendingPayment';
  const review = pendingOrder.awaitingReview === true;
  document.getElementById('payQrBox').hidden = !waiting || review;
  document.getElementById('payHeading').textContent = !waiting ? 'สถานะออเดอร์' : review ? 'รอร้านตรวจสอบ' : 'สแกนเพื่อชำระเงิน';
  document.querySelector('#payCard .pay-subtitle').hidden = !waiting || review;
  document.querySelector('#payCard .pp-steps').hidden = !waiting || review;
  document.getElementById('paySlipBtn').disabled = !waiting;
  document.getElementById('paySlipBtn').hidden = !waiting;
  document.getElementById('payCancelBtn').hidden = !waiting || review;
  document.getElementById('paySlipStatus').textContent = !waiting
    ? (pendingOrder.status === 'cancelled' ? 'ยกเลิกออเดอร์แล้ว' : 'ร้านยืนยันรับเงินแล้ว ไม่ต้องโอนซ้ำ')
    : review ? 'ส่งสลิปแล้ว รอร้านตรวจสอบ ไม่ต้องโอนซ้ำ' : '';
  document.getElementById('payOrderId').textContent = `เลขออเดอร์ ${pendingOrder.orderId}`;
  document.getElementById('payPickup').textContent = pickupLabel ? `นัดรับ ${pickupLabel} (เวลาประเทศไทย)` : '';
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
  if (!file || !pendingOrder || paymentBusy) return;
  paymentBusy=true;
  const uploadingOrder={...pendingOrder};

  const slipBtn = document.getElementById('paySlipBtn');
  const status = document.getElementById('paySlipStatus');
  slipBtn.disabled = true;
  slipBtn.innerHTML = '<span class="spinner"></span>กำลังส่งสลิป...';
  status.className = 'busy';
  status.textContent = 'เตรียมรูปและส่งให้ร้านตรวจสอบ...';

  try {
    if (file.size > 20 * 1024 * 1024) throw new Error('slip-file-too-large');
    // Convert image → base64. Compress large images first so we don't
    // POST a 10MB payload.
    const slipBase64 = await fileToBase64Compressed(file, 1600);

    const res = await apiFetch('/api/verifyPromptPaySlip', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        shopId,
        orderId: pendingOrder.orderId,
        customerToken: pendingOrder.customerToken,
        slipBase64,
      }),
    });
    const data = await res.json().catch(() => ({success:false,
      reason:res.status === 413 ? 'รูปสลิปใหญ่เกินไป กรุณาย่อรูปแล้วลองใหม่' : 'ระบบรับสลิปขัดข้องชั่วคราว กรุณาลองอีกครั้ง'}));

    if (!res.ok || data.success === false) {
      status.className = 'err';
      status.textContent = data.reason || data.error || 'ตรวจสลิปไม่สำเร็จ';
      slipBtn.disabled = false;
      slipBtn.innerHTML = '📷 ลองสลิปใหม่อีกครั้ง';
      return;
    }

    status.className = 'ok';
    pendingOrder.awaitingReview = true;
    document.getElementById('payCancelBtn').hidden=true;
    status.textContent = data.awaitingReview ? 'ส่งสลิปแล้ว รอร้านตรวจยอดเงินเข้าและยืนยัน' : 'กำลังเปิดหน้าออเดอร์...';
    setTimeout(() => {
      window.location.href = `/order/success/?order=${encodeURIComponent(uploadingOrder.orderId)}${data.awaitingReview ? '&review=1' : ''}${uploadingOrder.pickupLabel ? '&pickup=' + encodeURIComponent(uploadingOrder.pickupLabel) : ''}`;
    }, 1200);
  } catch (e) {
    status.className = 'err';
    status.textContent = e.message === 'slip-file-too-large'
      ? 'รูปต้นฉบับใหญ่เกิน 20 MB กรุณาย่อรูปหรือใช้ภาพหน้าจอสลิป'
      : e.message === 'image load failed'
        ? 'เปิดรูปนี้ไม่ได้ กรุณาใช้รูป JPG หรือ PNG หรือภาพหน้าจอสลิป'
        : 'ส่งสลิปไม่สำเร็จ ตรวจอินเทอร์เน็ตแล้วลองอีกครั้ง โดยไม่ต้องโอนซ้ำ';
    slipBtn.disabled = false;
    slipBtn.innerHTML = '📷 อัปโหลดสลิปให้ร้านตรวจสอบ';
  } finally {paymentBusy=false;}
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

async function cancelPay() {
  if (paymentBusy || !confirm('ยืนยันว่ายังไม่ได้โอนเงินและต้องการยกเลิกออเดอร์? หากโอนแล้ว ให้ส่งสลิปหรือติดต่อร้าน')) return;
  paymentBusy=true;
  try {
    await customerAction('cancel');
    forgetPayment();
    document.getElementById('payOverlay').classList.remove('open');
    await refreshPickup();
  } catch(e) {alert(e.message);}
  finally {paymentBusy=false;}
}
