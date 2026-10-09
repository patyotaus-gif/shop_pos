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
## Order-link consolidation for both shop modes — source only

- Owner confirmed restaurant Orders should also drop the duplicate link. Removed the floating link action, its dialog, unused imports and the temporary retail-only flag. Both shop modes now use the existing QR page for copying/sharing ordering links; per-table QR remains separate.
- Targeted Dart analysis passed. Not built or published yet; this supersedes the earlier note that restaurant Orders retains the action.
## Android 1.2.36+52 published — 2026-10-04

- Built all current fixes from source4451141, including retail QR wording and removal of the duplicate Orders link in both shop modes. Package app.pokpok.pos and original signing certificate verified.
- Firebase Hosting succeeded; live manifest matches local1.2.36/build52. Full APK download:84,973,400bytes; SHA2566c7f12c57aa9a635e8c64871df6cbc30b05abc0537a02cce5959885bb8b28f51 matches the release artifact.
- This supersedes the source-only release notes above. Targeted Dart analysis passed for the latest UI changes; the prior full suite was83 Flutter/40backend tests. No physical-device acceptance performed in this build step.
- iOS version stays1.2.36. Source is on master; Codemagic ios-release automatically uses the next App Store Connect build number. No Codemagic credentials available here, so no new iOS build was triggered. User's screenshot previously showed1.2.36(34) awaiting TestFlight review; current approval status not checked.
## LINE friend QR — source change, not yet released

- Added a responsive, white-background QR for LineService.officialAccountUrl on the LINE settings section, above the existing open-LINE button and connection-ID field. Tablet/POS users can scan with a phone; same-device users retain the button. Both use the same existing official account URL.
- Updated instructions to describe scanning or opening LINE, sending ID, and pasting the returned code. No account linking or message is performed by displaying the QR. Physical scanning still needs acceptance; published Android1.2.36+52 predates this change.
## Order/accounting consistency audit — 2026-10-04

See [order-accounting-audit.md](order-accounting-audit.md) for payment/order/cash/debt/refund/report findings. Two isolated tests reproduced incorrect cash-close and refunded-debt aggregation. This was an audit only: no production data changed and no fixes/deployment performed. Prior green tests are not evidence these financial invariants hold.

## Order/accounting fixes — 2026-10-05, not yet released

- Implemented linked order/sale/payment transactions, immutable cash movements, balance-checked debt collection and immutable cash close. Fixed double subtraction of cash refunds and separated sales from actual money received and current debt balances.
- Customer order slips/bank-notification matches require owner verification; Stripe payments/refunds require successful provider status. Repeated delivery is idempotent. Paid cancellations use the refund path; returns to stock are explicit and default off. Prepared-item cancellation records waste; ingredient event ordering and loyalty reversal are guarded.
- Reports include modifier costs and allocated discounts. Owner can open money history and a read-only discrepancy review from reporting/cash-close flows. Historical records are not automatically rewritten.
- Validation: 89 Flutter tests, 54 backend tests, clean Dart analysis and passing Firestore Emulator access/transaction integration suites. Final cash-close dialog uses the saved count when another device closes first; Z-report distinguishes net sales, net receipts and debt movement.
- **Not built, committed or deployed in this accounting batch.** Live Android remains 1.2.36+52. No new TestFlight upload or actual-device verification performed. Full implementation and rollout limits: [order-accounting-audit.md](order-accounting-audit.md).
- Coordinated migration is required: new financial rules reject older clients' direct writes. Update active terminals and validate Android/iOS before switching rules; sync pending offline receipts and review legacy open sessions. Stripe event subscriptions also need production verification. Separate subscription-plan slip activation remains an unresolved payment-verification path; do not confuse it with the fixed customer-order flow.

## Authentication-check error reported — 2026-10-05, source fix only

- Tester screenshot shows the authentication-check failure screen with offline entry/sign-out, rather than a subscription-expiry screen. The screenshot alone does not establish expired credentials, revoked access or the underlying network error; installed version/build and result after re-login were requested.
- Confirmed source failure path: an error reading ID-token claims propagates into the root auth stream. The old error screen offered no retry and no resume recovery, leaving users dependent on another token event or signing out.
- Added explicit retry by subscribing afresh to Firebase authentication, and one retry when returning to the app after a failed check. Healthy sessions are not restarted; persistent errors do not create a retry loop. Reading claims has a 20-second timeout. Network/timeout messages no longer tell users they must sign out; invalid-session and disabled-account errors have separate wording.
- Existing owner unlock, remembered-device preference and staff claim validation still apply only after a successful check. No fallback grants owner access when token verification fails. Offline entry continues to use its existing separate authorization path.
- Five focused regression tests passed: manual recovery, app-resume recovery, persistent error without a loop/protected content, sign-out following a stream error, and network-versus-expired-session messaging. Targeted analyzer passed. Actual tester-device reproduction remains pending; no new APK, backend deployment or TestFlight build performed for this fix.

- Full Flutter regression suite after auth recovery: 94 tests passed (.remember/tmp/auth-recovery-full-test.log). This includes the 89 accounting/baseline tests and five new auth recovery tests.

## Android 1.2.36+53 published — 2026-10-05

- Released the authentication-recovery hotfix and previously committed LINE friend QR. Source commit 60558a8 was pushed to master. Explicit retry and resume-after-error recheck do not grant access until existing owner/staff checks succeed; network errors no longer automatically instruct sign-out.
- Built from an isolated export of cee60ea plus the exact committed hotfix/version files. The pending order/accounting migration is deliberately excluded from this release. No Cloud Functions or Firestore rules deployed; existing terminals keep their current backend paths.
- Isolated release validation: 88 Flutter tests passed and targeted Dart analysis clean. This is distinct from the working-tree 94-test run that includes unpublished accounting changes.
- APK package app.pokpok.pos, version 1.2.36/build53, original signing certificate verified. Firebase Hosting succeeded. Live manifest returned build53; full public download verified package/version and matched the built file: 84,989,784 bytes, SHA256 2d18f5d456478f93e0dbd532295b1982b7d3fcf47975458238bf9ae13e13951f.
- Download: https://pok-pok.app/app/pokpok.apk . Prior build52 APK retained locally for rollback. Logs: .remember/tmp/auth53-build.log, auth53-tests.log, auth53-analyze.log, auth53-deploy.log.
- iOS source is on master with marketing version1.2.36 unchanged. Start Codemagic ios-release / iOS Release to TestFlight manually; no API/browser capability available to start it here. No new iOS build/upload or physical-device acceptance claimed. Exact tester-device root cause still requires installed build and reproduction evidence.

## Customer ordering website published ? 2026-10-05

- Source478a909 pushed and Firebase Hosting deployed from isolated release staging, excluding pending accounting/payment-verification changes. Android APK/manifest remains1.2.36+53; no backend or Firestore rule deployment.
- Mobile product grid now displays two items per row, including320px screens. Search works with categories; category chips remain visible for a single-category catalog and blank categories use the general group. Closed sheets no longer appear outside the viewport.
- Product Add opens configuration whenever options exist; required choices cannot be bypassed. Quick upsell excludes configurable products. Cart identity includes preparation notes, and all configurations share the stock cap. Successful kitchen submission clears every line; failed submission retains the cart. Kitchen confirmation shows options and notes.
- Draft cart survives reload in the same browser tab, isolated by shop/mode/table, with a2-hour lifetime. Restore recalculates prices/options/stock from the current catalog and discards invalid/expired selections; unavailable browser storage does not block ordering. Once a takeaway order is accepted or a kitchen submission succeeds, its cart is removed from draft storage. This does not implement pending-payment recovery or backend idempotency for ambiguous network outcomes.
- Node order-page regressions passed. Headless Edge fixture tests passed at320/375/414px and desktop, covering category/search, required choices, distinct notes, refresh, kitchen failure/success, table isolation and accepted takeaway draft clearing. Tests used local fixture APIs only; no real customer orders or payments submitted.
- Verified9 production HTML/CSS/JS assets byte-for-byte after newline normalization against release staging, plus no-cache headers and unchanged Android build53 manifest. Module URLs carry a coordinated asset version to avoid old/new cache mixtures. Screenshot: .remember/tmp/order-mobile-two-columns.png; browser log: .remember/tmp/order-release-browser-test.log; deployment log: .remember/tmp/order-web-deploy.log.


## Customer slip upload hotfix published - 2026-10-05

- Production logs for the reported attempts show TypeError: Jimp.read is not a function, not a file-size rejection. The installed Jimp 1.x API now decodes browser JPEGs through the exported Jimp class with decoder memory/resolution limits.
- Source b239531 pushed to master. Deployed only verifyPromptPaySlip and Firebase Hosting from an isolated committed-source export. No financial migration, Firestore/Storage rules, subscription-payment endpoint, Android binary or iOS release deployed.
- Customer slips are saved as evidence and attached to pendingPayment orders with slipReviewStatus awaitingOwner. A QR amount is not proof of funds received; this endpoint never marks an order paid. Existing apps display slipUrl and let the owner check the bank account and confirm receipt manually.
- Each attempt gets a unique image object. A confirmed concurrent order-state change rejects the attachment and removes the unreferenced image. Ambiguous database errors preserve possibly attached evidence. Image size/type/decoding errors are readable; browser PNG/JPEG images are reduced to JPEG before upload, with retry available without another transfer.
- Validation: 52 isolated-release backend tests passed (12 upload-specific); order-page Node regressions and headless Edge fixture browser tests passed, including PNG compression, failed upload followed by same-file retry, and a pending-review completion page. These are automated fixture results, not real bank or physical-device payment verification.
- Production verification: Hosting and function deployments completed. Live endpoint reports X-Pokpok-Slip-Version 2, GET returns 405, unauthenticated POST returns 401. All three changed web assets matched the release copy and returned no-cache. Android manifest remains 1.2.36 build53.
- Logs: .remember/tmp/slip-functions-deploy.log, slip-hosting-deploy.log, slip-release-tests.log and slip-release-browser.log. Logs may contain sensitive deployment metadata; do not share raw files.
- Device acceptance still needed: a customer uploads the existing paid slip, the shop opens it in Orders and checks actual bank receipt before confirming. No live customer order was created or changed for this release check. Subscription-plan slip verification remains a separate unresolved path.


## Closing-integrity recheck - 2026-10-05 (source only)

- Rechecked the unpublished accounting migration after the tester reported confirmed online payments absent from today's sales. The live Android release is still 1.2.36+53. Only the separate customer-slip upload hotfix is live; the accounting changes below have NOT been deployed.
- Added a transactional closing integrity check. Closing now refuses known paid online orders with missing/duplicate sales, unreviewed slip/bank matches, recently closed table orders without a sale, recent sales/refunds/debt receipts without their money movement, malformed/orphan/mismatched movements and unassigned/late movements. Failures leave the session open and include source IDs. It verifies integer satang against source documents before snapshotting.
- Successful close stores integrityVersion and checkedMovementCount. Unpaid orders and open table bills remain unchanged and their counts are included in the immutable summary, close result and Z-report; they are not invented revenue. Repeated close retains the first summary and actual cash count.
- Device rules now require amounts/method to match the sale, the correct current session/reconciliation flag, and the same atomic cashControl revision update. Emulator regressions reject omitted synchronization writes, mismatched amounts and attachment to an already closed session.
- An old open-session request cannot reopen a closed session or silently accept a different opening float. The app clears only definitively completed old request IDs, checks local persistence and reloads local pending-checkout state before closing.
- Legacy debt balances must agree with their credit sale and remain within 0..original total before collection/refund. Inconsistent records fail for review instead of creating invented receipts/refunds.
- Dashboard no longer labels all non-credit payments as cash: it shows cash sales only and reports load errors instead of a false zero. Calendar-date reports now include the final fractional second before midnight and exclude the following day; today's query also excludes future-day receipts.
- Verification: full backend suite 75 passed; full Flutter suite 95 passed, then final focused Flutter transaction/accounting suite 18 passed including the added date-boundary regression. Firestore Emulator access/integration suites passed, including concurrent confirmations/collections, payment-vs-close race, cross-session refund, immutable close and invalid device writes. Full lib/test analysis passed; final changed-service/test analysis also passed. Logs are ignored under .remember/tmp/cash-recheck-*.
- No historical customer data was queried or rewritten, no APK built, no accounting functions or rules deployed, and no physical-device/payment/printing acceptance performed in this recheck. Requested the affected shop's account and active device count/platforms before checking actual shop balances and planning coordinated rollout.
- Limits: the server cannot observe unsynced receipts on another disconnected device; synchronize every terminal before closing. A late receipt remains preserved and flagged for reconciliation rather than changing a closed report. Integrity queries fail closed above 10,000 records per checked query; they never silently truncate and claim success. Existing historical gaps require a reviewed migration/compensating-entry plan, not automatic deletion or rewritten closed snapshots. Reporting calendar dates still follow the device timezone; a multi-timezone shop configuration is not implemented.

## Android 1.2.37+54 published — 2026-10-05

- Published the order/accounting fixes and transactional close-integrity checks. Firebase deployment succeeded for 15 functions: confirmOrderPayment, transitionOrder, openCashSession, closeCashSession, collectDebtPayment, getAccountingReview, staffCheckout, offlineSync, createOrderCheckout, stripeWebhook, createRefund, onSaleDeductIngredients, onSaleRefundRestoreIngredients, aiChat and getSalesAnalysis. Conditional Firestore rules deployed successfully before Hosting. Unauthenticated smoke requests to the six new callables returned permission denied without changing shop data.
- Staged activation: each shop keeps legacy-client financial access until the owner opens the first new session and explicitly acknowledges every Android/iOS terminal is updated and synced. Activation is server-owned and cannot be forged by clients. The recorded baseline does not repair earlier gaps; historical paid orders missing sales and old sessions remain review findings. Do not activate while any iOS terminal is still using the previous TestFlight build.
- Automated verification: 96 Flutter tests, 76 backend tests, full lib/test analysis clean, Firestore Emulator access/integration tests passed. Includes duplicate payments, debt races, cross-session refunds, immutable close, payment-versus-close race and legacy-to-activated rule compatibility.
- Signed APK built successfully. Public download verified in full: package app.pokpok.pos, version 1.2.37, build54, 85,252,132 bytes. SHA256 628f4875cda689a69f9c29ef5cc7c837984c4a2ee2f79935447100aaf3a7dec1. Signing certificate SHA256 f7dc70e0464fed06f8c0d14907ef71a75effb566e41e67d1aa685491dff547eb matches the previous release. Download https://pok-pok.app/app/pokpok.apk . Previous APK retained locally as .remember/tmp/pokpok-build53-backup.apk.
- Live manifest and APK verified at 2026-10-04T16:16:39Z. Deployment/build/test evidence is under ignored .remember/tmp/release54-*. No physical-device install-over-existing, real customer payment, printer or historical production-balance acceptance has been performed; matching signature is not a device acceptance result.
- iOS: source/version prepared for master and Codemagic workflow ios-release / iOS Release to TestFlight. Manual start remains required; no API/browser build capability here. No new IPA/TestFlight release claimed. iOS build number is assigned from App Store Connect by the workflow, not assumed to be54.

## Responsive sale product cards — 2026-10-07 (source only)

- User confirmed this concerns products selected before adding to the cart. Added shared SaleProductGrid/SaleProductCard for storefront catalog, restaurant table product picker and offline sales. Phone-sized catalogs use two columns; wider content areas add columns with a maximum card width of200 logical pixels; unusually narrow panes below300 use one column. Layout uses available pane width, independent of side navigation and basket width.
- Replaced the phone storefront horizontal strip and offline full-width product rows with scrolling grids. Restaurant picker no longer fixes every device to three columns. Product images, two-line names, effective prices, promotion labels, full-name tooltips and disabled taps are retained; offline displays the prepared base price and suppresses live promotion pricing. Grid height scales for enlarged text.
- Validation:12 focused Flutter widget/regression tests passed, including320/390/600/800/1280 widths with2x text, tap/scroll behavior, offline prepared price, disabled cards, image fallback, cart actions and restaurant workflows. Targeted Dart analysis clean. Logs: .remember/tmp/product-grid-tests.log and product-grid-analyze.log. No physical-device acceptance, APK build, deployment or TestFlight update performed.
- Earlier table-card sizing edit remains pending alongside these changes. Live release remains1.2.37+54.


## Pickup scheduling and responsive layout — 1.2.38+55 (2026-10-07)

- Customer checkout supports earliest available pickup or a selected interval, for takeaway and ordinary online shop links. Table QR checkout remains dine-in. Owner configuration is in the link/QR ordering screen: enable scheduling, opening/closing time, weekdays, minimum preparation time (5–240 minutes), interval (15/30/60 minutes), and capacity (1–100 orders per interval). Scheduling starts disabled until the owner confirms their actual hours. The horizon is today plus six days, in Asia/Bangkok; this version supports one same-day opening period per chosen weekday, not split/overnight hours.
- The backend generates and validates slots using server time and checks overlap with existing reservations, including after opening time/interval changes. A shop-wide transactional guard prevents parallel reservations exceeding capacity. Pending-payment reservations remain until the shop explicitly cancels them; they do not silently expire while a customer might be transferring. Completed orders still count toward that interval. Queries are bounded at 2,000 records and fail closed when exceeded. Scheduling changes leave existing bookings unchanged.
- Browser checkout requests carry an idempotency UUID tied to their payload; retries in the same checkout reuse the order and original amount. Refresh/relaunch recovery of a pending payment is not part of this change. Legacy clients without a UUID remain supported. Once scheduling is enabled, a stale client must refresh to choose a valid slot.
- Pickup time appears on the payment screen, submission completion page and shop order card. Orders prioritize pending payments, then pickup/creation time. An A5 preparation ticket can be previewed, printed or shared as PDF from Orders; it includes pickup time, item options and notes, and explicitly is not a paid receipt. It uses bundled Thai fonts and the existing system printing/PDF support, not a new Bluetooth printer integration.
- Pickup timestamps are independent from createdAt/paidAt and do not create sales, money movements, cash sessions or shift closing entries. Owner payment verification remains required. No historical orders or accounting data were rewritten.
- Includes the pending responsive product grid changes (phone two-column catalog, tablet card width capped around200 logical pixels, restaurant/offline picker consistency) and tablet table-card sizing (around180 pixels, preserving phone three-column tables).
- Automated validation:99 Flutter tests;81 backend tests; order-page Node regressions; headless Edge fixture flow including pickup payload, mobile320×640 form bounds, payment confirmation display, slip retry and completion display. Full lib/test analysis initially reported two style-only findings, both fixed; changed-file analysis is clean. Firestore Emulator access/accounting suites and new pickup integration passed, including actual concurrent reservations, retry, cancellation, protected reservation control and actual HTTP handler compatibility for old/new clients.
- Physical Android/iOS upgrade, real customer payments, real printer output, and shop historical accounting reconciliation have not been performed. iOS needs a manual Codemagic master / iOS Release to TestFlight build; do not treat a source push as TestFlight availability.
- Publication evidence will be appended after verifying the downloadable APK and hosted assets.


### Publication verified — 1.2.38+55

- Android APK and customer ordering website published to Firebase Hosting. Functions getShopPublic and createPromptPayOrder deployed successfully; final checkout deployment includes compatibility for old clients without requestId. Live unauthenticated endpoint probes returned401 and did not create an order.
- Public download: https://pok-pok.app/app/pokpok.apk . Package app.pokpok.pos, version1.2.38, build55, 85874836 bytes. Full-download SHA256 d8425175d50f152f5f96b4c912d181838364fd205ac208b58dab51d0760609c9. Release certificate SHA256 f7dc70e0464fed06f8c0d14907ef71a75effb566e41e67d1aa685491dff547eb matches build54. This confirms signature continuity, not physical-device upgrade acceptance.
- Verified at 2026-10-06T14:12:17.635Z; all12 ordering HTML/CSS/module assets matched local hashes and returned no-cache. The previous APK is preserved locally at .remember/tmp/pokpok-build54-backup.apk. Evidence/logs: .remember/tmp/release55-* (private, ignored).
- No production shop's scheduling was enabled or hours changed. Owners must update their shop devices, then enable and configure pickup in the link/QR ordering screen. Existing orders remain unchanged.
- iOS source version1.2.38 is prepared for master. Manual Codemagic New build → master → iOS Release to TestFlight remains necessary. Codemagic assigns its next iOS build number; Android55 is not a claim about the iOS build. TestFlight processing/review and actual device tests are still outstanding.

## Exploratory user-journey audit — 2026-10-09, source 1.2.38+55

Requested scope: act through ordinary owner, staff and customer tasks and find defects. This audit does not certify that every feature works. No production shop records, actual payments, product implementation, version numbers or deployments were changed. The `audit56-*` evidence prefix is a local audit identifier, not a release/build number.

### Reproduced findings

Priorities: P1 = address before expanding the pilot; P2 = next usability/correctness batch. These are findings, not fixes.

| ID | Priority | User journey / actual result | Required behavior |
| --- | --- | --- | --- |
| UX-02 | P1 | Create online QR order, then refresh before uploading the slip. Payment screen disappears, cart is empty and the original pending order has no recovery entry. Reproduced in local browser. | Persist a secure reference and offer “ดำเนินการชำระ/ส่งสลิปต่อ” for the existing order. Re-fetch its authoritative status; do not create a new order or ask for another transfer. |
| UX-01 | P1 | Press “ยกเลิกออเดอร์” on the QR screen and confirm. No cancellation request is sent; only the overlay and in-memory pending reference are cleared. Backend pickup tests separately confirm that pending reservations continue consuming capacity until explicitly cancelled. | Distinguish closing the payment screen from cancelling an unpaid order. Implement an authorized, race-safe server transition that reconciles payment/slip state and releases capacity only after a confirmed cancellation. Do not delete a potentially paid order. |
| DATA-01 | P1 | With one stock unit, two separate customers both receive payable QR orders. After both simulated receipts are confirmed in the emulator, stock is **-1**. A direct checkout at stock zero also succeeds. | Check/reserve availability transactionally before requesting payment, with safe release/reconciliation. Keep recording money actually received even when stock is short; suppressing a confirmed sale would corrupt accounting. |
| DATA-03 | P1 for recipe menus | Recipe dish has finished-goods stock zero but ingredient stock available. Actual public-menu handler returns stock zero with no recipe availability. Browser using that response shape disables Add. | Use recipe/ingredient availability consistently instead of treating finished-goods stock as the only availability signal. Revalidate on checkout. |
| DATA-02 | P2 | Create a valid prepaid table QR order, then confirm its simulated payment. Saved sale channel is **takeaway**, even though order type is dineInPrepaid. | Derive the channel from the validated order type; test dine-in and takeaway separately so channel reports are meaningful. |
| UI-04 | P2 | Emulator sale records **50.03** including the order's matching satang; base order total is **50.00**. Source of the paid order card selects the base total, while pending card uses finalAmount. | Display the actual paid amount consistently, with any base-price/matching-satang breakdown labelled. This audit found a display mismatch, not missing money. Card rendering itself was reviewed in source, not on a physical device. |
| UX-03 | P2 | Enter **abc** in customer phone, submit checkout: both browser and actual server handler accept it. | Validate and normalize supported phone formats on both sides with an actionable message; do not reject legitimate international formats accidentally. |

Reproduction code and evidence:

- `scripts/audit_customer_journeys.cjs`: shipped HTML/JS in headless Edge at 375×812, local fixture APIs, external requests blocked. Evidence: `.remember/tmp/audit56-browser-findings.json`, `audit56-cancel.png`, `audit56-payment-reload.png`.
- `functions/audit_order_journeys.cjs`: actual extracted checkout/menu handlers and `confirmOrder` module against isolated Firestore emulator (`demo-pokpok-admin`). App Check is stubbed and modifier-group loading is stubbed; this does not test deployed HTTP middleware, bank verification or production trigger delivery. Evidence: `.remember/tmp/audit56-backend-findings.json`.
- These scripts deliberately assert the current defects. Exit zero means the defects were reproduced, **not** that these journeys passed acceptance. Convert them to desired-behavior regressions when fixing each issue. No real bank transfer occurred.
- Source anchors: `public/order/js/payment.js` (`cancelPay`, in-memory pendingOrder); `functions/index.js` (`createPromptPayOrder`, `getShopPublic`); `functions/order_accounting.js` (`salesChannel`); `lib/screens/orders_screen.dart` (paid amount selection); `public/order/js/catalog.js` (stock-based availability).

### Additional source-review findings requiring device/workflow acceptance

- **UI-05 / P2 — short phone viewport hides product cards.** `lib/screens/pos_screen.dart` includes the catalog only when available content height is at least 580 logical pixels in the narrow layout. Smaller screens, landscape or keyboard/system UI can fall below it. Search remains, but browsing products disappears. Test the complete POS screen at short heights, not only the standalone grid; keep a reachable product browser.
- **FLOW-01 / P1 for shops using the kitchen display — online orders and kitchen queues are separate.** `KitchenScreen` subscribes to open `TableOrder` records. Online `ShopOrder` confirmation/status transitions update the orders/sales collections and do not populate that queue. Online orders have their own status controls and preparation PDF. Decide and clearly expose a unified send-to-kitchen/print workflow; an empty kitchen display must not imply there are no online meals to prepare. No physical kitchen/device run was performed.
- **Staff role scope is narrower than restaurant operations.** `StaffModeScreen` deliberately exposes POS sales/receipt and tells staff the owner manages tables/kitchen. This is an explicit current limitation, not proof of a permission bug. A restaurant pilot needs a decision on cashier/server/kitchen roles before delegating those tasks; keep owner-only financial/configuration privileges protected.

### Validation completed in this audit

| Area | Evidence / result | Scope limit |
| --- | --- | --- |
| Flutter regression | **99 passed**: auth recovery/remembered owner, social buttons/onboarding, staff switching, entitlements, cart/grid, restaurant workflows, receipts, sessions, offline and accounting cases | Automated widget/unit tests; not a full installed-device walkthrough or real Google/Apple sign-in |
| Backend regression | **81 passed** plus escalation script: payments/accounting/refunds, analytics, capabilities, staff, LINE delivery, slips and pickup | Unit/stub coverage; does not establish live provider delivery |
| Firestore access/integration | Passed admin-plan rules, staff access, offline sales, accounting and pickup suites | Isolated emulator: includes concurrent payments/close, immutable summaries and pickup reservations; no historical-shop reconciliation |
| Storage access | Passed owner logo create/update/delete; public read; denial for foreign owner, staff and anonymous writes; image type/size/path limits | Rules-level emulator test, not image selection/compression/upload on a customer's device |
| Existing online-browser journeys | Passed categories/search, responsive grid, required choices, notes, draft restore, kitchen retry, slip PNG compression and same-file retry, pending-review completion | Headless Edge with fixture APIs at mobile and desktop widths; no actual funds moved |
| New exploratory journeys | Reproduced the findings above | Browser fixtures and isolated backend emulator are separate checks, not a production end-to-end transaction |

Logs are private/ignored under `.remember/tmp/audit56-*`; raw Firebase logs may contain sensitive environment metadata and must not be shared. Test success does not erase the newly reproduced gaps.

### Still not tested

- Physical Android/iOS installation/update, OS process termination and remembered login, actual Google/Apple auth, camera/gallery/file picker, slow/mobile network and offline multi-device recovery. No Android device was attached; no iOS simulator is available on this Windows machine.
- Actual Bluetooth/system printer output, bank receipts, deployed App Check/auth behavior, LINE/FCM delivery and a complete real-store closing reconciliation. No customer's historical financial records were read or rewritten.
- End-to-end supplier ordering, subscription purchase/renewal, AI features and every inventory/import/export setting. Existing unit coverage is not a substitute for these journeys.
- User reported Codemagic working again, but the new iOS build's TestFlight availability was not independently confirmed.

Suggested repair order: payment recovery/cancellation → stock and recipe availability → online kitchen handoff → channel/amount consistency → short-screen browsing/contact validation. Then repeat the affected regressions and a real-device pilot from order placement through receipt and day close. No claim of full-app acceptance yet.

## Audit repairs and two kitchen output modes — 2026-10-09 (source only)

Status: implemented locally; no APK/IPA build, version bump, commit, push or deployment in this repair batch. The historical audit above describes the pre-fix behavior. Latest published Android remains 1.2.38+55.

### Implemented repairs

- UX-01 / UX-02: customer QR checkout persists an order request and a random capability before sending it. Refresh and ambiguous network replies recover the same order, original amount and current server status instead of creating another payable order. Cancellation is a server transaction, allowed only for an unpaid pending order without known slip/payment evidence; it releases stock and pickup reservations. Customers must confirm they have not transferred. External money not yet reported to the system cannot be detected by this check.
- DATA-01 / DATA-03: online checkout reserves counted products and recipe/modifier ingredients transactionally, preventing simultaneous customers reserving the last unit twice. Public recipe availability is calculated from ingredients. Updated native POS/table checkout and staff checkout respect online holds; recipe deduction and sale snapshots are atomic and existing deduction triggers skip already-deducted sales. Confirmation preserves actual received money even if a later inventory conflict needs reconciliation. Cancellation/refund paths release or restore the appropriate stock once.
- DATA-02 / UI-04: prepaid table orders record dine-in sales channels; order cards display the actual PromptPay amount, including matching satang, for both pending and paid orders.
- UX-03: phone formats are checked and normalized in the browser and server, including supported international numbers.
- UI-05: short mobile/landscape POS layouts retain a reachable product picker and cart controls. Recipe product cards no longer depend solely on finished-goods stock.
- FLOW-01: kitchen includes paid online orders with preparation notes and pickup times alongside table orders. Unpaid online orders do not enter the preparation queue. Table and online preparation actions continue using their authoritative records without adding another sale.

### Kitchen operation

Open Kitchen, or the kitchen/print shortcut on a table or paid online order, and choose a shop setting:

1. Screen: view preparation tickets and update readiness.
2. Kitchen printer: view the pending print queue, tap print, select a printer through the operating system, then explicitly confirm that the paper arrived. This is manual printing, not background network printing.

Print jobs use server-side claims to prevent simultaneous printing by two devices. New table items can be printed separately; duplicate/recovery printing requires an explicit action and marks the ticket as a reprint. Cancelled/failed printing remains visible for review. Closed/completed orders with unacknowledged tickets remain reachable; closed table items cannot change cooking status. Printing does not create payment, sale or cash movement records.

Current output is a Thai-font 80 mm multipage PDF using the existing system printing service. No direct ESC/POS, Bluetooth or USB driver was added. Actual model/connection compatibility and paper output remain untested; the user's printer model has been requested. A successful OS callback alone is not treated as paper receipt.

### Verification

- Flutter: 106 tests passed, including combined kitchen queues, closed unprinted tickets, small-screen layouts, long Thai kitchen PDFs, and counted/recipe stock reservation guards. Focused kitchen tests and changed-file analysis repeated after final navigation/read-only changes.
- Backend: 82 tests passed plus the existing escalation check.
- Firestore Emulator: admin/staff/offline/accounting/pickup suites and new customer integration passed. New coverage includes reservation races, secure status/cancellation, token isolation, evidence guards, recipe snapshots/deduction/refund, sales channel and kitchen print claim/retry/new-line/permission handling.
- Headless Edge: existing customer ordering fixtures passed; new recovery fixtures passed invalid-phone rejection, refresh recovery, server cancellation, lost-response same-order retry, and review/paid screens hiding transfer instructions. Fixtures do not establish real bank or deployed provider behavior.
- Changed Dart files analyze cleanly; git diff whitespace check passed. Private evidence is under .remember/tmp/fix-audit-*. Raw Firebase logs must not be shared. Historical audit reproduction scripts remain explicitly labelled as expected-defect evidence, not release gates.

### Release and acceptance still required

Deploy compatible backend/rules before updated Hosting and native clients. New endpoints: customerOrder, claimKitchenPrint, finishKitchenPrint. Changed handlers include getShopPublic, createPromptPayOrder, verifyPromptPaySlip, confirmOrderPayment, transitionOrder and staffCheckout. Publish the new customerOrder Hosting rewrite, ordering assets, additive Firestore access rules and a new native build together. Existing ingredient triggers already honor the ingredientsDeducted marker.

Recovery uses the same browser's saved capability. Cleared storage, another device, or old orders created before this capability require owner assistance. Legacy checkout requests remain compatible; the current customer UI uses PromptPay, and unused legacy Stripe checkout is not a newly redesigned recovery flow.

Pending reservations do not expire silently while a customer may have transferred. Update all terminals: older clients and offline sales may consume stock without seeing these new online holds and need reconciliation. Previously received money must not be discarded to fix a stock conflict. No historical production financial records were rewritten.

Staff remains deliberately restricted to its existing POS scope; no new table/kitchen privileges were granted. Physical Android/iOS upgrade, real sign-in, actual bank/slip services, printer output and a full real-store order-to-day-close acceptance remain outstanding. These local automated results are not full-app or hardware certification.

### Publication verified — Android 1.2.39+56 (2026-10-09)

- User authorized publishing this complete repair batch. Signed release APK built successfully, then package/version/signature checked before replacing the hosted APK. Package app.pokpok.pos, version 1.2.39, build 56, 85,989,696 bytes. Certificate SHA256 f7dc70e0464fed06f8c0d14907ef71a75effb566e41e67d1aa685491dff547eb matches build55.
- Deployed Firestore rules and 10 functions successfully before Hosting: customerOrder, claimKitchenPrint, finishKitchenPrint, getShopPublic, createPromptPayOrder, verifyPromptPaySlip, confirmOrderPayment, transitionOrder, staffCheckout and stripeWebhook. The webhook deployment includes the shared confirmation/reservation changes. No shop settings or customer financial records were manually changed.
- Published the customer ordering website, customerOrder rewrite, APK and version manifest to Firebase Hosting. Full public download https://pok-pok.app/app/pokpok.apk verified at 2026-10-08T15:09:43.937Z: SHA256 dc63f8696ec172a3b5a89ec0cbfb80c63cb67684a1810ad29fbb97d4b633198a, byte count and manifest match the built artifact. All 13 ordering assets match local SHA256 and return no-cache.
- Unauthenticated production probes to shopPublic, createPromptPayOrder, customerOrder and verifyPromptPaySlip returned401; both kitchen print callables denied access with403/PERMISSION_DENIED. No smoke probe created an order or print job. These are deployment/access checks, not real bank/customer acceptance.
- Verification reuses the passed repair gates: Flutter106, backend82, Firestore access/integration and browser journeys; final kitchen4 tests and kitchen/orders analysis passed after the last small UI edits. Release logs and verification JSON are private under .remember/tmp/release56-*. Previous APK retained at .remember/tmp/pokpok-build55-backup.apk.
- Android update is optional in the existing manifest (minSupportedBuild1, mandatory false). All shop terminals should update to honor the new stock holds. Matching signature establishes upgrade signing compatibility; no physical install-over-existing or data-retention acceptance was performed here.
- iOS source version is1.2.39. Use Codemagic New build, master, workflow iOS Release to TestFlight; the workflow assigns the next iOS build number from App Store Connect, independently of Android56. Manual build remains required. No new IPA upload, TestFlight availability or Apple review completion is claimed.
- Kitchen selection is available in the Kitchen screen, with shortcuts from table/order details. Actual hardware printing, real payment/sign-in, offline multi-device use and complete real-store closing remain device acceptance items. This release does not add a direct Bluetooth/USB printer driver.

## Compact action buttons — 1.2.40+57 prepared (2026-10-09, source only)

- User requested compact buttons on phone/tablet, with iOS version preparation only. Added CompactAction to release full-width parent constraints, cap actions at360 logical pixels and retain a minimum48 logical-pixel touch area. Primary login/signup/payment actions keep a consistent bounded width; secondary settings actions fit their labels.
- Applied to settings, login/signup, subscription, supplier delivery confirmation, staff form, payment and upgrade sheets. POS pending-payment recovery is bounded. POS basket, table operations, offline checkout, modifier selection, split-bill actions and LINE save/test groups now wrap with spacing instead of distributing excess horizontal width. POS action labels no longer scale down to tiny text to fit fixed ratios.
- Kept existing callbacks, busy/disabled states and financial behavior. Social login already had its360-width limit and remains consistent. This is a targeted layout change, not a global replacement of every button or a change to product/table grids.
- Focused Flutter validation:16 tests passed (new layout tests at320/568/1280 with2x text, tablet settings sizing/taps, plus existing restaurant, cart, onboarding/social and compact-catalog checks). Changed-file Dart analysis and git diff whitespace check passed. No physical-device visual acceptance performed.
- pubspec.yaml is1.2.40+57; iOS Info.plist already uses FLUTTER_BUILD_NAME/FLUTTER_BUILD_NUMBER, so no hardcoded plist version change is needed. Codemagic will assign the next iOS build number when manually started;57 is not a claim about a TestFlight build. No iOS build/upload was started.
- No APK build, Hosting/backend deployment, commit or push in this UI batch. Live download/version manifest remains1.2.39+56. Do not publish the manifest for1.2.40 until its matching APK has been built and staged.

## Security repairs — 2026-10-09 (source only)

Four weaknesses reproduced in isolated tests have been repaired locally. This is not evidence that production was attacked, and it is not a claim that every security risk has been eliminated.

- SEC-01: supplier status changes now require an existing supplier profile, matching actor identity and matching shop/supplier order copies. A crafted supplier-side record cannot make the privileged handler create or overwrite another shop's order.
- SEC-02: referral rewards use a transaction and a server-only referralClaims record. Concurrent requests cannot award twice; owners cannot edit referralCode/referredBy or erase the claim to redeem again. Existing referredBy markers remain respected.
- SEC-03: supplier order rendering escapes stored quantity and other display values. Document IDs no longer enter HTML attributes/selectors; action buttons use DOM text and captured IDs. Product numeric values inserted into HTML are escaped too.
- SEC-04: clients cannot write either marketplace order copy directly. marketplacePlaceOrder reads current catalog prices, availability and minimum quantities; marketplaceShopOrderStatus and supplierSetOrderStatus enforce lifecycle transitions. Both copies update atomically and delivery fees come from saved prices. Native requests persist an idempotency key for retry after an ambiguous response; captured shop identity prevents a switched account submitting the previous shop's cart.

### Verification and remaining limits

- Flutter:110 automated tests passed, including the pending compact-button work. Backend:82 tests passed plus the existing escalation check. Changed marketplace Dart files analyze without issues.
- Full Firestore access/integration suite passed, including the new security regression: unauthenticated/staff/direct-write denial, tenant isolation, invalid quantity and price rejection, legitimate order lifecycle, concurrent replay, cancellation/shipping races, matching copies and one-time referral rewards.
- Headless Edge exercised the actual supplier order renderer with hostile stored fields and document IDs. They remained text, no injected script ran, and legitimate status buttons still invoked their callbacks. External browser requests were blocked; this was not a production supplier session.
- functions/security_audit.integration.cjs is historical pre-fix reproduction evidence, explicitly not a release gate. functions/security_hardening.integration.cjs is the expected-behavior regression gate; scripts/test_supplier_security.cjs checks browser rendering. Private logs are in .remember/tmp/security-fixes-* and must not be published raw.
- Physical Android/iOS upgrades and live marketplace ordering have not been tested. No production customer data was read or rewritten. Existing mismatched/invalid marketplace records fail closed and require administrative reconciliation; this batch does not repair historical records or infer referral rewards whose old marker had already been erased.

### Deployment coupling

Not deployed, built, committed or pushed in this batch. Prepared version remains1.2.40+57; the published Android download remains1.2.39+56. iOS remains version preparation only, as requested.

Deploy new marketplacePlaceOrder/marketplaceShopOrderStatus and updated supplierSetOrderStatus/applyReferral, compatible native clients, Firestore rules and the supplier portal as a coordinated release. Older native clients write marketplace orders directly and will be unable to place/change those orders after these rules are activated; updating only server/rules while leaving customers on old clients is not compatible. Merely changing the iOS version does not update installed TestFlight clients. Prepare the migration/update path before enabling the restrictive rules; do not restore insecure direct writes as a fallback.

## Brand and interface refinement — 2026-10-09 (source only)

User approved the design direction: retain Pokpok's name/logo/wine accent and warm Thai identity, improve readability and consistency across website and app. Implemented a shared visual foundation and applied it to the high-use sales/payment surfaces. This is not a replacement of every screen or a new business workflow.

- Added lib/theme/pokpok_theme.dart and connected both app themes: warm neutral backgrounds, white/dark-neutral cards, wine primary actions, restrained selected states, consistent12px corners, readable secondary text, bundled IBM Plex Sans Thai and minimum48px main button targets. Cards, forms, app bars and navigation inherit the same theme.
- Product cards have larger names/prices, consistent image proportions and neutral unavailable labels. Short catalogs reduce image height so products remain tappable in landscape; long names retain a two-line area. Missing product photos use a neutral, readable placeholder.
- Cart details are visually subordinate to names and totals. Checkout uses a neutral surface and clear top divider; totals/header rows flex with enlarged text. Category strips adapt their height to text scaling. Existing cart, payment, permissions and saved state behavior remain intact.
- Payment sheet is bounded to560px on tablets, respects safe areas and uses wine for confirmation. Method selection has a check icon, and change/shortfall remains explicitly labelled. Fixed large-text overflow in the change row and sales-channel selector. Light-mode change text uses a darker green for readability.
- Dashboard figures use larger dark text on neutral cards, with color reserved for icons/status. Supplier entry is labelled in Thai. Desktop navigation uses a restrained selected background instead of a large solid block.
- Landing page keeps the existing logo/headline, enlarges its app image with a full-size link, aligns palette/button shapes with the app, and adds an accessible shop-example selector plus a four-step daily workflow. Both stories remain readable without JavaScript. Pricing selection and download destinations are unchanged. Customer ordering CSS uses matching palette values without changing ordering/payment logic.

### Verification

- Full Flutter suite:111 passed. Existing catalog/cart/compact-action/navigation/restaurant regression tests now run under the actual new light theme. New payment test covers320/768/1280 widths,1.6x text, light/dark modes, bounded sheet width, cash/change calculation and returned payment result.
- Changed Dart files analyze cleanly. Full suite repeated after layout repairs; payment and visual fixture checks repeated after the final green contrast adjustment. Whitespace check passed.
- Offline headless Edge: landing page at320/390/768/1440 has no horizontal overflow; shop-example and pricing selection, mobile Escape/menu behavior and no-JS fallback passed. Existing customer browser journey passed categories/search, product choices, notes, drafts, kitchen retry and slip recovery fixtures after palette changes.
- Rendered and inspected actual shared Flutter catalog/cart/payment widgets with bundled Thai/icon fonts in light/dark fixture screens. Preview files are private under .remember/tmp/brand-preview; these are component fixtures, not screenshots from an installed customer account. Website previews are renders of the actual local landing page. No real payment or customer data was used.

No build, deployment, commit or push in this design batch. Prepared version remains1.2.40+57 and published Android remains1.2.39+56. Previous security and compact-button changes are preserved. Existing website app screenshots remain from the earlier app version; this batch enlarges them but does not fabricate replacement product screenshots. Capture updated installed-app screens with consistent demo data before replacing those marketing images. Physical-device visual acceptance and iOS build remain outstanding; iOS is still version preparation only per the user's instruction.

## Block daily closing while work remains — 2026-10-09 (source only)

User reported closing was allowed with pending orders and explicitly selected: unfinished work from today or earlier must block closing, except pickups scheduled for a later day.

- Root cause: the former close check counted unpaid orders and open table bills for the saved summary, but only blocked unreviewed payment evidence and financial inconsistencies. A warning after a successful close did not enforce completion of outstanding work.
- The server now checks all pendingPayment/paid/accepted/ready orders and open table bills, including records older than the accounting activation boundary. Unpaid orders, paid but unfinished orders and open tables block the transaction. Archiving a legacy session cannot bypass this operational check. No order is automatically cancelled, marked paid or completed.
- Scheduled pickup from the next calendar day onward, using Thailand time, can carry forward. Invalid/missing pickup times and ASAP orders do not qualify. Unreviewed slip/bank evidence still blocks even for a future pickup. Previously received money remains in its original receipt round; the exception does not defer or erase that money. A futureOrderCount is saved and shown in the close result and Z-report; old summaries default it to zero.
- Added owner-only getCashCloseReadiness and an app check before asking for the drawer count. A scrollable dialog lists up to20 issues, the remaining count, future pickup count and shortcuts to orders/table bills/money review. Failed checks cannot proceed. Local unsynced sales/pending checkout guards run before preflight and final close. closeCashSession independently repeats the server checks inside its transaction, so a previously clear preview cannot authorize a stale close.
- Retrying an already closed session returns its immutable original summary. New work arriving after that completed close does not rewrite the old report. Ordinary completed/cancelled orders do not block; recorded credit sales remain subject to the existing accounting checks rather than requiring all customer debts to be repaid.

Validation:90 backend unit tests passed plus the existing escalation check; the full Firestore emulator integration/rules suite passed, including a real confirmation-versus-close race that leaves the session open until the paid order is completed. Tests cover Thailand midnight, overdue work, future prepaid/unpaid pickups, unreviewed future payments, malformed pickup timestamps, read-only preflight, new orders after preflight, legacy bypass prevention, staff/tenant denial and unchanged snapshots on retries. Full Flutter suite:114 passed, including a320px phone with1.6x text, scrolling the blocker list and navigating to resolve an order. Changed-file analysis and whitespace checks passed.

Not deployed, built, committed or pushed. Publish updated closeCashSession and new getCashCloseReadiness before distributing the client that calls preflight; old clients receive the server refusal only after that server update is deployed. Prior security migration dependencies remain applicable to the broader pending release. Physical multi-device closing and production verification remain outstanding. The server cannot inspect unsynced records still stored only on another offline terminal; every terminal must synchronize before closing. Prepared version remains1.2.40+57; published download remains1.2.39+56.

## Publication verified — 1.2.40+57 (2026-10-09)

User authorized publication of all accumulated fixes. Published the compact buttons, brand/interface refinement, marketplace/referral security repairs and pending-work closing guard described above. The earlier source-only notes are historical; this section records their release.

- Android: https://pok-pok.app/app/pokpok.apk now serves app.pokpok.pos1.2.40 build57,86,088,000 bytes. SHA-256:4c54b4eceaf8a202af2efc7b574c922b81342717400db58749326b6084c0b700. apksigner verified the release certificate SHA-256 f7dc70e0464fed06f8c0d14907ef71a75effb566e41e67d1aa685491dff547eb, matching build56. The prior APK is backed up privately as .remember/tmp/pokpok-build56-backup.apk. No uninstall or customer-data reset is required by this release; physical install-over-existing acceptance is still outstanding.
- Deployed closeCashSession, getCashCloseReadiness, marketplacePlaceOrder, marketplaceShopOrderStatus, supplierSetOrderStatus and applyReferral to asia-southeast1. Published Hosting next, verified the downloadable APK, then deployed the restrictive Firestore rules. All deployment commands completed successfully. No existing customer order or accounting history was rewritten.
- Live verification at2026-10-09T06:35:13.093Z: complete APK download and manifest matched local version, size and SHA-256;16 hosted landing-page, brand, supplier and ordering assets matched local bytes. Added no-cache headers for /app/**; live APK and version manifest returned them. All six changed/new callable endpoints rejected unauthenticated probes with401/403. These probes do not substitute for authenticated real-shop acceptance tests.
- Release validation: Flutter114 tests, backend90 tests plus escalation, full Firestore emulator access/integration suite and changed-file analysis passed. Offline browser checks passed supplier stored-input security, landing-page responsive/accessibility flows and the customer-order journey. APK release build and whitespace checks passed. Private evidence is under .remember/tmp/release57-*; do not publish raw deployment logs.
- Android updates remain optional (mandatory false, minSupportedBuild1), avoiding a global POS lockout. Release notes explicitly require updating before marketplace ordering. Old native apps that write marketplace orders directly can no longer place/change those orders after the security rules activate; read access remains. This applies to old iOS builds too. The compatible Android APK is now available. No insecure legacy-write fallback was deployed.
- iOS: source version1.2.40 is prepared. Per the user's version-only instruction, no Codemagic build or TestFlight upload was started. A manual master / iOS Release to TestFlight build, Apple processing/review and tester installation are needed before iOS users receive these changes or can use the updated marketplace flow. Codemagic assigns the next iOS build number independently;57 refers to Android only.
- Remaining device acceptance: actual Android update/data retention, authenticated owner/staff journeys, multi-terminal offline synchronization and daily closing, physical printers and iOS appearance/sign-in. Other offline terminals still need to synchronize before closing. Website product screenshots remain from the earlier installed app version as disclosed above.

## Product management list/photo switch — 2026-10-09 (source only)

- User reported retail Products still used full-width rows without photos. This was the separate product-management screen, not the recently updated sales picker.
- Added a labelled รายการ / รูปภาพ segmented control below search. List remains the initial view; either choice is remembered locally per shop. List rows now use ProductImage thumbnails; photo mode reuses the compact SaleProductGrid/SaleProductCard, with two columns on phones and bounded card width on tablets. Products without an available image retain the existing placeholder.
- Search, barcode matching and category remain selected while switching views. Edit-product navigation, promotion prices, stock counts and entitlement-gated receive-stock actions remain available. Added optional card footers without changing existing sales picker defaults. Stable product/shop subscriptions avoid reconnecting on each search or view toggle; shared shop subscription also supports staff streams.
- Six focused Flutter tests passed: retained filters and callbacks, persisted/per-shop view choice,320px phone,568px landscape and1280px tablet with2x text, Solo action restrictions, existing sale/compact catalog and payment regressions. Changed-file analysis and whitespace checks passed. No physical device verification.
- Not built, published, committed or pushed in this batch. Live release remains1.2.40+57. The earlier restaurant dine-in/takeaway discussion was a recommendation; this batch changes product presentation only.

## Publication verified — 1.2.41+58 (2026-10-09)

- User authorized publishing the product-management list/photo switch. Android app.pokpok.pos1.2.41 build58 is available at https://pok-pok.app/app/pokpok.apk. Open สินค้า and use รายการ / รูปภาพ below search; the selected view is saved per shop on the device. List thumbnails, photo cards, filters and stock/edit actions are included.
- Release APK:86,088,096 bytes, SHA-256135c182bf49e8945fa874f71e0106b70cf674ae52ec4eb81da1cad736d11b658. Package/version checked with aapt; apksigner verified the same release certificate as build57 (SHA-256f7dc70e0464fed06f8c0d14907ef71a75effb566e41e67d1aa685491dff547eb). Previous APK preserved privately in .remember/tmp/pokpok-build57-backup.apk.
- Firebase Hosting deployment succeeded. Downloaded the complete published APK and verified byte count/hash against both the built and staged files. Published manifest matches1.2.41+58 and both download/manifest return no-cache. Optional-update policy remains unchanged. Evidence: .remember/tmp/release58-verified.json and private release58 logs.
- Six relevant Flutter tests, changed-file analysis and whitespace checks passed before release; release build succeeded. No backend or rules changes in this release. No physical-device install-over-existing/data-retention test was performed.
- iOS source version1.2.41 is prepared for master. No Codemagic build or TestFlight upload was started, respecting the version-only instruction; manual master / iOS Release to TestFlight and Apple processing remain needed.58 is the Android build number, not a TestFlight build number. The existing requirement to update old native clients for marketplace ordering remains.

## Compact phone navigation and retail checkout — 2026-10-10 (source only)

- User reported that bottom navigation and net-total controls occupy too much of the retail sales screen on iPhone. NavigationBar was reserving top safe-area padding despite being at the bottom, and both the page checkout and navigation reserved the bottom home-indicator inset.
- Phone navigation now uses64px content height instead of80px, removes its unnecessary top inset, and owns the bottom inset once. Pages above it no longer reserve that same bottom space. Sidebar layouts retain their existing safe-area behavior and stable page keys.
- Extracted PosCheckoutPanel with a compact narrow-layout presentation: net total beside the payment button; discount and credit under the labelled overflow menu; subtotal/discount details appear when a discount exists. Small widths, enlarged text and large totals can use multiple rows. Payment retains a minimum48px height. Staff cannot access discount/credit actions, and empty carts cannot check out or sell on credit. Wide checkout retains explicit actions.
- Verification: all119 Flutter tests passed, including nine focused navigation/catalog/checkout cases. Simulated390x844 iPhone with47px top and34px bottom insets gives98px navigation overall and checkout within80px without discount. Tests cover320/375/430 widths,2x text, large amounts, safe bottom placement, callbacks, staff/empty restrictions and cart preservation across rotation. Changed-file Dart analysis passed.
- Source changes only: not built, published, committed or pushed. Version remains1.2.41+58. These are widget tests, not physical iPhone acceptance; a future TestFlight build and device check are still needed.

## Publication verified — 1.2.42+59 (2026-10-10)

- User authorized publication of the compact phone navigation/retail checkout changes above. Android app.pokpok.pos1.2.42 build59 is available at https://pok-pok.app/app/pokpok.apk. This applies to Android phone layouts as well as the prepared iOS source.
- Release APK:86,333,856 bytes; SHA-25622c79fe8319829b9f9155fbea84f0224156273e02e86b9f1a6c9e5018e550eb7. aapt verified package/version; apksigner verified the release certificate matches build58 (SHA-256f7dc70e0464fed06f8c0d14907ef71a75effb566e41e67d1aa685491dff547eb). Prior hosted APK is backed up privately as .remember/tmp/pokpok-build58-backup.apk.
- Firebase Hosting deployment succeeded. Full live APK download, staged APK, built APK and version manifest matched byte count/SHA-256 at2026-10-09T14:17:48.531Z (2026-10-10 Sydney). Manifest and download returned no-cache headers. Updates remain optional; no backend, rules or customer records were changed.
- Validation: all119 Flutter tests passed before version bump, changed-file Dart analysis and whitespace check passed; release APK build succeeded. Physical Android upgrade/data retention and iPhone appearance remain unverified. Private evidence: .remember/tmp/release59-verified.json and release59 logs.
- iOS source version1.2.42 is prepared for master. No Codemagic build or TestFlight upload was started, respecting the version-only instruction. Manual master / iOS Release to TestFlight build and Apple processing are still required.59 is the Android build number; Codemagic assigns the next iOS number independently.
