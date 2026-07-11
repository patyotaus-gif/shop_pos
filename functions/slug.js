// Pure slug helpers for the short shop link /r/<slug> — CommonJS so index.js
// and scripts/test_functions_slug.mjs share them.

// Paths that already mean something under the hosting root, plus the /r/
// prefix itself. A slug can't collide with these.
const RESERVED = new Set([
  "order", "api", "app", "r", "admin", "privacy", "terms", "blog",
  "subscribe", "supplier", "payment", "screens", "js", "assets", "favicon",
]);

// Lowercase, spaces/underscores → "-", strip anything not [a-z0-9-], collapse
// repeated "-", trim leading/trailing "-". May return "" if nothing survives.
function normalizeSlug(raw) {
  return String(raw || "")
    .toLowerCase()
    .replace(/[\s_]+/g, "-")
    .replace(/[^a-z0-9-]/g, "")
    .replace(/-+/g, "-")
    .replace(/^-+|-+$/g, "");
}

// Throws Error (Thai, user-safe) when the slug is too short/long or reserved.
// Assumes the input is already normalized. Returns the slug on success.
function validateSlug(slug) {
  if (RESERVED.has(slug)) {
    throw new Error("ชื่อนี้เป็นคำสงวน ใช้ไม่ได้");
  }
  if (slug.length < 3 || slug.length > 30) {
    throw new Error("ลิงก์ต้องยาว 3–30 ตัวอักษร (a-z, 0-9, -)");
  }
  return slug;
}

module.exports = { normalizeSlug, validateSlug, RESERVED };
