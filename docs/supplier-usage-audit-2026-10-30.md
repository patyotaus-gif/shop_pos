# Supplier usage audit — 2026-10-30

User authorized simulated-data testing, then requested fixes and release. Tested the actual `public/supplier/index.html` DOM and event handlers in headless Chrome with in-memory Firebase adapters and all browser network requests blocked. Separately exercised the actual marketplace handlers and Firestore rules on the local `demo-pokpok-admin` emulator. The seven findings below are **fixed and deployed on 2026-10-30** with release 1.2.64+81: Hosting, Firestore rules and `marketplacePlaceOrder`. Public supplier HTML matches local source; the changed function is ACTIVE and rejects unauthenticated requests. No production business order/account/notification was created. LINE contrast shipped in the Android app in the same release.

## Fix verification

- Money uses two decimal places and the stored order total, with rounded line totals as the legacy fallback. Browser checks cover 12.50, fractional quantity 1.5, 18.75 and an authoritative total that differs from the item sum.
- Product and profile forms reject blank/negative/nonfinite/out-of-range numeric input. Rules also enforce names, nonnegative price/minimum order and positive fractional MOQ. Emulator tests reject bad writes, allow fractional values and confirm legacy invalid data can be repaired. Existing invalid records are not automatically rewritten; they must be corrected before updates will pass validation.
- Narrow catalog cards wrap details and move actions below; a 390-pixel viewport now remains 390 pixels wide with long unbroken names. Retry states handle profile fetch and list subscriptions; profile save preserves inputs on failure; status actions restore labels and allow retry. Availability/delete failures are caught.
- New marketplace orders snapshot the shop's registered address/phone in both copies. The portal labels these as shop details at ordering time, not a separately confirmed delivery destination. Old orders explicitly show unavailable contact fields. Emulator tests verify retries retain the original snapshot even after the shop address changes. No historical data backfill.
- Final browser journey and stored-XSS regression passed. Both catalog-rules and security-hardening emulator suites passed, including lifecycle, mirror consistency, idempotency, concurrent transitions and tenant boundaries. Evidence: `.remember/tmp/supplier-fix-*-final.log` and updated private screenshots.
- Release deployed the supplier hosting page, Firestore rules and `marketplacePlaceOrder` backend update. Real-account, App Check, physical-device browser, upload and LINE checks remain outstanding.

## Confirmed findings

| ID | Priority | Reproduction and impact | Suggested change |
| --- | --- | --- | --- |
| SUP-01/02 | High | Catalog price 12.50 displays as 13; an order for 1.5 units totals 18.75 but displays 19. The shared `baht` renderer rounds to an integer. The underlying fixture write retains decimals; this is a display discrepancy, not evidence of an altered charge. | Format two decimal places; use the authoritative order total, with a defined legacy fallback. |
| SUP-04 | High | Product form sends price -10 and MOQ 0. Actual Firestore rules allow the supplier to save them. Marketplace checkout then rejects that product. Profile rules also permit a negative minimum-order value. | Validate finite numeric ranges in the form and database rules, while retaining valid fractional quantities. Audit existing invalid catalog data before introducing strict updates. |
| SUP-03 | Medium | At a 390-pixel viewport, a long unbroken product code expands document width to 849 pixels and overlaps actions. Ordinary Thai product names fit at widths 320/390/800/1480, though the 320 layout is cramped. | Allow word breaks and give product details and actions separate rows on narrow screens. |
| SUP-05 | Medium | Injected profile update failure produces an unhandled rejection with no inline failure/retry guidance. | Disable save while pending; catch failures, retain inputs and offer retry. |
| SUP-06 | Medium | Injected order-status failure shows an alert, but the action remains labelled `…` after it is re-enabled. | Restore the original label on failure and keep retry available. |
| SUP-07 | Medium | Authentication succeeds but the subsequent supplier-profile fetch fails. The user remains on the login screen without an explanation; the auth callback rejects without handling the error. | Distinguish authentication from profile loading; show a retry state and handle callback errors. |

The original contact-information gap is addressed for new orders using the registered shop contact snapshot described above. Separate delivery destinations and real supplier fulfilment have not been tested.

## What passed

- Simulated login, rejected-login error, catalog creation with decimal price/fractional MOQ, availability toggle, successful profile update, empty orders, logout/password clearing.
- UI accept → ship → waiting for shop receipt calls the correct supplier status handler.
- Actual emulator: order creation and both mirrored copies, accept → ship → customer receipt, fee calculation, repeat-request idempotency, competing cancel/ship, cross-account access restrictions and denial of direct order tampering.
- Existing browser stored-XSS regression: hostile item fields/document IDs render without executing scripts; legitimate actions remain intact.

## Reproduce and evidence

- `scripts/audit_supplier_journey.cjs`: browser regression now requires zero findings and checks recovery flows. Set `PLAYWRIGHT_MODULE` and `BROWSER_EXECUTABLE` to local installations.
- `scripts/audit_supplier_catalog_rules.cjs`: emulator regression now requires invalid writes to be rejected; refuses non-local emulator endpoints. Run through `firebase emulators:exec --only firestore --project demo-pokpok-admin --config firebase.rules-test.json "node scripts/audit_supplier_catalog_rules.cjs"`.
- Existing `functions/security_hardening.integration.cjs` and `scripts/test_supplier_security.cjs` passed.
- Private evidence: `.remember/tmp/supplier-audit/findings.json`, catalog screenshots, `.remember/tmp/supplier-audit-browser.log`, `supplier-audit-emulator.log`, `supplier-audit-catalog-rules.log`, `supplier-audit-render-security.log`.

Limitations: browser SDK/auth/network operations were simulated; only backend/rules checks used the real local emulator. Hosted App Check, real supplier credentials, image upload/compression, LINE delivery, tablet browser and iOS were not verified. External fonts were blocked with other network requests, so screenshots use the fallback font.
