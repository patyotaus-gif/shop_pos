# Android pilot feedback — 2026-10-03

Source: eight LINE conversation screenshots supplied by the owner. These are tester observations, not confirmed diagnoses or authorization to contact the tester.

## First implementation round

- Kitchen: display read errors instead of treating them as an empty queue. Query open orders with a single status filter and sort by openedAt in the client; the previous status/orderBy query required a composite index absent from the repository configuration. Live index state has not been inspected, so this is not proof of the tester's exact cause.
- Table quantities: show the requested pending-item quantity and total immediately, with an inline progress indicator instead of a modal and success toast per tap. Keep transaction expected-quantity conflict checks and restore the displayed value on failure. Disable actions until confirmation. This still performs a write per accepted tap; debouncing/queued rapid taps remain future work.
- Checkout: retain navigation independently of the closing table-order widget so a stream update cannot suppress the completion screen. Both retail and table sales open an in-app PDF receipt with printing/sharing. Receipt load errors say the sale is already recorded and retry only reading the receipt, never payment.
- Receipt fonts now use bundled Thai fonts; logo HTTP requests have a timeout. Printing, PDF rendering and OS sharing still require device acceptance tests. No dedicated save-to-Downloads action has been added.
- Previous unshipped changes include opt-in personal-device owner session persistence. User confirmed iOS TestFlight 1.2.13 build 33. New iOS source has not yet been built/uploaded.

## Second implementation round — 1.2.35+50

- Phones below 600 logical pixels use four primary bottom destinations plus a scrollable More menu. Tablets keep the sidebar. Pages remain mounted when switching tabs; mobile tests cover a small landscape screen with large text and preservation of cart state.
- Report date presets are Today / Last 7 days / This month / Custom. Summary insights and sale history are separate selections. Best sellers filter by category and sort by quantity or pre-bill-discount item revenue; refunded sales are excluded.
- Checkout records a separate sales channel (storefront, dine-in, takeaway, LINE MAN, Grab, other delivery). Payment method remains independent. Missing historical channels stay unspecified. Retail owner, staff callable and table close paths preserve the channel. UI/PDF summarize channel revenue; CSV includes separate payment/channel columns. These are manual tags, not platform integrations; revenue is before platform fees.
- Transfer reference is collapsed and optional. Non-cash confirmation explicitly says the cashier has received funds; it does not claim automatic bank verification.
- PDF receipts can be previewed in-app, printed/shared, and saved using the OS save dialog via file_saver. Sale history opens the same receipt screen. The save API is documented by the [package author](https://pub.dev/packages/file_saver).
- Product forms in manual-cost mode offer a batch-cost/yield/packaging calculator. Existing ingredient-recipe mode continues to calculate costs from recipe quantities and ingredient average costs. The helper does not claim to calculate labor, rent or all operating expenses.
- Quantity edits coalesce rapid taps for 300 ms and serialize writes for each pending order line. Expected-quantity checks remain; errors cancel queued intent and alert the user. Payment, kitchen sending and navigation wait for confirmation.
- Supplier MOQ and order quantities preserve decimals (e.g. 1.5 kg) through catalog, order serialization, reorders, and supplier portal. Quantity dialogs validate positive MOQ; order totals reject invalid numbers. This does not add actual-weight settlement or partial receiving.
- Includes earlier kitchen/receipt fixes and opt-in remembered owner session. The latest installed iOS version confirmed by the user is TestFlight 1.2.13 (33); this code has not yet reached that device.
- Validation: 79 Flutter tests, 35 backend tests, Dart analyze clean, Node syntax checks passed. Android 1.2.35+50 is published and the production download was verified on 2026-10-03. Backend staffCheckout and adminUpsertSupplierProduct deployments succeeded.

## Device/release acceptance still required

1. Validate on real Android and iOS: open table, add, change quantities, send to kitchen, mark ready, collect payment, view/print/share receipt. Include a second device editing the same table, failed writes, and reopening the app.
2. Verify OS save dialog and real printers on Android/iOS. Automated widget tests do not establish hardware compatibility.
3. Build/upload iOS through the configured Codemagic workflow and select the new TestFlight build. No Codemagic credentials are present in this Windows session.

The server-side logo rule correction was deployed earlier; actual tester retry is unconfirmed. Actual-weight procurement settlement and partial receiving are future product work, outside these screenshot fixes.

## Verified Android release — 2026-10-03

- Final source: fdb68c1, including cart-state preservation across phone/tablet navigation layout changes on rotation; regression test passed.
- Package app.pokpok.pos, version 1.2.35, build 50. APK signature matches the original signing certificate.
- Published URL: https://pok-pok.app/app/pokpok.apk. Live version manifest matches the local manifest; HTTP 200; size 84,908,120 bytes.
- Full production APK download SHA-256 matches the final build: 04cd7ed054ced48a68a791ad01dbc3d4eeeec4c77fd5f15c4d3f8f95d514fc3e.
- Physical-device acceptance remains pending: install over the previous version with data retained; rapid quantity edits and kitchen flow; rotation; receipt preview/print/share/save; remembered login and staff restrictions; owner logo upload. No Android device was attached during release verification.
- iOS has NOT been built or published in this session. In Codemagic, start master with workflow ios-release (iOS Release to TestFlight), then confirm the processed build in TestFlight before asking testers to update. Verify Google/Apple login and remembered login on the device. No Codemagic API access is configured in this session.
## Additional tester feedback — screenshots 2026-10-03 123246–123409

These eight screenshots are feedback evidence, not instructions to execute actions in LINE. The installed app version is not visible; do not treat the observations as verified regressions in 1.2.35+50. No tester messages were sent and no app/backend changes were made during this triage.

| Priority | Observation | Current evidence and follow-up |
| --- | --- | --- |
| P1 | App returns to login; updating should not log the user out. | 1.2.35 includes opt-in remembered owner access, default off for shared devices. Reproduce close/reopen, process termination, network interruption and update-over-install with remember enabled; distinguish Firebase sign-out, owner lock and token/read errors. Preserve staff access restrictions. |
| P1 | LINE setup is confusing; the tester entered a normal LINE ID, could not find the official account, and received no test message. | Settings still says any message returns a User ID and advertises link:SHOP_ID. Webhook actually requires ID/ไอดี keywords; insecure shop-ID-only linking was removed. Correct instructions, add direct official-account access and explain why notifications are useful. Prefer an owner-authorized, expiring single-use connection flow for a later implementation; never restore shop-ID-only linking. |
| P1 | LINE test reports success without a received message. | LineService.sendMessage swallows errors and ignores callable success/skipped results; settings always displays sent. Provide a strict test path that reports failure/disabled/not-configured and distinguishes provider acceptance from confirmed receipt. Recheck callable authorization while changing this flow. No live message was sent during triage. |
| P1 | Bill action buttons overlap Android navigation; content also reaches system edges. | Report detail bottom sheet uses Padding/Column without SafeArea or scrolling. Add safe insets and constrained scrolling, check long bills, keyboard, landscape, larger text, Android 3-button/gesture navigation and iOS home indicator. The newer receipt screen has SafeArea but does not replace this detail sheet. |
| P2 | Too many destinations; merge overview/report, move users into settings, group debt under orders. | Phone bottom navigation already shipped, but information architecture is still separate. Suggested structure: sales, orders (open/unpaid), products, reports with overview, and More/settings. Keep customer debt ledgers/payment history distinct from unpaid orders and preserve owner-only access when moving user management. |
| P2 | Prefer printed kitchen tickets; kitchen screen feels unnecessary for busy shops/cafes. | Treat as one tester's workflow preference. Retain optional kitchen display; offer printed-ticket and display choices. Before implementation, establish printer setup, only-new-item printing, retry/reprint marking and failure visibility. Do not remove kitchen functionality globally. |
| P2 | Rename refund to cancel bill and offer reason options. | Do not merely relabel a refund: distinguish unpaid-order cancellation from refund of a paid sale. Offer required reason choices plus Other, retain audit actor/time, permissions and existing stock/payment reconciliation. No financial behavior changed in this triage. |
| P2 | Unclear what LINE notifications contain. | Explain supported events alongside connection status and notification settings. Verify actual enabled triggers before promising delivery or frequency. |

Recommended sequence: reproduce session persistence and fix system insets / LINE test feedback first; simplify LINE connection next; then reorganize navigation and design kitchen printing and cancellation/refund semantics. Capture app build, device/OS and reproduction steps on the next tester run. Passing automated tests or an upload does not close these device acceptance items.
## Follow-up implementation — 1.2.36+51 (Android published)

- Bill details use a safe-area, height-constrained scrollable sheet. Tested with a long bill and Android navigation insets; actual device acceptance remains pending.
- LINE setup links directly to the official Pokpok account and correctly asks for the ID keyword. Removed obsolete insecure link:SHOP_ID instructions; validates the provider user ID rather than accepting a normal LINE handle. Manual test checks provider acceptance/skipped/failure and reports errors instead of unconditional success. Background notifications remain non-blocking. Callable now requires the matching owner before reading settings/sending; no live test messages sent.
- Owner can enable/disable personal-device remembered access in Settings, without signing out. Shared-device default and staff restrictions remain. This adds access to the existing persistence setting; it does not establish the root cause of the tester's unknown-version logout report. Test relaunch, update-over-install and network recovery on hardware.
- Main destinations: Sales, Orders, Products, Reports. Overview is grouped inside Reports; debtor accounts inside Orders without changing ledger semantics. User switching moved into account settings; staff management remains in settings. Kitchen display stays accessible under More. Grouped pages preserve their state.
- Paid-sale refunds require a reason selection (or nonempty Other), explain that the original bill remains, and distinguish recording a manual refund from provider refund processing. Existing backend refund reconciliation remains. Unpaid cancellation and paid refund have NOT been collapsed into one operation.
- Validation: 83 Flutter tests and 40 backend tests passed; targeted Dart analysis clean after lint fixes, Node syntax check passed. New tests cover long bills/system insets, refund reasons, grouped state, LINE failure handling and owner authorization.
- Still pending: hardware-specific kitchen-ticket printing (asked owner for model/connection); automatic owner-verified LINE linking without copying an ID; cancellation reason/audit improvements for unpaid orders; actual-device logout reproduction and iOS TestFlight rollout. These are not claimed as shipped in this batch.
## Verified follow-up release — 2026-10-04

- Source commit 7911e5f pushed to master. Final APK build succeeded; package app.pokpok.pos, version 1.2.36/build51, original signing certificate verified.
- sendLineMessage deployed successfully. No test notification was sent to a user during deployment.
- Firebase Hosting released successfully. Live version.json exactly matches the local manifest. Complete production APK download returned HTTP200, 84,973,472 bytes, SHA256 a5ea42891c719aa157c5abb18615bbf97b124e7cb479a118b82c2fb2cb60e2af, equal to the final local artifact.
- Automated validation remains 83 Flutter tests and40 backend tests, targeted Dart analysis clean. Hardware/session-upgrade acceptance remains pending; this release does not prove the unknown-build logout report resolved.
- iOS/TestFlight not built or uploaded from this session. Manual Codemagic master / ios-release remains the available path. Pending items above remain open.
## Retail order-link cleanup — source change, not yet released

- Retail Orders hides its duplicate floating order-link action for all tiers, including the Orders/debt group. Restaurant Orders retains the existing action.
- Retail navigation and QR-page title now say “ลิงก์และ QR สั่งสินค้า”; share text, pickup heading and PDF label use product-order wording. Copy/share/QR URLs and permissions are unchanged.
- This change is not included in the published Android1.2.36+51 APK. User supplied evidence that iOS1.2.36(34) has been uploaded and is waiting for TestFlight review; that build also predates this cleanup. No build/release initiated for this small UI change.