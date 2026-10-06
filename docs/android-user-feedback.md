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
