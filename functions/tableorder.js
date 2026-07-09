// Pure helpers for web-originated table orders (createTableOrder) —
// CommonJS so index.js and scripts/test_functions_tableorder.mjs share them.

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

// Whitelist-validate items sent from the table-order web page. Quantity is
// clamped to 1..99; more than 20 lines per call is rejected (spam guard).
// Throws Error with a Thai, user-safe message.
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
    return notes ? { productId, quantity, notes } : { productId, quantity };
  });
}

module.exports = { effectivePriceOf, sanitizeTableOrderItems };
