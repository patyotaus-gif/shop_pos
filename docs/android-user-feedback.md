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
- Validation: 78 Flutter tests, 35 backend tests, Dart analyze clean, Node syntax checks passed. Android release and limited backend deployment are in progress; update the release record only after live verification.

## Device/release acceptance still required

1. Validate on real Android and iOS: open table, add, change quantities, send to kitchen, mark ready, collect payment, view/print/share receipt. Include a second device editing the same table, failed writes, and reopening the app.
2. Verify OS save dialog and real printers on Android/iOS. Automated widget tests do not establish hardware compatibility.
3. Build/upload iOS through the configured Codemagic workflow and select the new TestFlight build. No Codemagic credentials are present in this Windows session.

The server-side logo rule correction was deployed earlier; actual tester retry is unconfirmed. Actual-weight procurement settlement and partial receiving are future product work, outside these screenshot fixes.
