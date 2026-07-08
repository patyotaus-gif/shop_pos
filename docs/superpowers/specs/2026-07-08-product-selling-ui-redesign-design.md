# Product Selling UI Redesign — Customer Order Page + POS Picker

**Date:** 2026-07-08
**Status:** Approved by owner
**Inspiration:** Woolworths app (promo badges, Add button on card, quantity bottom sheet) — restyled to Pokpok brand (burgundy `#7A1F2B` + cream `#F5F1EC`), NOT Woolworths green.

## Goal

1. Rewrite the customer online-order page (`public/order/`) with a cleaner file structure and a Woolworths-style shopping UX: promo badges, per-card Add button, and a quantity bottom sheet.
2. Small upgrade to the POS app: the category product picker becomes image cards with promo badges instead of text chips.

**No backend changes.** The `shopPublic` endpoint already returns `price`, `originalPrice` (only when a sale is live, computed server-side), `stock`, `category`, `imageUrl` (`functions/index.js` ~L210-228). The Flutter `Product` model already has `isOnSale` / `effectivePrice`.

## Part 1 — Customer web rewrite (`public/order/`)

### File structure (static, no build step)

```
public/order/
├── index.html      ← markup skeleton + Firebase App Check bootstrap (inline module, as today)
├── order.css       ← all styles (moved out of <style>)
├── js/
│   ├── main.js     ← entry (ES module): init, load shop + products, wire events
│   ├── catalog.js  ← product grid cards + product bottom sheet
│   ├── cart.js     ← cart state + cart drawer + badge counts
│   └── payment.js  ← customer form + PromptPay QR + slip upload (MOVED verbatim, not rewritten)
└── qrcode.min.js   ← unchanged
```

- ES modules (`<script type="module">`). Browsers that run Firebase SDK v10 support them.
- **App Check contract preserved:** the inline App Check module sets `window.__appCheckToken`, and only then starts the page, so the first `/api/shopPublic` call always carries a token (the endpoint is enforced). All API calls go through the existing `apiFetch` wrapper that attaches the `X-Firebase-AppCheck` header.
- **payment.js is a code move, not a rewrite:** PromptPay EMVCo payload builder, CRC16, slip image compression (`fileToBase64Compressed`), `verifyPromptPaySlip` call, success redirect — behavior identical.

### Product card (new look)

- Product image 4:3 on top; no image → cream block + icon placeholder.
- **On sale** (`originalPrice` present and > price):
  - Circular badge **"ลด X%"** (burgundy bg, cream text) top-left over the image. `X = round((1 − price/originalPrice) × 100)`.
  - Yellow strip **"ประหยัด ฿Y"** above the name. `Y = originalPrice − price`.
  - Sale price large in burgundy + struck-through "ปกติ ฿XX".
- Name clamped to 2 lines; stock line (เหลือ N / low-stock warning / หมด).
- Full-width **"+ เพิ่ม"** button at card bottom → adds 1 to cart instantly (button press feedback; qty badge on card corner updates, as today).
- Tapping anywhere else on the card (image/name) → opens the product bottom sheet.
- Out of stock: card grayscale/faded, Add button disabled.

### Product bottom sheet (new — same pattern as existing cart drawer)

- Thumbnail + promo badges + name + price (+ strikethrough).
- Horizontal number strip **1 2 3 …** (scrollable, max = actual stock), Woolworths style.
- If the product is already in the cart → preselect current quantity; primary button becomes **"อัปเดตเป็น N ชิ้น"**, plus a secondary **"เอาออกจากตะกร้า"** button.
- Not in cart → primary button **"เพิ่ม N ลงตะกร้า"**.
- Quantity semantics are **absolute set** (not additive) — simpler for shop customers.

### Unchanged behavior (restyle only)

Cart drawer, customer info form, PromptPay payment screen + mandatory slip upload, privacy/terms links, SEO tags + canonical.

## Part 2 — POS small upgrade (`lib/screens/pos_screen.dart`)

Only the category product picker changes (the `if (_selectedCategory != 'ทั้งหมด')` block, currently a `Wrap` of text `ActionChip`s):

- Replace with a **horizontal scrolling card row** (~150px tall; cards ~110px wide):
  - Product image on top (`imagePath`/`imageUrl`; none → box icon placeholder).
  - On sale → mini "ลด X%" badge on the image corner + sale price + tiny struck-through regular price.
  - Name clamped to 2 lines, small text.
  - Out of stock → faded + "หมด", not tappable.
- **Tap card = add 1 to cart instantly** — no bottom sheet on POS (cashier speed; quantities are edited in the cart list as today).
- Everything else unchanged: search, pinned chips, cart, checkout/debt buttons, barcode scanner.

## Edge cases (both surfaces)

| Case | Behavior |
|---|---|
| Discount % rounding | `round((1 − price/originalPrice) × 100)`; savings = `originalPrice − price` |
| Sale but discount < 1% or bad data (`originalPrice ≤ price`) | No badge; show normal price |
| Sheet quantity vs stock | Number strip capped at actual stock; stock 1 → only "1" |
| Image load failure | Fallback cream block + icon (not `display:none`, so the card doesn't collapse) |
| Special characters in product names | `escHtml` at every render site (web) |
| Stock lowered after item added to cart | Server re-checks at checkout, as today (untouched) |

## Testing / verification

- **Web:** serve locally (`firebase serve` or static server) against a real shop → walk the flow: products load → promo badges on the right items → Add +1 → sheet select/update/remove quantity → cart → customer form → QR renders (no real transfer). payment.js is a verbatim move → low risk.
- **POS:** `flutter analyze` + existing tests pass; run POS to check category cards, promo display, out-of-stock state.
- Deploy: commit → `firebase deploy --only hosting` (web only; functions untouched).

## Decisions log

- Owner chose: full rewrite of the order page (not in-place patch), static split files (no framework, no build step), Woolworths interaction model (Add = instant +1; card tap = qty sheet), POS gets a small picker upgrade only, Pokpok branding throughout.
- Unit-price display (฿/100g) was considered and **rejected** — product data has no size/unit fields.
- Save-to-list ("Lists") from Woolworths — **out of scope**.
