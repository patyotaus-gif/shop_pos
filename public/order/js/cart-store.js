// Drafts belong to one browser tab and one shop/table. Never trust saved prices.
import { items, addLine, clearCart, onCartChange } from './cart.js?v=20261005';

export function cartStorageKey(shop, mode, table) {
  return 'pokpok-draft-v1:' + JSON.stringify([shop, mode, table || null]);
}

export function restoreDraft(raw, products, now = Date.now()) {
  let saved;
  try { saved = JSON.parse(raw); } catch (_) { return; }
  if (!saved || !Number.isFinite(saved.at) || now - saved.at > 2 * 60 * 60 * 1000 ||
      saved.at > now || !Array.isArray(saved.lines)) return;
  const catalog = new Map(products.map((p) => [p.id, p]));
  for (const line of saved.lines.slice(0, 100)) {
    if (!line || !Array.isArray(line.optionIds) || !Number.isInteger(line.quantity) || line.quantity <= 0) continue;
    const p = catalog.get(line.id);
    if (!p || !Number.isFinite(p.stock) || p.stock <= 0 || !Number.isFinite(p.price)) continue;
    const ids = new Set(line.optionIds);
    const modifiers = [];
    let valid = ids.size === line.optionIds.length;
    for (const g of p.modifierGroups || []) {
      const picks = (g.options || []).filter((o) => ids.has(o.id));
      if ((g.required && !picks.length) || (!g.multiSelect && picks.length > 1)) valid = false;
      for (const o of picks) modifiers.push({ groupId: g.id, groupName: g.name,
        optionId: o.id, optionName: o.name, priceAdjust: Number(o.priceAdjust || 0) });
    }
    if (!valid || modifiers.length !== ids.size) continue;
    const price = Math.max(0, p.price + modifiers.reduce((sum, m) => sum + m.priceAdjust, 0));
    if (!Number.isFinite(price)) continue;
    addLine({ id: p.id, name: p.name, stock: p.stock, price: Math.round(price * 100) / 100,
      optionIds: [...ids], modifiers, notes: typeof line.notes === 'string' ? line.notes.trim().slice(0, 200) : '' },
    Math.min(line.quantity, 99));
  }
}

export function initCartPersistence({ shop, mode, table, products, storage }) {
  const key = cartStorageKey(shop, mode, table);
  clearCart();
  try {
    storage ??= window.sessionStorage;
    restoreDraft(storage.getItem(key), products);
  } catch (_) { /* Private mode or unavailable storage: ordering still works. */ }
  const save = () => {
    try {
      const lines = items().map(({ id, quantity, optionIds, notes }) => ({ id, quantity, optionIds, notes }));
      if (!lines.length) storage.removeItem(key);
      else storage.setItem(key, JSON.stringify({ at: Date.now(), lines }));
    } catch (_) { /* Do not block checkout on a device storage error. */ }
  };
  save(); // Replace stale prices/removed options with the revalidated draft.
  return onCartChange(save);
}
