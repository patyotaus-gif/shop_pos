// Shared helpers for the order page. Keep this module DOM-free at import
// time so the Node smoke test (scripts/test_order_page.mjs) can load it.

// `location` is absent in Node — guard so tests can import this module.
const _params = typeof location === 'undefined'
  ? new URLSearchParams('')
  : new URLSearchParams(location.search);
export const shopId = _params.get('shop');
// Table-QR / takeaway-QR context (see spec: table-qr-ordering).
export const tableParam = _params.get('table');
export const takeawayParam = _params.get('mode') === 'takeaway';

// Resolved once by main.js after shopPublic answers; read by payment.js /
// tableorder.js. mode: 'normal' | 'takeaway' | 'dineIn' | 'prepaidTable'.
export const orderContext = { mode: 'normal', table: null };

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
