import { apiFetch } from './util.js?v=20261013stock';

export function isConfirmedPayment(status) {
  return ['paid', 'accepted', 'ready', 'completed'].includes(status);
}

export async function customerOrderAction(action, {orderId, customerToken}, shopId) {
  const response = await apiFetch('/api/customerOrder', {
    method: 'POST',
    headers: {'Content-Type': 'application/json'},
    ...(typeof AbortSignal.timeout === 'function' ? {signal: AbortSignal.timeout(15000)} : {}),
    body: JSON.stringify({action, shopId, orderId, customerToken}),
  });
  const result = await response.json();
  if (!response.ok || result.orderId !== orderId) {
    throw Object.assign(Error(result.error || 'ตรวจออเดอร์ไม่ได้ กรุณาลองใหม่ โดยไม่ต้องโอนซ้ำ'), {status: response.status});
  }
  return result;
}

// Watch only while the relevant page or overlay is visible. A closed view must
// never be updated by an in-flight status request for a previous purchase.
export function watchCustomerPayment(reference, onStatus, onError, {trackFulfillment = false} = {}) {
  let stopped = false, checking = false, timer, delay = 5000;
  function stop() {
    stopped = true;
    clearTimeout(timer);
    document.removeEventListener('visibilitychange', check);
    window.removeEventListener('online', check);
  }
  async function check() {
    clearTimeout(timer);
    if (stopped || checking || document.hidden) return;
    checking = true;
    let retry = true;
    try {
      if (!window.__appCheckToken) await import('./order-app-check.js');
      const order = await customerOrderAction('status', reference, reference.shopId);
      if (stopped) return;
      onStatus(order);
      const pending = order.status === 'pendingPayment';
      retry = pending || (trackFulfillment && ['paid', 'accepted', 'ready'].includes(order.status));
      delay = pending ? 5000 : 15000;
      if (!retry) stop();
    } catch (_) {
      if (stopped) return;
      onError();
      delay = Math.min(delay * 2, 60000);
    } finally {
      checking = false;
      if (retry && !stopped && !document.hidden) timer = setTimeout(check, delay);
    }
  }
  document.addEventListener('visibilitychange', check);
  window.addEventListener('online', check);
  check();
  return stop;
}

const receiptPrefix = 'pokpok-receipt-v1:';
const receiptLifetime = 7 * 24 * 60 * 60 * 1000;
const maxReceipts = 20;
export const newReceiptExpiry = () => Date.now() + receiptLifetime;

function listRecentReceipts() {
  const now = Date.now(), recent = [];
  for (const key of Object.keys(localStorage)) {
    if (!key.startsWith(receiptPrefix)) continue;
    let entry;
    try { entry = JSON.parse(localStorage.getItem(key)); } catch (_) {}
    if (entry?.orderId && key === receiptPrefix + entry.orderId &&
        entry.shopId && entry.customerToken && entry.expiresAt > now) {
      recent.push(entry);
    } else {
      localStorage.removeItem(key);
    }
  }
  return recent;
}

export function rememberReceipt({shopId, orderId, customerToken, receiptExpiresAt = newReceiptExpiry()}) {
  if (!shopId || !orderId || !customerToken || receiptExpiresAt <= Date.now()) return;
  try {
    const recent = listRecentReceipts();
    if (!recent.some(entry => entry.orderId === orderId)) {
      const entry = {shopId, orderId, customerToken, expiresAt: receiptExpiresAt};
      localStorage.setItem(receiptPrefix + orderId, JSON.stringify(entry));
      recent.unshift(entry);
    }
    recent.sort((a, b) => b.expiresAt - a.expiresAt);
    for (const older of recent.slice(maxReceipts)) {
      localStorage.removeItem(receiptPrefix + older.orderId);
    }
  } catch (_) { /* The active checkout can still supply its original credential. */ }
}

// The old receipt URL has only the order ID. Resolve its private proof on
// this device, without putting credentials (or a customer's data) in links.
export function findReceipt(orderId) {
  if (!orderId) return null;
  try {
    const saved = listRecentReceipts().find(entry => entry.orderId === orderId);
    if (saved) return saved;
  } catch (_) {}
  try {
    const last = JSON.parse(sessionStorage.getItem('pokpok-open-receipt') || 'null');
    if (last?.orderId && last.shopId && last.customerToken) {
      rememberReceipt(last);
      try {
        if (localStorage.getItem(receiptPrefix + last.orderId)) sessionStorage.removeItem('pokpok-open-receipt');
      } catch (_) {}
      if (last.orderId === orderId) return last;
    }
  } catch (_) {}
  try {
    for (let i = 0; i < localStorage.length; i++) {
      const key = localStorage.key(i);
      if (!key?.startsWith('pokpok-payment-v1:')) continue;
      let saved;
      try { saved = JSON.parse(localStorage.getItem(key)); } catch (_) { continue; }
      if (saved?.orderId !== orderId || !saved.customerToken) continue;
      if (saved.receiptExpiresAt && saved.receiptExpiresAt <= Date.now()) continue;
      const receiptExpiresAt = saved.receiptExpiresAt || newReceiptExpiry();
      const ref = {shopId: key.split(':')[1], orderId, customerToken: saved.customerToken, receiptExpiresAt};
      // Timestamp pre-upgrade references on first use so an expired archive
      // cannot be renewed later by the legacy recovery slot.
      if (!saved.receiptExpiresAt) {
        try { localStorage.setItem(key, JSON.stringify({...saved, receiptExpiresAt})); } catch (_) {}
      }
      rememberReceipt(ref);
      return ref;
    }
  } catch (_) {}
  return null;
}
