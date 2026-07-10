// Pure helpers for web-originated orders (createTableOrder /
// createPromptPayOrder) — CommonJS so index.js and
// scripts/test_functions_tableorder.mjs share them.

// Price to actually charge for a product doc — mirrors the Dart
// Product.effectivePrice getter: the sale price wins only when it's set,
// below the normal price, and not past saleUntil (null = no expiry).
function effectivePriceOf(product, now) {
  const price = Number(product.price || 0);
  const sale = Number(product.salePrice || 0);
  if (!sale || sale <= 0 || sale >= price) return price;
  const until = product.saleUntil?.toDate?.();
  if (until && until <= now) return price;
  return sale;
}

// Whitelist-validate items sent from the order web page. Quantity is
// clamped to 1..99; more than 20 lines per call is rejected (spam guard).
// `optionIds` (selected modifier options) is carried through as a string
// array. Throws Error with a Thai, user-safe message.
function sanitizeTableOrderItems(raw) {
  if (!Array.isArray(raw) || raw.length === 0) {
    throw new Error("ไม่มีรายการอาหาร");
  }
  if (raw.length > 20) {
    throw new Error("สั่งได้ครั้งละไม่เกิน 20 รายการ");
  }
  return raw.map((it) => {
    const productId = typeof it?.productId === "string" ? it.productId.trim() : "";
    if (!productId) throw new Error("ข้อมูลสินค้าไม่ถูกต้อง");
    const q = it?.quantity;
    if (!Number.isInteger(q) || q < 1) throw new Error("จำนวนไม่ถูกต้อง");
    const quantity = Math.min(q, 99);
    const notes = typeof it?.notes === "string" ? it.notes.trim().slice(0, 200) : "";
    const optionIds = Array.isArray(it?.optionIds)
      ? it.optionIds.filter((x) => typeof x === "string").map((x) => x.trim())
      : [];
    return {
      productId,
      quantity,
      optionIds,
      ...(notes ? { notes } : {}),
    };
  });
}

// Resolve + validate the modifier selection for one line and compute its
// unit price. `groups` is the product's ModifierGroup docs (id, name,
// required, multiSelect, options[{id,name,priceAdjust}]). Prices are always
// computed server-side — the client's numbers are never trusted.
//
// Returns { productName, basePrice, unitPrice, modifiers, quantity, notes }.
// Throws (Thai message) on an unknown option, a radio group with >1 pick,
// or a required group left empty.
function priceLine(item, product, groups, now) {
  const base = effectivePriceOf(product, now);

  // option id → { option, group }
  const byOption = {};
  for (const g of groups) {
    for (const o of g.options || []) byOption[o.id] = { option: o, group: g };
  }

  const selected = item.optionIds || [];
  const perGroup = {}; // groupId → count of picks
  const modifiers = [];
  let adjust = 0;
  for (const oid of selected) {
    const hit = byOption[oid];
    if (!hit) throw new Error("ตัวเลือกไม่ถูกต้อง — รีเฟรชแล้วลองใหม่");
    perGroup[hit.group.id] = (perGroup[hit.group.id] || 0) + 1;
    adjust += Number(hit.option.priceAdjust || 0);
    modifiers.push({
      groupId: hit.group.id,
      groupName: hit.group.name,
      optionId: hit.option.id,
      optionName: hit.option.name,
      priceAdjust: Number(hit.option.priceAdjust || 0),
    });
  }

  for (const g of groups) {
    const count = perGroup[g.id] || 0;
    if (!g.multiSelect && count > 1) {
      throw new Error(`เลือก "${g.name}" ได้อย่างเดียว`);
    }
    if (g.required && count < 1) {
      throw new Error(`กรุณาเลือก "${g.name}"`);
    }
  }

  const unitPrice = Math.max(0, base + adjust);
  return {
    productName: product.name || "",
    basePrice: base,
    unitPrice,
    modifiers,
    quantity: item.quantity,
    ...(item.notes ? { notes: item.notes } : {}),
  };
}

module.exports = {
  effectivePriceOf,
  sanitizeTableOrderItems,
  priceLine,
};
