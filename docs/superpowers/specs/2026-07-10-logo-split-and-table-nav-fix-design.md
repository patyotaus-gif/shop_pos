# Logo Split (QR-center vs shop banner) + Table Nav Fix

**Date:** 2026-07-10 · **Status:** Approved; execute fully then deploy (owner).

## Part 1 — Table nav fix (already implemented, ships in 1.2.17)

Bug: the "โต๊ะ"/"ครัว" tabs gated on the `shopType` field, but the founder-console `adminSetSubscription` upgrade wrote only `tier`, leaving `shopType="retail"` on shops upgraded from retail → restaurant screens never appeared.

Fix:
- `functions/index.js` `adminSetSubscription` (activate op) now also writes `shopType` derived from tier (restaurant → "restaurant", else "retail").
- `lib/main.dart` nav gates restaurant screens on `tier == ShopTier.restaurant` (single source of truth, consistent with the QR screen + Entitlements), so a stale `shopType` can never hide the tabs again.

## Part 2 — Logo split

**Decisions:** QR-center logo = fixed Pokpok mark (shop owners cannot change it — brand consistency on every printed QR). Shop's own logo → full-width head-band banner on the `/order` customer page. Shop uploads it from Settings.

### App (Flutter)
- `order_qr_screen.dart`: remove the "เปลี่ยนโลโก้" upload row and all shop-logo state; the on-screen QR always embeds `AssetImage('assets/icon/icon.png')`.
- `qr_pdf_generator.dart`: center logo always the Pokpok asset (caller loads it via `rootBundle`); drop the shop-logo path.
- `settings_screen.dart`: add a "โลโก้ร้าน" row → pick image → `ImageService.saveShopLogo` → `settings.logoUrl` (same field/storage as before). Shows current logo + replace/remove.

### Server
- `getShopPublic`: response gains `logoUrl` read from `settings/shop` (unconditional single read).

### Web `/order`
- `index.html`: `<div id="shopBanner" hidden><img></div>` full-width at the top of the content, above the category bar.
- `order.css`: banner full-width, height ~120px, cream background, `object-fit: contain` (no crop for any logo aspect).
- `main.js`: when `data.logoUrl` present, set the banner `src` + unhide; else leave hidden (existing SVG-mark header unchanged).

### Migration
None. `logoUrl` is the same field 1.2.16 wrote; shops that uploaded a logo there simply see it move from the QR center to the `/order` banner.

## Testing
- Node suites unchanged (no tested-helper logic changed) — must stay green.
- `flutter analyze` clean + `flutter test` pass.
- Manual: upload logo in Settings → `/order` shows banner; QR (screen + PDF) shows Pokpok mark regardless.

## Rollout (one round)
- Deploy `functions` (shopType sync + getShopPublic logoUrl) + `hosting` (/order banner).
- Release Android **1.2.17+32** (table nav fix + Settings logo upload + QR-center Pokpok).

## Out of scope
Per-shop admin-set QR-center logo (kept as fixed Pokpok asset); banner theme/aspect customization.
