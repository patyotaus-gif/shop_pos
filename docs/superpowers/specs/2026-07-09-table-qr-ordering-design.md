# Table/Takeaway QR Ordering + Order-Web Upgrades

**Date:** 2026-07-09 · **Status:** Approach A approved; section 1+2 approved; execution delegated ("ไปต่อ" — implement fully, summarize, NO production deploy without owner sign-off).

## Goals

1. **Printable QR codes** (Restaurant tier focus): one takeaway QR + one QR per dine-in table, exported as A5 PDF pages via the existing `pdf`+`printing` stack. QR embeds the shop logo (or the Pokpok mark) center, EC level H.
2. **Table ordering over the web**: scanning a table QR opens the existing `/order` page in one of two shop-chosen modes.
3. **Order-web upgrades** (all tiers): category filter chips + a "recommended" upsell popup before checkout.

## Shop settings (`shops/{id}/settings/shop` — new fields)

| Field | Values | Meaning |
| --- | --- | --- |
| `tableOrderMode` | `dineIn` (default) / `prepaid` | Table QR → order-to-kitchen-pay-later vs pay-first flow |
| `tableOrderAutoSend` | `false` (default) / `true` | Web items enter the tab as `pending` (staff confirms → kitchen) vs `sent` (straight to kitchen) |
| `logoUrl` | string? | Shop logo (Storage `shops/{id}/logo.jpg`), uploaded from Settings |

## Server (functions)

- **`getShopPublic`**: products gain `pinned` (from `isPinned`); accepts optional `&table=<tableId>` → response gains `tableOrderMode` and `table: {id, name}`; unknown table → `{ error: "table_not_found" }` with 404.
- **`createTableOrder`** (HTTP, CORS, App Check enforced like the order endpoints):
  - Body `{ shopId, tableId, items: [{productId, quantity, notes?}] }` — **prices are resolved server-side** from `products` (sale price honored via the same salePrice/saleUntil logic; client prices ignored).
  - Guards: shop tier must be `restaurant`; per-table cooldown 45s; ≤20 lines/call; reject when the open tab already holds >60 lines; qty clamped 1–99; unknown productIds rejected.
  - Transaction: table has open `currentOrderId` → append items to that TableOrder; else create TableOrder (`webOrigin: true`, items `kitchenStatus` = `sent` when `tableOrderAutoSend` else `pending`, `sentToKitchenAt` set when sent) + set table `occupied` + `currentOrderId`.
  - Notify owner via FCM + LINE (same pipeline as paid orders): "🍽️ ออเดอร์ใหม่ โต๊ะ X · N รายการ".
  - No stock check/decrement (restaurant flow; stock settles at bill close as today).
- **`createPromptPayOrder`**: accepts optional `tableId`, `tableName`, `orderType` (`takeaway` | `dineInPrepaid`) — stored verbatim on the order doc for display.
- Pure helpers extracted to `functions/tableorder.js` for Node tests: `effectivePriceOf(product, now)` (mirrors Dart `Product.effectivePrice`), `sanitizeTableOrderItems(raw)` (shape/qty/line-count validation → throws Thai messages).

## Web `/order` (builds on the new split modules)

- **URL params** (util.js): `table`, `mode=takeaway`.
- **Mode resolution**: `table` present → fetch shopPublic with `&table=`; `tableOrderMode === 'dineIn'` → dine-in UX, else prepaid-with-table. `mode=takeaway` → normal flow tagged takeaway. No params → unchanged.
- **Dine-in UX**: header shows "โต๊ะ <name>"; checkout button becomes "ส่งออเดอร์เข้าครัว"; no customer form / no payment; optional per-order note field (แทน modifier UI เฟสนี้); submit → `/api/createTableOrder` → success panel "ส่งเข้าครัวแล้ว ✓ สั่งเพิ่มได้เลย" → cart clears, further rounds append to the same tab.
- **Prepaid/takeaway**: existing PromptPay flow; order carries `tableId/tableName/orderType`; header badge.
- **Category chips**: horizontal strip above the grid — "ทั้งหมด" + distinct categories present; client-side filter; hidden when ≤1 category.
- **Upsell popup** (`js/upsell.js`): on checkout tap (both modes), shown once per page load: up to 4 products not in cart, pinned first then on-sale; each with image/price/"+ เพิ่ม"; actions "ไปชำระเงินต่อ"/"ส่งออเดอร์ต่อ". Empty candidate list → skip silently.

## App (Flutter — ships with next APK)

- **Shop logo**: Settings → "โลโก้ร้าน" → pick → compress → Storage `shops/{id}/logo.jpg` → `logoUrl` in settings/shop. Used as QR center logo (and future receipts).
- **"QR สั่งอาหาร" screen** (entry from เพิ่มเติม/ตั้งค่า):
  - Takeaway card (any tier with online ordering): QR + link.
  - Tables section (Restaurant only): every table from ผังโต๊ะ with mini QR; auto-follows table add/remove.
  - Header controls: dropdown โหมดโต๊ะ (dineIn/prepaid) + switch ส่งเข้าครัวอัตโนมัติ → writes settings.
  - QR widget: `qr_flutter`, EC level H, `embeddedImage` = shop logo (network) else Pokpok asset (`assets/icon/icon.png`), logo ≤20% area.
- **PDF export**: select takeaway / all tables / subset → one A5 page per QR: shop name, "สแกนสั่งอาหาร", big QR with center logo (pw.Stack over BarcodeWidget, EC H), table name huge (or "รับกลับบ้าน"), URL small → share/print via `printing` (same dialog as receipts).
- **Orders screen**: order tiles show chip "โต๊ะ X" / "รับกลับบ้าน" when `tableName`/`orderType` present (model `ShopOrder` gains the fields).

## Edge cases

| Case | Behavior |
| --- | --- |
| QR of a deleted table | Web shows "ไม่พบโต๊ะนี้ — แจ้งพนักงาน" (no orphan orders) |
| Mode switched dineIn↔prepaid | Takes effect on next page load; printed QRs stay valid |
| Multiple rounds same table | Append to the open tab until staff closes the bill |
| Reserved table scans | Ordering allowed → becomes occupied |
| Out-of-stock in dine-in | Not blocked (restaurants don't stock-count dishes); "หมด" badge still shows |
| Upsell in dine-in | Shown too (before ส่งเข้าครัว) |
| Non-restaurant shop hit createTableOrder | Server rejects (tier check) |
| Logo missing | Pokpok mark used; QR still EC H |

## Testing

- Node: `scripts/test_functions_tableorder.mjs` for the pure helpers (effective price incl. expired/tiny sale, item sanitize rejects); existing order-page tests must stay green (category filter helper `filterByCategory` + upsell candidate picker `pickUpsell` exported pure from their modules and covered in `scripts/test_order_page.mjs`).
- Flutter: analyze + tests pass; QR/PDF verified manually.
- Manual (owner, post-deploy): scan real printed QR → dine-in round-trip to kitchen; prepaid table order; takeaway tag; upsell popup; category chips.

## Rollout

1. functions + hosting (web modes + chips + upsell) — safe for existing shops (no table param → unchanged behavior).
2. APK 1.2.16: QR screen + logo upload + settings + orders chips.

## Out of scope (deliberate)

Modifier/topping UI on web (note field instead), customer-visible running bill, waiter call, stock decrement on kitchen send, QR poster theme customization.
