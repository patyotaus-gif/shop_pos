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
