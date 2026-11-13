# Android 1.2.78 (95) and website refinement

Owner authorized implementation and publication on 2026-11-13. Released and
verified live. Previous Android is 1.2.77 (94). Hosting rollback baseline is
`cb06af000098f85d`. Release subject is all source after `17fd271` plus this change.
Master is the source branch; Firebase Hosting is deployed explicitly by CLI.
Release source commit: `7c67501`. Preflight verified exactly eight expected public
path changes against the rollback version; runtime rewrites remain unchanged.

## Changes

- Restaurant sales starts with dine-in/takeaway selection. Visited workflows and
  cart stay mounted when switching; retail opens the catalog directly.
- Search, categories and favorites share one catalog; display settings and
  secondary bill actions move into menus. Cashier identity, recovery notices,
  customer/points and payment remain accessible. See `ui-layout.md`.
- Homepage and pricing page use three bounded white cards, stronger feature
  hierarchy, clear plan inheritance and user limits. Prices remain unchanged.
- Pale rose mortar curves behind the actual app screenshot and a pale rose price
  band add brand character. Only the device image enters once, with reduced-motion
  support. No new image assets, third-party libraries or continuous animation.

## Verification and publication checklist

- [x] Repository destination verified as `patyotaus-gif/shop_pos`; no remote-only commits.
- [x] Pricing browser gate: 56 states, seven widths, both routes, shop types and
  billing cycles; keyboard, 200% text, contrast, forced colours and trial links.
- [x] Hero/pricing captures at 1440, 768, 390; no overflow, reduced-motion and
  one-shot entrance checked with local browser. Real screenshot remains fully visible.
- [x] Marketing regression gate: 18 pages × five widths; links/assets, menus,
  headings, guide search, FAQ, no-JS content and overflow passed.
- [x] 53 focused app tests across eight files; targeted analysis of 13 Dart files
  reported no issues. All ran again in this release session.
- [x] Fresh isolated source review of the whole outgoing range: clean, no verified
  blockers. Separate screenshot review: no definite hard blocker; optional polish below.
- [x] Signed APK built from isolated native input copy; all 406 inputs match.
  Package/version, three ABIs and existing signing certificate verified.
- [x] Final metadata review clean after one deployment-helper fix and regression check.
- [x] Clean reviewed source committed and pushed; remote SHA `193ef23` read back.
- [x] Hosting file/config preflight; explicit `shop-pos-89294` deployment stamped with commit.
- [x] Live file hashes, APK download and version manifest verified.

Published Hosting `98a6ffde29a23f7e` at 2026-11-12 16:44:40 UTC / 2026-11-13
03:44:40 Sydney, stamped with `193ef23ef7f5778a8d3ea03230d18e207509f48e`.
All 73 public files and the exact eight expected changes verified through Hosting;
rewrites and cache/download headers match. Twelve public response hashes and a
full APK download match local bytes. Live browser smoke passed 24 states on
homepage and `/pricing/`, both shop types/cycles at 390/768/1440 widths, without
horizontal overflow or page errors. These are browser checks, not a physical tablet.

No device was connected at publication. The subsequent physical-tablet pass is
recorded below; it does not replace the publication-time browser evidence.
No backend, payment/security configuration or customer data change is required.
This local Windows build publishes Android; iOS/TestFlight needs its existing
Codemagic workflow and is tracked separately, not inferred from a Git push.

Evidence: `D:/pokpok-release-1.2.78/`; local website captures:
`.remember/tmp/background-20261113/`.

Artifact: 92,469,169 bytes; SHA256
`5db45df2aac60b3eed6fadbd98c9aa99e06a8bf1d4b75287100023e60754d951`.
The initial PowerShell wrapper terminated on a native compiler deprecation
warning. An incremental rebuild captured stdout/stderr separately and returned
actual Flutter exit 0 (40.3 seconds); staged artifact checks used that output.

Metadata review round 1 found one stale-preflight guard issue in the local
deployment helper. The helper now invalidates saved success, runs preflight
synchronously inside deployment, and verifies its commit. A simulated failed
preflight blocks the upload despite older success; successful fresh checks permit
it. Round 2 independently reviewed the helper delta and was clean. These checks
do not deploy or modify app/backend behavior.

Visual review: isolated, ephemeral read-only Codex CLI (fallback after Claude's
previous usage limit), screenshots only. No definite hard blocker. Plan comparison
on stacked mobile cards, larger-image inspection, and fuller TestFlight/printing
guidance are optional follow-ups; existing full-image link and guides remain.
Plan selection happens explicitly during app signup as stated beside the cards.
The screenshot reviewer saw retail/monthly; the browser gate independently tested
both types/cycles. Scoped design score 18/20: accessibility 3, performance 3,
theming 4, responsive 4, integrity 4. This is not a full WCAG/PageSpeed certification;
no physical keyboard or screen-reader pass is claimed. Subsequent device checks
are limited to the flows below.

## Physical-tablet acceptance — 2026-11-13

Installed Android **1.2.78 (95)** verified on Samsung **SM-X900** (2960×1848
landscape, DPR 2). Existing owner session in the explicitly authorized test shop;
no reinstall, app-data clear, security change or live-payment test.

| Journey | Observed result |
| --- | --- |
| Open Sales | Centered dine-in/takeaway chooser; takeaway catalog and cart fit landscape |
| Create temporary cart | Pasta 80 × 2 plus crepe 60 × 1 = 220; quantity controls work |
| Switch workflows | Dine-in table grid opens; returning to takeaway retains the cart |
| Display preferences | Photo/name switching and category colour work; favourites filter the catalog without changing the cart |
| Rotation/search | Portrait product grid and cart button fit; basket retains quantities/total; no-match search clears correctly; landscape returns to side-by-side layout |
| Checkout entry | Opens without permission error; cash/transfer available; admin Omise option explicitly marked Test Mode |
| Cash and keyboard | 500 cash against 220 total yields 280 change; scrolling brings confirm/cancel fully above the keyboard |
| Kitchen | Display and printer modes show bounded two-column tickets; history/guidance/print controls fit |
| Cleanup | Checkout cancelled, temporary cart emptied; photo/default colour, display kitchen mode and original auto-rotation restored; app returned to Products |

Minor follow-up: after cancelling cash checkout while the software keyboard is
open, it remains on the sales screen until Back is pressed. This was observed,
not fixed here. The portrait photo grid also wraps one long food name onto a short
second line; it remains readable and is optional typography polish.

Live website tested in **Chrome 157.0.8103.51 on this tablet**, not an emulated
viewport. Native rotation produced 1480×750 and 924×1306 CSS viewports. Sixteen
states covered `/` and `/pricing/`, retail/restaurant and monthly/yearly. Verified
199/399/599 monthly, 1,990/3,990/5,990 yearly, annual-average visibility, selected
shop type, three cards, CTA height >=44 CSS px, unbroken rendered images, no
horizontal overflow and no page errors. Trial CTA reached `/#download` from both
orientations. Device and browser captures inspected: three cards across landscape,
one centered column in portrait, legible feature hierarchy and visible hero image.
Chrome's own tab-help bubble appears on some device captures; it is browser UI.
Closed the test tab only and removed the temporary ADB port forwarding.

Evidence under `D:/pokpok-release-1.2.78/device/`: `sales-entry`, `cart-returned`,
`names-colored`, `restored-photo-confirmed`, `portrait-catalog-settled`,
`portrait-basket`, `payment-scroll-end`, `final-empty`, `kitchen-first`,
`kitchen-printer-settled`, `reconnected-state`, `device-finished`, `web-*.png`
and `web-results.json`. Screenshot/XML capture is sequential, so transitional
captures are not visual acceptance evidence. A brief USB disconnection interrupted
the final capture; connection and restored kitchen mode were verified afterwards.
The sampled recent app-process log contained no fatal, unhandled Flutter or layout
overflow markers; logs are not a complete functional test.

**Not exercised:** final payment/sale persistence, actual printing/Bluetooth,
staff or account switching, offline recovery, scanner hardware, bundle addition,
iOS, screen reader or physical keyboard. Existing kitchen orders were viewed;
their statuses were not changed. The kitchen output preference was briefly saved
and restored, but no sales/product/customer records were changed. This task adds
test evidence only and does not produce another release.
