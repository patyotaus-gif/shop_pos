# UI sizing review — 2026-10-30

Scope: rechecked Flutter screen layout and shared controls after the user reported an oversized receipt preview on a tablet. Released Android 1.2.66+83 through Firebase Hosting, replacing public build 82.

## Changes

- Sale receipts: limit preview pages to 360 logical pixels for 58 mm, 480 for 80 mm and 720 for A4. On sufficiently wide/tall screens, scrollable tools occupy a 320-pixel side column; otherwise they occupy a bounded, scrollable area above the preview. Enlarged text uses the stacked layout. Total/change appear first; the continue/back action stays outside the scrolling areas with a 360-pixel maximum width. PDF generation, physical paper size, sharing, saving and Bluetooth bytes are unchanged.
- A5 preparation-ticket preview: maximum page width 560 logical pixels.
- PIN/account selection and short forms: widths 520–640; product/modifier forms and printer/subscription settings: 720–840. Existing field validation and actions remain intact. Direct form actions use the shared compact button with a 48-pixel minimum tap area.
- Customer, staff, inventory, debt, promotions, order and marketplace lists: maximum width 1040. Analytical reports: 1200. Chat: 840. The stock scanner page/viewfinder is bounded at 760. Product management list/search are bounded; its image grid continues to adapt to available space.
- Stock-receive shortcuts and auto-print actions use compact buttons. Supplier checkout actions wrap onto another line when their labels/summary cannot fit, instead of relying on a stretching row.
- Existing bounded login/register, settings sections, dashboard, cash closing, money movements and QR page were reviewed alongside the changes. Existing adaptive sales/table/product grids, kitchen tickets, payment sheets and navigation retain their layouts. No global text-scale reduction or global forced button width was introduced.

## Validation

- Full Flutter suite: **348 passed**. Full analyzer: no issues. A final compact-button adjustment in auto-print was followed by a clean targeted analyzer check. Final document/compact-action focused run: 13 passed, including explicit receipt preview width assertions for each paper format.
- New interaction tests cover 320×568 and 390×740 phones, 740×390 landscape, 800×1100 portrait tablet, 1480×924 landscape tablet, 200% text and a simulated keyboard. Document preview remains visible, all tools can be scrolled to and tapped, and the footer stays reachable. Real table/PIN forms retain validation and bounded field/action widths.
- Existing receipt-paper test confirms selecting 58 mm / 80 mm / A4 still generates the corresponding document, and printer-requested page changes do not silently change the selected receipt bytes. Existing catalogue, payment, staff permissions and other workflow tests remain passing.
- These tests cover representative layouts, not every possible customer device, text value or keyboard. Physical iOS and printer testing are outside this sizing review.

## Device review

- Built and installed local Android candidate `1.2.65-ui-review`, build 82, over the existing app on Samsung SM-X900. Release-mode build completed in 199.8 seconds; the shop session remained available. At release time ADB reports no connected devices, so the final build 83 has not been installed or inspected on the tablet.
- Confirmed the original oversized receipt on the tablet before installing. Opened the same existing cash bill through report history after installing; landscape preview is bounded and scrolls to the complete footer, while portrait shows the complete example slip. Totals/change and print/share/continue controls remain visible. No payment, refund or print command was submitted.
- Inspected the report/history, product catalogue, product-add form and its final save action with the Thai keyboard open. The form is centered, input widths are bounded, the save action is compact and reachable by scrolling above the keyboard. Exited without entering/saving a product. Restored device rotation settings to their original values (`accelerometer_rotation=1`, `user_rotation=0`).
- Private evidence: `.remember/tmp/sizing-before.png`, `sizing-receipt-landscape.png`, `sizing-receipt-footer.png`, `sizing-receipt-portrait.png`, `sizing-product-form.png`, `sizing-product-save-keyboard.png`. Screenshots contain test-shop details and are not published.

## Release verification

- Built final release `app.pokpok.pos` 1.2.66+83 in 116.8 seconds. Verified package version and original signing certificate SHA-256 `f7dc70e0464fed06f8c0d14907ef71a75effb566e41e67d1aa685491dff547eb` before publication.
- Backed up and hash-checked previous public build 82 APK/manifest. Deployed Hosting only; no backend or rules changes. Held receipt-feed stash remains excluded.
- Downloaded the complete public APK from `https://pok-pok.app/app/pokpok.apk`: 96,100,718 bytes, SHA-256 `9a404ffd040f74a9f97871a08502494ba2a9adc48a8f71cdb9e08fcf1ac73221`, identical to the built APK and version manifest. Manifest advertises optional build 83, minimum supported build 1. No-cache headers verified.
- Final build could not be installed because no ADB device was connected. No iOS IPA/TestFlight release was performed. Private release evidence: `.remember/tmp/release83-build.log`, `release83-deploy.log`, `release83-verified.json`.
