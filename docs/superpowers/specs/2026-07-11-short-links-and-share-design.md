# Short Shop Links (/r/<slug>) + Share Button

**Date:** 2026-07-11 · **Status:** Approved; execute fully then deploy.

Shop owners want a clean link to paste into Google Maps / social, instead of `pok-pok.app/order/?shop=<long-id>&mode=takeaway`. Two pieces: a short link `pok-pok.app/r/<slug>`, and a share button in the QR screen.

**Decisions:** slug is ASCII `[a-z0-9-]`; `/r/<slug>` redirects to the takeaway order page.

## Data
- Top-level `slugs/{slug}` doc → `{ shopId }`. The doc id IS the slug — O(1) lookup + uniqueness by existence.
- Current slug mirrored on `settings/shop.slug` (app displays it; used to release the old slug on change).
- Rules: `match /slugs/{slug} { allow read, write: if false; }` — admin SDK / callables only.

## Server (functions)
- **`functions/slug.js`** (pure, Node-tested): `normalizeSlug(raw)` → lowercase, spaces→`-`, strip non `[a-z0-9-]`, collapse repeated `-`, trim leading/trailing `-`. `validateSlug(slug)` → throws Thai message if length not 3–30 or a reserved word (`order api app r admin privacy terms blog subscribe supplier payment screens js assets favicon`).
- **`setShopSlug({ slug })`** (onCall, auth required; shopId = uid): normalize + validate; transaction — reject if `slugs/{new}` belongs to another shop; delete the shop's old `slugs/{old}` when changing; write `slugs/{new}={shopId}` and `settings/shop.slug`. Returns `{ slug }`.
- **`goShop`** (onRequest) + hosting rewrite `/r/**`: extract `<slug>` from the path, read `slugs/{slug}`; found → 302 to `/order/?shop=<shopId>&mode=takeaway`; not found → 302 to `/order/` (page shows "ลิงก์ไม่ถูกต้อง"). Public (no App Check — read-only redirect).

## App (Flutter — ships in 1.2.19)
- **Settings**: new "ลิงก์ร้าน (สำหรับแชร์)" row — TextField for the slug (helper: a-z 0-9 -), Save → `ShopService.setSlug` (callable). On success show `pok-pok.app/r/<slug>` + copy button. Errors (taken / invalid) shown in a snackbar.
- **OrderQrScreen**: a "แชร์ลิงก์" button (share_plus `Share.share`) in the takeaway section, sharing a friendly message + the BEST link (short `pok-pok.app/r/<slug>` if the shop has a slug, else the long `?shop=id&mode=takeaway`). The existing copy button also uses the short link when available. The screen reads `settings.slug` in `_load`.

## Edge cases
| Case | Behavior |
| --- | --- |
| slug taken by another shop | `already-exists` → "ชื่อนี้มีคนใช้แล้ว" |
| reserved word / <3 / >30 / empty after normalize | invalid-argument with a clear message |
| owner changes slug | old `slugs/{old}` deleted, new reserved (transaction) |
| shop has no slug | share/copy fall back to the long link; `/r/` just never resolves to it |
| two shops race same slug | transaction — one wins, other gets "มีคนใช้แล้ว" |
| `/r/<unknown>` | redirect to `/order/` → "ลิงก์ไม่ถูกต้อง" |

## Testing
- Node: `scripts/test_functions_slug.mjs` — normalize (spaces, uppercase, unicode stripped, collapse/trim hyphens) + validate (length bounds, reserved words).
- Flutter analyze + test.
- Manual: set a slug in Settings → open `pok-pok.app/r/<slug>` → lands on the takeaway order page; share button shares the short link; taking an existing slug errors.

## Rollout
1. functions + rules + hosting (rewrite) — deploy.
2. APK **1.2.19+34** — Settings slug field + QR share button.

## Out of scope
Custom domains per shop; QR image regenerated from the short link (existing QR already encodes the long `?shop=` URL and keeps working — the short link is for humans, not the QR).
