# Pokpok handoff log

Shared handoff between AI assistants (Claude, Codex, or any other) and the owner.
Read this file before starting work. Update it after every meaningful step:
a commit, a deploy, a release, a device test, a decision, or when stopping.

Rules:
- Newest entry at the top of **Log**. Keep **Current state** true at all times.
- Write facts: what changed, how it was verified (local / emulator / device),
  what is deployed, what is still pending. Say plainly what was not verified.
- No credentials, signing keys, tokens, or customer personal data.
- Commit this file together with the work it describes.

---

## Current state (updated 2026-11-14)

**Omise confirmation correction (backend deployed; tablet testing passed):**
Owner authorized release and testing. Source `d262183` deployed on 2026-11-14
05:26 UTC to the three sandbox functions only: create `00008-vit`, status
`00008-pos`, webhook `00007-men`. All are ACTIVE; secret version 3 and instance
limits unchanged. Downloaded all three deployed source archives; five reviewed
runtime/package files match local SHA-256 hashes for each function.
27 focused tests and mocked browser checks passed again, and fresh read-only
Codex review of `55d187e..d262183` found no findings. On SM-X900 Chrome, isolated
THB 100 TEST journeys passed for card, PromptPay and TrueMoney. TrueMoney failure
remains payment_failed without confirmation. Six repeated webhook requests (two
per successful method) preserve the original confirmation timestamps. Actual
provider webhooks returned HTTP 200; PromptPay confirmed while Chrome was in the
background, before the next status poll. Source and audit are pushed through
`ae9421a`; remote master was read back and matched that commit exactly.
No APK, Hosting or security changes; native app remains 1.2.78 (95).
Native follow-up on the same SM-X900 now passed: takeaway payment sheet ->
founder-only Omise sandbox -> Android Custom Tab -> back to the installed app.
Two new PromptPay THB 100 TEST attempts covered success and failure. The app
automatically showed the matching confirmed/payment_failed result on return;
no manual refresh or new login was needed. Provider webhook deliveries were
HTTP 200. The original one-item THB 80 cart remained unpaid and intact; cancelled
the payment sheet and removed only the temporary cart item, restoring zero.
Native card and TrueMoney follow-up completed on 2026-11-14 at 06:12 UTC.
Four new THB 100 TEST attempts passed: card success, card insufficient funds,
TrueMoney paid and TrueMoney failed. Returning from Custom Tab automatically
displayed each matching native attempt's result without refresh or new login.
Exact-ID backend read-back agrees; both failures have no confirmation timestamp.
Actual provider callbacks returned HTTP 200. The THB 80 POS cart stayed unpaid;
removed only the temporary item and restored zero items and the channel chooser.
All three payment methods now have native Android sandbox success/failure evidence.
iOS, real debits and settling a real POS cart through Omise remain untested.
Native card/TrueMoney evidence is committed and pushed in `af6de8e`; remote
master was read back and matched it exactly, with a clean working tree.
Minor pre-existing sandbox UI follow-up: the previous success label briefly
remains visible while a new attempt is being created. The new attempt correctly
becomes pending; no incorrect backend confirmation was observed.
Credential follow-up: origin now uses a clean HTTPS URL and credential manager;
the previously exposed GitHub token still needs replacement by the owner.

Implementation and earlier local verification:
removed the nonexistent `captured` response requirement from sandbox reconciliation
and the internal future-live evidence verifier. Confirmation requires verified
successful/paid status, no refund/reversal, matching amount/currency/bindings and,
when returned, full captured_amount. Auto-capture configuration is not evidence.
Refund/reversal cannot be undone by stale success. Fixtures now match actual
provider responses. Tests first reproduced 14 failures, then all 27 passed;
Firestore emulator, mocked browser and the three-channel audit reproduction pass.
Read back the four existing THB 100 TEST charges from Omise (16 GETs, no new
charges): card, TrueMoney and PromptPay now confirm through the corrected local
status/webhook handlers; failed card remains payment_failed; duplicate callbacks
retain confirmation time. DB/auth were in-memory fixtures, not deployed endpoints.
Those earlier local checks made no production Firestore writes or deployment.
The subsequent release/device checks above wrote only isolated sandbox attempts,
not real shop orders, stock, sales or live payments. Native Android sandbox
return for all three methods is now verified above; iOS and real debits remain untested.
Live Mode remains unavailable.
See `docs/omise-sandbox-audit-2026-11-14.md`.
Login follow-up: after the owner manually opened and signed into `/payment-test/`,
the SM-X900 screen verified authenticated sandbox access. Tapped only the existing
attempt's status refresh; config/status calls returned HTTP 200 in server logs.
The old PromptPay attempt now reconciles to `expired` / `payment_failed` in both
tablet UI and isolated Firestore data. No new charge or real shop transaction.
The earlier ADB launch/forward rejection was not retried; this follow-up read the
already-open screen and used the observed refresh control. Homepage login remains
the separate `/subscribe/` entry; no package purchase is required for this sandbox.

**Kitchen screenshot correction (published and verified):** source `a1f4fbe`
is pushed; Hosting `427f2873006b59f9` went live 2026-11-13 15:17:39 Sydney. The owner
noticed that the tablet shows two columns while the website image shows one.
The preceding capture used density 540, which reduced logical workspace width
below the app's responsive threshold. A fresh unedited SM-X900 1.2.78 (95)
capture at its normal density 320 shows the two table tickets side by side.
Homepage/restaurant image links now use `kitchen-1.2.78-tablet.png` to avoid
reusing the cached one-column image. Device settings restored; no order state
or shop data changed. Local and live image checks passed two pages x three widths;
18-page/five-width marketing checks and fresh source/visual reviews passed.
All 79 public files match the reviewed upload, with only two HTML files and one
new PNG changed. Four live response hashes match; every full-image link opens.
No app release; APK, backend routes and headers unchanged. Rollback Hosting:
`42e39d68841be565`. Evidence: `D:/pokpok-kitchen-two-columns-20261113/`.

**Earlier website screenshot refresh (kitchen corrected above):** source `920e23b` is pushed;
Hosting `42e39d68841be565` went live 2026-11-13 14:54:12 Sydney. Five fresh SM-X900
captures from installed Android 1.2.78 (95) replace older Sales, Products,
Orders, Overview and Kitchen images across nine pages, including full-size links
and social/structured metadata. All 78 public files match the reviewed upload;
exactly nine HTML files and five PNGs changed. Live checks passed 15 response
hashes, 12 browser states at 390/768/1440 and a full-size image click. Local
18-page / five-width marketing and 9-page / three-width image checks passed;
all images match raw device captures. Fresh visual and source reviews found no
blocking defect. Rollback Hosting: `98a6ffde29a23f7e`. Demo order
removed and absence verified, temporary cart emptied,
device density/fullscreen/S Pen restored. No payment, sale, stock or kitchen
status changed. APK, version manifest, runtime rewrites and headers are unchanged.
See `docs/website-screenshots-2026-11-13.md`.

**Payment keyboard follow-up (source pushed, not in released app):** reproduced
keyboard/search-focus restoration after cancel, route back and confirmation in
six Android/iOS widget cases. Clearing the focused input before opening the
shared payment sheet passes eight exit/focus cases (including swipe dismissal)
and preserves search text/reopening. All 50 focused checkout/cart/workspace
tests and targeted Dart analysis passed. An isolated native SM-X900 fixture also
passed cancel/back dismissal with Samsung's keyboard hidden, search text and
the 220-baht mock cart retained, and amount autofocus working on reopening.
This fix is not in the published APK; installed production app remains 1.2.78 (95).

**Android 1.2.78 (95) release (website superseded above):** source `7c67501` is pushed; Hosting
`98a6ffde29a23f7e` stamps commit `193ef23` and went live 2026-11-13 03:44:40 Sydney.
All 73 public files match the reviewed upload; exactly eight expected paths
changed. Public APK download matches the signed artifact and manifest. Existing
runtime rewrites and download/cache headers verified. Rollback: `cb06af000098f85d`.
Local gates passed: 53 app tests, targeted analysis, 56 pricing states, 18-page /
five-width marketing checks, fresh source/visual/final metadata reviews. Live
browser checks passed 24 pricing states at 390/768/1440 widths and 12 response
hash checks. A subsequent SM-X900 test of installed 1.2.78 (95) passed the sales
chooser/cart/rotation/display and checkout-entry checks, both kitchen layouts,
and 16 live website pricing states in tablet Chrome. Checkout was cancelled;
no completed payment, physical print or iOS/TestFlight test is claimed. Minor
follow-up fixed locally: dismiss the keyboard when cancelling payment; it awaits
the next app release. See `docs/release-1.2.78.md`.

**Website pricing/background refinement published:** homepage
and `/pricing/` use bounded, separate cards with darker/larger feature text and
explicit Solo/Lite inheritance and user limits (1 / 1 / 3). Prices and entitlements
are unchanged. Pale rose mortar curves frame the real app screenshot and a rose
band sits behind white pricing cards. A short one-time device entrance respects
reduced motion. Scoped component audit: 18/20; see `docs/website-pricing-2026-11-13.md`.

**Sales-screen simplification released in 1.2.78:** restaurant
owner/staff Sales starts with dine-in / takeaway, keeping visited workflow/cart
state. Display settings, favorites, bundles, offline access and secondary bill
actions are reorganized. Payment/recovery warnings remain prominent. All 70
focused tests passed, with 18 affected tests rerun after the final refinement;
targeted analysis passed. Fresh source review is clean; visual review found no
hard stop, with optional layout polish documented in `docs/ui-layout.md`.
The release reran 53 relevant tests, built and published Android. Subsequent
SM-X900 owner-mode acceptance covered channel switching, cart retention, display
settings, portrait/landscape and cash/change entry. Staff, offline recovery,
scanner hardware and completed checkout remain outside that device pass.

**Previous Android 1.2.77 (94) release:** sales-display and kitchen-width changes
were published in Hosting `cb06af000098f85d` (2026-11-13 00:11:44 Sydney).
All 68 focused tests, targeted analysis, fresh source/metadata reviews and SM-X900
device checks passed. Public APK download matches the signed, tested artifact.
Only APK/version.json changed; all 71 public files verified. Rollback Hosting
`b362e6435d006aad`. No iOS build, physical print, backend or payment/security change.
See `docs/release-1.2.77.md` for evidence and limitations.

**Sales display modes (released in 1.2.77):** owner asked for an optional
name-only sales view with configurable button colors. Added photo/name controls,
category colors and shop-scoped device preferences to POS, table selection and
offline entry. Cart/draft, prices, permissions and backend data are unchanged.
All 34 focused tests and targeted Dart analysis passed. Two visual review rounds
finished clean for the rendered fixtures. SM-X900 checks now also passed for
switching modes, category colors, cart retention and persistence after restart.

**Kitchen width fix (released in 1.2.77):** SM-X900 confirmed that both
kitchen modes stretched a single ticket across the tablet workspace. They now
use up to two columns within 1120 logical pixels, or one centered column with
tickets capped at 600 pixels on smaller workspaces / larger text. History
controls and printer guidance are bounded; action spacing and a table-row tap
hint improve readability. All 34 focused kitchen tests and targeted Dart
analysis passed. See `docs/ui-layout.md`. Both modes now checked on SM-X900 with
1.2.77 (94): two-column tickets, bounded history/guidance and print controls.
Test-shop output mode was temporarily changed and restored to display. No
physical print or saved sale/order/inventory changes were made.

**Website direction fixes pushed and deployed:** all six
approved items from `website-direction-review-2026-11-12.md` are implemented;
see `website-direction-implementation-2026-11-12.md`. Full specifies owner 1 +
staff 2, Retail/Restaurant pages preserve their pricing context, four homepage
feature cards have real screenshots, and Android/iOS setup has illustrated steps.
Source `3fab693` is on GitHub; initially published as Hosting `b362e6435d006aad`
at 2026-11-12 11:49:26 UTC (22:49:26 Sydney), now retained unchanged in the
Android 1.2.77 Hosting release. Website-release rollback was `b7110c9b1acdcfe9`.
Local browser checks passed: 18 pages × 5 widths plus a focused 4-page × 4-width
contrast/target/geometry check. Two newcomer visual rounds completed with no
remaining dead end in the shown flows. SM-X900 app 1.2.76 (93) supplied Products
and Kitchen captures from existing test data. No sales/inventory writes; density,
fullscreen and S Pen settings restored (320, null, 1). Owner authorized push and
update. Independent static review passed; live checks passed 26 response hashes
and 12 page/viewport states, segment pricing and installation-guide navigation.
All 71 public files match Hosting; exactly the 25 reviewed files changed.
APK installation and physical iOS were not retested in this website release.

**Branch:** `master`. Release source `7c67501` is pushed, including sales workspace
`c7bab30` and website pricing `8084306`. Hosting stamps `193ef23` (source plus
preflight records). Android 1.2.78 replaces 1.2.77. Earlier kitchen/display changes
and website direction fixes remain included; final publication records follow.

**Website content direction (recorded 2026-11-12, documentation only):**
Owner supplied `POKPOK.PDF` (14 pages). Source preserved in
`docs/references/pokpok-website-content-standard-2026-11-12.pdf`; its page-referenced
summary is `docs/website-content-standard.md`. Read with the existing visual and
structural core before website work. Example prices, entitlements and service
conditions require factual checks; the new document records the two briefs'
feature-heading and footer differences. This task changes no live website/app.

**Website direction review (2026-11-12, baseline):** the read-only findings in
`docs/website-direction-review-2026-11-12.md` describe the pre-change live site.
The six fixes are now deployed, so that baseline no longer describes production.
See the implementation report for release evidence and remaining limitations.

**Live wording follow-up (2026-11-12):** additional marketing wording from
`Recording 2026-11-12 2222.mp4`: plan feature lists, costs, FAQ and consistent
Thai terminology. Hosting version `06bd0506b99944b0`, released at
2026-11-12 01:04:58 UTC (12:04:58 Sydney). Local checks and live browser checks
passed. Only 16 marketing HTML files and `site.js` changed in Hosting.
See `docs/website-copy-followup-2026-11-12.md` for wording and verification.

**Earlier website copy/cache update (2026-11-12):** `5c68828` and `05540a7`
remain included in the current release. Marketing HTML revalidates on navigation instead
of retaining the old response for one hour. Old cached copies still need one
hard refresh or expiry before receiving this policy.
See `docs/website-copy-2026-11-12.md`. The 2026-11-11 read-only website audit
is recorded below; its performance/accessibility/analytics fixes remain pending.

**Live app (released 2026-11-13):** Android **1.2.77 (build 94)**, served at
`pok-pok.app/app/version.json` (sha256 `045d56ca…d9b6`, 92,403,745 bytes, signed
with the existing release key `f7dc70e0…`). Website screenshots are unchanged.
Hosting rollback: `b362e6435d006aad`. Functions `tablePromotions`, `staffWork`,
`staffCheckout`, `createRefund` remain at their 2026-11-10 deployment;
this release changed no Functions, rules or payment/security settings.

**Test tablet (SM-X900):** installed and verified **1.2.77 (94)** on 2026-11-13.
Kitchen table tickets have no bill shortcut; table billing remains reachable
from Sales > dine-in > table. Fresh website screenshots retain their real capture
version, 1.2.75 (92); they were not refreshed in this Android release.

**App release verification (2026-11-13):** downloaded the live APK and checked its size/hash against
the signed, device-tested artifact; live version.json and 10 sampled unchanged
website HTML/image files match local bytes. Hosting API verifies all 71 public
files and exactly the two intended changes. Source review, focused checks, signed APK
build, installation and metadata review passed. iOS/TestFlight was not built
or triggered; its Codemagic workflow does not run automatically on push.

### Next
- Device-check the features shipped in 1.2.75 on the current tablet build:
  table-bill loyalty and staff bill request
  (now possible with the Functions live), counter points lock on a slow network,
  debt picker phone conflict and "กลับไปรายชื่อ".
- Website (Gif's feedback 2026-11-09), branch `website-gif-2026-11`:
  round 1 merged to master and **deployed 2026-11-10**; refreshed app screenshots
  **deployed and verified 2026-11-11** (see `docs/website-screenshots-2026-11-11.md`).
  Four feature cards with real screenshots, separate `/retail/` and
  `/restaurant/` pages and illustrated setup guides are deployed and verified
  on the live website (2026-11-12, source `3fab693`).
  Real shop photography / a dedicated retail demo image set remain optional work.
- Website direction: owner approved the ten-part brief in
  `docs/website-development-core.md` on 2026-11-11 and supplied the content
  standard on 2026-11-12. Read the core and `docs/website-content-standard.md`
  before website work; they are targets, not claims of completed implementation.

### Review backlog (Low, accepted for 1.2.75)
- **L1** Staff can't unblock a table bill whose redeemed points no longer fit
  (loyalty action is owner-only; staff UI hides the strip). Staff reads also
  include `tablePromotion.loyalty` (customer name/id). Revisit if staff report
  a stuck table or before giving staff loyalty controls.
- **L2** Points discount not itemised in the coupon dialog; payment sheet lumps it
  into ส่วนลด; 1.2.74/staff figures don't add up (totals correct). Revisit when
  the dialog is next changed.
- **L5** จัดเรียง mode can't scroll (cards start a drag at once). Revisit if a
  shop has more tables than fit on one screen.
- **L6** Staff tables tab polls all open table orders every 5 s. Revisit if
  Functions cost or latency rises.
- Round 2 **L-3**: bill-request hints are listened once and not re-subscribed
  after the stream errors (hints can freeze until the screen is rebuilt).
  Revisit if รอชำระเงิน badges are reported stale.
- Round 2 **L-4**: `ensureByName` and the counter POS redemption have no
  automated test (CustomerService uses `FirebaseFirestore.instance`, not the
  `ShopDatabase` test override). Revisit when CustomerService is next changed.
- Round 5 **L-2**: in the debt picker, after going back, editing the phone in
  the search box drops the kept name, and the phone field is never cleared by a
  new search (a new name can be saved with the old phone). Revisit with the
  picker's next change.
- Round 5 **L-4**: ✕ only discards a late attach result; it can't cancel a
  first attach (no ✕ shown) and doesn't release the loading lock early (worst
  case 18 s). Revisit if cashiers report waits.
- Round 6 (subject `e5de43e`, nothing above Low): late counter loyalty messages
  clear other screens' queued SnackBars; the first-attach timeout says
  "ยังไม่ได้เปลี่ยนลูกค้า" when none was attached; the picker "phone never
  becomes the name" holds only if the search isn't edited. Revisit together
  with the loyalty strip's next change.
- Round 3 **L-5** / round 4 test note: the counter POS loyalty lock, timeouts and
  redemption cap have no automated test (same cause as round 2 L-4).
- Pre-existing: if the typed debt phone matches nobody, `ensureByName` falls back
  to an exact name match and drops the phone (same-name customers merge).
- L3 part not fixed: counter redemption maximum ignores bundle discounts;
  checkout still blocks a negative total.

### Known issues and leftovers
- Entitlement gap (found 2026-11-12 by website review, not changed): the product edit
  form opens the stock screen, including "สแกนรับสินค้าเข้า", with no tier check, so
  Solo may scan-receive although the website lists it from Lite.
- **Historical 1.2.74 bug:** refunds started from the sales report did nothing.
  The fix in `0de7903` shipped in 1.2.75; this release does not re-test refunds.
- Test data left in the owner's test shop: loyalty customer `TEST-CLAUDE`
  (0990000001, 0 points) cannot be deleted from the app. Three test sales from
  2026-11-09 are refunded. Loyalty rate was restored to 10 points = ฿1.
- Production `createRefund` was updated on 2026-11-10. Real-device verification
  of returning redeemed points is still pending; do not infer it from deployment.
- 5 Flutter tests already failed on `d29153f` before this work and still fail:
  `online_payment_readiness_test` (2), `product_promotion_service_test` (1),
  `table_promotion_ux_test` (2). Not caused by this branch; not fixed.
- Many Functions still call `db.runTransaction` directly. Only `staff_access.js`
  checkout and `refund.js` were moved to `transaction_retry` after emulator
  evidence; others were not audited.
- Sales report shows "ต้นทุนไม่ครบ" for profit when every bill of the day is
  refunded (pre-existing behaviour, not changed).
- Product "พารา" that existed on 2026-11-05 was missing on 2026-11-09; cause unknown.
- 2026-11-08: the bundled Flutter SDK (`flutter/`) was stuck in a failed `git pull`
  merge; it was aborted back to tag 3.41.7 with the owner's approval.

### Local test setup
- Emulator suites need JDK 21: set `JAVA_HOME` to Android Studio's `jbr`.
- `npm run test:rules` in `functions/` now runs 19 files including
  `table_loyalty.integration.cjs`. `staff_work.integration.cjs` runs separately.
- Website tests need `PLAYWRIGHT_MODULE` and `BROWSER_EXECUTABLE`.

---

## Log

### 2026-11-14 — Complete native card and TrueMoney sandbox testing

- Owner requested testing in the installed app. On SM-X900 1.2.78 (95), opened
  the sandbox from the takeaway payment sheet and used Android Custom Tabs.
- Card TEST success confirmed at 06:00:02.501 UTC; TrueMoney TEST success at
  06:03:58.263 UTC. TrueMoney TEST failure and the official insufficient-funds
  test card stayed failed/payment_failed with no confirmation timestamp.
- All four native screens showed the exact original attempt's result on return,
  without another login or a manual status refresh. Exact-ID read-back verified
  testMode true, THB 100, method, status and confirmation timestamps.
- Actual provider webhook requests for all four outcomes returned HTTP 200.
  Together with the earlier native PromptPay pair, all three channels now have
  success and failure coverage on physical Android. iOS and live debits are untested.
- The original THB 80 cart remained unpaid and intact. Cancelled the payment
  sheet, removed only the temporary item, verified zero items/THB 0 and returned
  to the sales channel chooser. No actual POS sale was submitted.
- Updated `docs/omise-sandbox-audit-2026-11-14.md`; raw captures remain ignored
  local evidence. This pass changes documentation only; no deploy/version bump.
- Committed/pushed evidence as `af6de8e`; remote read-back matched exactly and
  working tree was clean. The follow-up handoff records that completed push.

### 2026-11-14 — Verify Omise from the installed Android app

- Owner asked whether testing had started from the app. Previous three-method
  tablet evidence was Chrome-only; this pass used installed 1.2.78 (95), SM-X900,
  and the already-authorized test shop/founder session.
- Opened takeaway checkout with one temporary THB 80 cart item, then the
  founder-only Omise TEST entry. Its separate THB 100 order opened in a Custom
  Tab using the native attempt ID and existing browser login.
- Generated PromptPay TEST QR, used the provider's TEST-only mark-as-paid API,
  and closed the Custom Tab. Native app automatically showed confirmation;
  server confirmed at 05:50:08.253 UTC; provider webhook HTTP 200.
- Created a second native attempt and simulated failed payment. Native return
  showed payment_failed, with no confirmation timestamp in isolated read-back.
  Provider failure webhook at 05:51:18.989 UTC returned HTTP 200.
- Returned to checkout: original THB 80/quantity-one cart and unpaid state were
  intact. Cancelled checkout, removed only our item, verified zero cart, and
  restored the sales channel chooser. No real sale, stock or live payment write.
- Captures are local ignored evidence under `.remember/tmp/omise-native-*`;
  no account details or test identifiers added to tracked docs. Updated audit
  and handoff for commit; no source changes or new deployment in this pass.
- Card/TrueMoney native-return journeys and iOS remain outside this pass.

### 2026-11-14 — Push Omise release source and device evidence

- Committed release/device evidence as `ae9421a` and pushed all five outgoing
  commits, including fix `d262183`, to origin/master. Read-back matched the full
  local commit SHA; working tree was clean after the push.
- Backend deployment and isolated tablet/provider checks are complete as
  documented below. This final handoff records the verified push; the small
  sandbox UI follow-up and GitHub token replacement remain outstanding.

### 2026-11-14 — Complete deployed Omise tablet and webhook verification

- Source `d262183` is deployed to create `00008-vit`, status `00008-pos` and
  webhook `00007-men`. Downloaded exact-generation source archives for all three;
  runtime/package SHA-256 checks match the reviewed local files.
- SM-X900 Chrome `/payment-test/`: card, PromptPay and TrueMoney each confirmed
  an isolated THB 100 TEST attempt. TrueMoney's provider failure action returned
  payment_failed, with no confirmation timestamp. No real money or shop writes.
- Actual provider webhooks returned HTTP 200. PromptPay confirmed at 05:28:34 UTC
  while Chrome was on Android HOME, before the next foreground status request.
- Replayed each successful charge callback twice; all six returned HTTP 200 and
  retained original confirmation times. Read-only Firestore checks corroborate
  all four final attempt states. Tablet left on the completed failed-test result.
- Local 27-test suite, mocked browser checks and fresh source review passed.
  No APK/Hosting release; native/iOS/real-payment journeys were not exercised.
- Recorded the transient stale-success-label issue in the sandbox UI as a
  separate follow-up. Audit updated; source and evidence are ready for Git push.

### 2026-11-14 — Omise sandbox correction deployed; tablet tests started

- Owner requested release and testing. Deployed only create/status/webhook from
  `d262183`; all three report ACTIVE at 05:26 UTC. Secret version and limits
  unchanged; no app/Hosting/Live Mode/App Check changes. Prior revisions and
  source archive saved locally for rollback.
- Fresh Codex read-only review of four outgoing commits found no findings.
  Focused 27-test suite and mocked browser regression rerun passed (exit 0).
- First actual SM-X900 Chrome card journey returned successful/confirmed at
  05:27 UTC. Hosted form used only provider test card data; declined browser's
  offer to save that card. PromptPay/TrueMoney and real webhook checks ongoing.
- Credential incident: an existing token-bearing Git remote URL was exposed by
  a status command. Removed credentials from the URL and stored via configured
  credential manager. Owner notified to replace the exposed token; rotation is
  not verified. No secret value recorded here. Outgoing-ref secret check passed.


### 2026-11-14 — Correct Omise paid-charge confirmation locally

- Owner authorized fixing the sandbox issue. Updated sandbox and internal
  future-live verification to use documented successful/paid evidence instead of
  the absent captured flag, retaining mode/account/order/instrument/amount guards.
- Do not interpret capture=true as paid. Missing/invalid refund evidence and
  explicitly incomplete captured amounts cannot confirm. Verified refunds and
  reversals cancel the test order; delayed success cannot reconfirm it.
- Replaced invented provider fixtures in unit/emulator tests. Red run: 14 of 27
  failed on old code; green run: all 27 pass. Added actual-shaped all-channel
  webhook/polling, refund/reversal and duplicate timestamp checks.
- Actual provider read-back at 05:11 UTC: four existing TEST charges, 16 GETs,
  zero new charges; local handlers confirm all three paid methods and retain the
  failed-card result. Duplicate callbacks keep confirmation time. In-memory
  database/auth only; no production collection writes or real transactions.
- Firestore emulator passes concurrency/isolation/client-denial checks (Java 21;
  transaction-contention retries completed). Mocked mobile/tablet browser suite
  and the original three-case provider-contract reproduction also pass.
- No app version bump, push or deployment. Device success and real webhook delivery
  remain release follow-ups; tablet access/expired reconciliation were verified
  earlier. Updated audit report. Scoped source/docs commit only.

### 2026-11-14 — Verify authenticated sandbox access on the tablet

- Owner reported login complete. Read the already-open SM-X900 Chrome page at
  `/payment-test/`; authenticated account controls and the old THB 100 expired
  attempt are visible. No navigation/port-forward workaround was used.
- Tapped the observed **ตรวจสถานะล่าสุด** button only. UI remains `expired`,
  with the new-attempt action available. Server logs corroborate config/status
  HTTP 200 and the refresh POST at 04:44:52 UTC; Firestore's isolated old attempt
  is now `expired` / `payment_failed`. Foreground expiry reconciliation works.
- No new charge, real sale, stock change, code fix or deployment. Success predicate
  bug remains pending; this proves authenticated access/status refresh, not a
  successful end-to-end payment. Updated the audit with the device evidence.

### 2026-11-14 — Check reported Subscribe navigation during sandbox login

- Live signed-out Edge reproduced homepage login opening `/subscribe/`; direct
  `/payment-test/` remained on sandbox login with Google available. Sandbox HTML
  and JS match source; slashless route canonicalizes correctly. Check exited 0.
- Sandbox source has no Subscribe redirect; owner's exact tablet click and
  authenticated flow remain unobserved. Explained the separate login entry and
  directed the owner to `/payment-test/`. No code, payment or deployment change.

### 2026-11-14 — Audit Omise Test Mode with actual provider responses

- Requested inspection only; recorded findings without changing application or
  backend code, payment mode, App Check, real orders or stock.
- Existing 24 Node tests, mocked browser flow, Java 21 Firestore integration and
  20 Flutter payment widget tests passed with exit 0. Initial emulator startup
  with Java 17 failed; corrected PATH to the existing JBR 21 and reran successfully.
- Used actual Omise Test Mode keys to create four THB 100 charges with isolated
  in-memory DB/auth. Card, TrueMoney and PromptPay succeeded at the provider;
  insufficient-funds card correctly failed. No production attempt writes or
  real financial movement. Test history retains these four charges.
- Reproduced missing-`captured` schema mismatch in both local polling and webhook
  handling: all three successful payments remain awaiting payment. Three minimal
  provider-shaped assertions exit 1. Passing old fixtures use an invented field.
  Same assumption found in the internal future-live verifier; no live endpoint
  incident is claimed. Fix and provider-shaped regression coverage are pending.
- Read-only deployed checks passed page hashes, signed-out rejection, function
  availability and test-key/channel availability. One old pending attempt is
  expired at Omise; reconciliation needs follow-up. Deployed backend byte identity
  and authenticated webhook/polling end-to-end were not established.
- Automatic approval review blocked the ADB launch/forward command, stating only
  `blocked by policy`; no workaround attempted. No physical tablet payment result
  claimed. Detailed scope, evidence and next steps are in
  `docs/omise-sandbox-audit-2026-11-14.md`.

### 2026-11-13 — Publish native two-column kitchen screenshot

- Owner reported two columns on their tablet versus one in the website image.
  Confirmed the earlier density-540 capture reduced logical width and triggered
  the app's one-column layout. It was not an old app build or website CSS reflow.
- Captured installed SM-X900 1.2.78 (95) at its normal density 320. Raw PNG is
  byte-identical to the published asset; UI hierarchy confirms the two table
  tickets occupy the same row without overlap. Restored device settings and
  changed no order, sale, stock or shop data.
- Updated homepage/restaurant image and full-size links to a fresh filename.
  Kept the old image available for cached HTML. Source `a1f4fbe` was committed,
  pushed and remote-verified before publication.
- Local: image checks passed both pages at 390/768/1440; marketing gate passed
  18 pages at five widths. Fresh visual and isolated source reviews found no
  blocking defect. Mobile image text remains small; full-size links work.
- Deployed Hosting only: `427f2873006b59f9`, 15:17:39 Sydney. Postflight verified
  all 79 public files, exactly three expected changed paths and unchanged
  runtime routes/cache headers. Live body hashes passed four URLs; browser
  checks passed all six image states and enlargement links. Visually checked
  the live homepage image. These browser checks used simulated viewport sizes;
  the underlying screenshot came from the physical tablet.
- APK/version manifest remain 1.2.78 (95); no app or backend deployment.
  Rollback: `42e39d68841be565`. Evidence:
  `D:/pokpok-kitchen-two-columns-20261113/`.

### 2026-11-13 — Publish and verify refreshed website screenshots

- Owner still saw 1.2.75 / 1.2.76 on the live homepage. Confirmed that the
  preceding screenshot commit had not been deployed; published its actual files.
- Reran the marketing gate on exact source `920e23b`: 18 pages x five widths
  passed. A fresh isolated read-only Codex CLI review of `193ef23..920e23b`,
  publication guards and relevant callers found no verified introduced defects.
  Codex was the available fallback; Python/Claude/Grok were unavailable. The
  first report was below the required evidence length, so a second fresh review
  completed with a detailed 5,752-character report before acceptance.
- Verified the GitHub push destination, pushed the three pending commits, and
  read back remote HEAD `920e23b`. This also pushes the separate keyboard fix's
  source; it does not release that Flutter change or rebuild the APK.
- Hosting-only deployment completed successfully at 14:54:12 Sydney, version
  `42e39d68841be565`, stamped with full commit `920e23b`. Preflight and postflight
  verified exactly 14 changed paths, all 78 public file hashes, unchanged
  runtime rewrites/cache/download headers and the existing 1.2.78 (95) APK.
- Live `pok-pok.app` verification passed nine page bodies, five new PNGs and
  version.json against local SHA-256, four routes x three viewport widths,
  image decoding/dimensions, no horizontal overflow and hero image enlargement.
  Inspected the live feature-card screenshot with 1.2.78 (95) captions.
- Evidence: `D:/pokpok-website-screens-release-20261113/`; original device
  captures remain in `D:/pokpok-website-screens-20261113/`. Rollback Hosting:
  `98a6ffde29a23f7e`. No new app build, backend, payment or security deployment.

### 2026-11-13 — Refresh website app screenshots from installed 1.2.78

- Owner reported website app images still showed old layouts. Replaced five
  screenshots referenced by nine marketing/guide/blog pages; captions now name
  the actual 1.2.78 (95) build and capture date where a date is displayed.
- Captured original 2960 x 1848 PNGs on SM-X900. Sales shows the simplified
  takeaway workspace and display settings; Products uses the approved pasta
  photos; Kitchen shows the bounded ticket layout. No synthetic UI or numbers.
- Created one unpaid DEMO-001 only in the authorized test shop, removed it with
  guarded cleanup and verified absence. Cart restored to zero items. No payment,
  sale, inventory or kitchen status mutations. Restored density 320, fullscreen
  policy null and S Pen setting 1; returned to the sales-channel chooser.
- Passed 18 pages x 5 widths with the existing marketing browser suite, plus
  9 pages x 3 widths for new image dimensions/aspect/link targets and a real
  click to open the hero image. Raw/copy hashes match for all five assets.
- Fresh newcomer review checked 18 rendered specimens. A sticky-header/focus
  artifact in two automated captures was removed by capturing from scroll zero
  without locator auto-scroll; re-review found no blocking visual issue.
- Committed the nine HTML changes, five images, provenance and this handoff
  together; earlier image files remain available for cached pages.
- Source-only website change; no Hosting deployment, app release or push yet.
  Prior keyboard fix remains a separate local commit awaiting app release.

### 2026-11-13 — Fix and verify payment keyboard focus after tablet feedback

- Owner asked to fix the previous tablet finding. Six new widget regressions
  failed before the fix: cash checkout returns to the focused catalog search,
  reopening the keyboard after cancel, route back or confirmation.
- Unfocus the actual primary input before pushing the shared payment sheet.
  Unfocusing the caller's scope alone did not fix its remembered child focus;
  this candidate was rejected by the regression tests. All six cases now pass.
- All 50 tests in payment_journey, pos_basket_checkout, pos_checkout_panel and
  sales_workspace passed (exit 0); targeted analysis passed (exit 0). Eight new
  Android/iOS widget cases include cancel, route back, swipe and confirmation,
  retaining search text and allowing the amount input to focus on reopening.
- Built and installed a separate `app.pokpok.keyboardtest` native fixture with
  the actual payment sheet and mock cart, without Firebase initialization.
  On SM-X900, typed search then cash 500 for a 220-baht cart (change 280).
  Cancel returned to the intact cart/search with inset 0 and Android reporting
  `mInputShown=false`. Reopening focused the cash amount and showed Samsung's
  numeric keyboard. System Back first hid the keyboard, then closed the sheet;
  search and cart stayed intact and the keyboard remained hidden.
- Removed only the temporary fixture and returned to production app 1.2.78 (95),
  whose package/version stayed unchanged. No shop writes, completed real sale,
  printer or physical iOS test. Widget iOS configuration is not iOS acceptance.
- Evidence: `D:/pokpok-payment-keyboard-20261113/` contains test/analyze/build
  logs and `device/` captures (search, payment, entered, cancelled, reopened,
  back-dismissed). Fix and verification are recorded with this commit; no push,
  version bump, release, deployment, payment mode or security change.

### 2026-11-13 — Test released 1.2.78 on the connected tablet

Owner requested a physical-tablet test. Verified installed Android 1.2.78 (95)
on SM-X900, using the previously authorized test shop and existing owner session.
Sales starts with dine-in/takeaway; a temporary cart survived switching workflows,
photo/name modes, category colour, favourites, search and portrait/landscape.
Two products / three units totalled 220; cash 500 produced change 280. Checkout
opened without an access error, and scrolling reached both buttons above the
software keyboard. Cancelled without recording a sale; removed the temporary cart.
Payment cancellation left the keyboard visible until Back: recorded as minor UX
follow-up, not fixed or released in this test-only task.

Both kitchen output modes showed bounded two-column tickets with usable print
controls. No ticket status or print action was invoked. Restored display mode,
photo/default category colour and original auto-rotation; returned to Products.
USB briefly disconnected during final capture, then reconnected; restoration was
read back from the device. Recent app-process log sample had no fatal/unhandled
Flutter/overflow matches; this is not proof that every path is error-free.

Real tablet Chrome 157 passed 16 pricing states across homepage and `/pricing/`,
both shop types and billing cycles at 1480×750 / 924×1306 CSS viewports, DPR 2.
Prices, annual-average visibility, minimum CTA height, download navigation, images
and horizontal overflow checked; no page errors. Inspected device/browser captures.
Only the test browser tab was closed. No source, deployment, backend security or
payment-mode change. Evidence: `D:/pokpok-release-1.2.78/device/`; scope and limits
are recorded in `docs/release-1.2.78.md`.

### 2026-11-13 — Publish and verify Android 1.2.78 plus website

Pushed `193ef23` and read the same SHA back from GitHub. Explicit Hosting-only
deployment succeeded as `98a6ffde29a23f7e` at 03:44:40 Sydney, stamped with that
commit. Fresh preflight passed inside the deploy path. All 73 public-file hashes,
the exact eight changed paths, runtime rewrites and cache/download headers match.
Twelve public response hashes and the downloaded APK/manifest passed; artifact
SHA256 is `5db45df2aac60b3eed6fadbd98c9aa99e06a8bf1d4b75287100023e60754d951`,
92,469,169 bytes. Live browser checks passed 24 homepage/pricing states across
390/768/1440 widths, both shop types and billing cycles. Rollback Hosting is
`cb06af000098f85d`. ADB rechecked: no connected device. No iOS/TestFlight build,
physical checkout/print, backend, payment or security-enforcement change.
Final publication records are committed/pushed after these checks.

### 2026-11-13 — Commit 1.2.78 and pass Hosting preflight

Release source committed as `7c67501`. Clean-tree Hosting preflight compared the
current deployment `cb06af000098f85d` with the local public tree: exactly eight
expected paths differ (APK/manifest, brand/home/pricing styles, home/pricing HTML,
and shared pricing copy). Existing runtime rewrites are unchanged. All review
and artifact gates passed. Push and explicit publication follow; the deployment
helper will rerun preflight against the exact pushed commit immediately before
upload. No production files have changed yet.

### 2026-11-13 — Release 1.2.78 checks complete; ready to publish

Final metadata review is clean after one deployment-helper finding was fixed:
cached preflight evidence is invalidated, and deploy runs a new synchronous
preflight bound to the commit. A local regression verified failure blocks the
upload despite an older success record; no network/deployment occurred in that
test. Full source and separate visual reviews remain accepted. Metadata, APK
size/hash and version agree. Ready to commit/push and explicitly deploy Hosting;
no iOS build or physical device test is included. See `release-1.2.78.md`.

### 2026-11-13 — Android 1.2.78 (95) built and staged

Signed universal APK is 92,469,169 bytes, SHA256
`5db45df2aac60b3eed6fadbd98c9aa99e06a8bf1d4b75287100023e60754d951`.
Package/version, all three native ABIs and matching 1.2.77 signing certificate
passed. All 406 native inputs still match the reviewed workspace. The first
PowerShell wrapper treated a compiler deprecation warning as a terminating error;
an incremental rebuild captured native stdout/stderr separately and exited 0.
APK and version manifest are staged locally; final metadata review is running.
No production publication yet.

### 2026-11-13 — Combined release checks passed; Android build running

All 53 focused app tests across eight files and targeted analysis of 13 Dart files
passed in the isolated release source copy. The 56-state pricing and 18-page /
five-width marketing gates passed, with motion/overflow/forced-colour checks.
Fresh ephemeral read-only Codex source review covered all outgoing code since
`17fd271` and found no verified blocker; separate screenshot review found no
definite hard blocker. 406 native inputs match the workspace; focused tracked-file
credential/signing scan found no matches. Android release build is still running.
No production deployment or real-device validation yet. Evidence is under
`D:/pokpok-release-1.2.78/`; optional visual follow-ups are in the release record.

### 2026-11-13 — Prepare authorized combined app/website update

Owner requested implementation and release of all pending approved changes.
Added CSS mortar-inspired hero decoration and pale rose pricing background while
retaining the light brand canvas. Pricing gate passed all 56 states; local
1440/768/390 captures and reduced-motion/forced-colour checks passed. Preparing
1.2.78 (95) in an isolated D-drive build because C has limited free space. Fresh
source and screenshot reviews and app/marketing gates are running. Remote has
no divergent commits; four local commits await publication. ADB has no device.
No deployment yet; previous 1.2.77 (94) and Hosting `cb06af000098f85d` remain live.

### 2026-11-13 — Discuss website background treatment (advice only)
- Read the standing website direction and content standard, and compared the
  existing palette/styles with the supplied hero reference. Recommend using
  large mortar-inspired curves near the app image, alternating white/light-grey
  surfaces, pale rose behind white pricing cards, and restrained motion with
  reduced-motion support. Keep body text on clear surfaces and burgundy as accent.
- Proposed starting with hero and pricing; these are recommendations, not an
  approved visual direction. No website edits, tests, push or deployment.

### 2026-11-13 — Refine website pricing comparison (local)
- Owner requested narrower pricing cards, darker text and clearer package
  differences, using the supplied competitor layout as a reference. Updated
  homepage pricing and `/pricing/` with a shared 1,060px comparison, separate
  cards, readable 16px feature text, stronger benefit headings and explicit
  Solo/Lite inheritance. Full retains the existing recommendation treatment.
- Preserved prices, entitlements and destinations. Exposed existing user limits
  for every plan (1 / 1 / 3), verified against the app's entitlement map. Trial
  copy explains selection during app registration; buttons still open download.
- Local checks passed: 56 pricing states across seven widths, both business
  types and billing cycles; 18 marketing pages at five widths. Includes target
  sizes, text contrast, keyboard activation, 200% text, forced colours, pricing
  switches and links. Rendered 1440/768/390px captures inspected.
- Fresh isolated source and screenshot-only reviews led to spacing and copy
  refinements and explicit Solo/Lite user limits. Final source review is clean;
  screenshot walkthrough found no visible P0/P1 blocker. Scoped component audit
  is 18/20; optional mobile comparison/plan-handoff suggestions and evidence
  paths are in `docs/website-pricing-2026-11-13.md`.
- No physical device test, production data changes, push or deployment. Earlier
  unpublished app changes remain separate. Website changes await publication.

### 2026-11-13 — Implement sales channel chooser and simplify POS (local)
- Owner approved the preceding space review, requiring an initial dine-in /
  takeaway choice for restaurant sales. Implemented lazy, retained workflows
  with a return-to-choice action. Retail still opens its catalog directly.
- Consolidated search/categories/favorites into one catalog stream; moved display
  controls into a dialog, bundles into the category row, offline entry into the
  header menu and tablet discount/debt into the bill menu. Kept selected customer,
  payment recovery warning, cart state, total and payment action visible.
- Local verification: 70 focused widget tests and targeted Dart analysis passed.
  Includes real catalog, cart item controls, tables, dialogs and checkout layout
  with fixture data at 320/390/768/1440 widths and normal/200% text. After the
  search-result affordance refinement, 18 affected tests and analysis passed.
- Independent reviews identified staff entry classification, offline access on
  workspace failure, search details/scanner access, and pending category saves
  across rotation. Fixed those, preserving the catalog's state across breakpoints.
  Staff restaurant sales now get the same chooser, with retry and prepared-only
  offline access while the workspace is unavailable. No new offline permission.
- Visual review confirmed scrolling reaches lower prices/stock at enlarged text.
  Replaced placeholder basket rows with real CartItemTile controls in previews;
  forced retained layers to repaint to avoid omitted AppBars in test captures.
  Initial stream-test teardown stall and retry Future-return assertion are fixed.
  Claude reviews were unavailable (usage limit); fresh isolated read-only Codex
  CLI sessions reviewed source and screenshots. Source round 3 found no concrete
  regression; visual round 3 found no hard stop. Entire search result rows are
  tappable, quantity controls retain 48-pixel targets, and the repeated Favorites
  label is a deliberate fixture category. No claim of measured color contrast or
  authenticated/device checkout is made. Evidence: `D:/pokpok-sales-workspace-review/`.
- ADB listed no device. No real checkout, scanner, backend/data/payment changes,
  push or deployment. Live Android remains 1.2.77 (94). See `docs/ui-layout.md`.

### 2026-11-13 — Review clutter in sales screen (advice only)
- Compared current source with 1.2.77 tablet screenshot/XML. Empty takeaway has
  eight pre-catalog levels; first product begins at y=962 on 2960x1848 capture.
- Proposed a compact header, display-settings menu, favorite/bundle category
  tabs, contextual offline warnings and stronger product/cart/total emphasis.
  Preserve cashier identity, loyalty access and payment-recovery warnings.
- Confirmed sidebar collapse/persistence and mobile secondary checkout actions
  already exist. Mobile was inspected through source/component fixtures, not a
  newly connected physical device. No cashier-usage analytics or implementation.
- Recorded findings and pending recommendations in `docs/ui-layout.md`; only
  documentation changed. No tests rerun, data writes, push or deployment.

### 2026-11-13 — Android 1.2.77 (94) published and verified
- Hosting-only deploy from pushed `d8e0ded` completed with exit 0. New version
  `cb06af000098f85d`, released 2026-11-12 13:11:44 UTC (00:11:44 Sydney).
  Rollback `b362e6435d006aad`; changed only APK/version.json. All 71 public paths
  and gzip hashes match local; headers/rewrites and website assets unchanged.
- Downloaded public APK and verified 92,403,745 bytes and SHA-256
  `045d56ca6d6b191be45dc0ae52f0db73bceb7a4af7a69f65db8c0f722266d9b6`.
  Manifest and 10 sampled website files match. SM-X900 already runs this artifact.
- No iOS/TestFlight trigger or physical printing. No Functions/rules/payment/
  security changes. Original signing inputs retained; automatic approval review
  blocked deletion of the local temporary signing copies (policy rejection,
  no specific reason supplied). No retry or workaround attempted; copies remain
  in the local release workspace, outside tracked/public files.

### 2026-11-13 — Release source pushed; Hosting preflight passed
- Committed and pushed `2d1cbce` to master; remote SHA read back matches.
- Hosting preflight confirms current version `b362e6435d006aad` and exactly two
  pending public changes: APK and version manifest. Website bytes and runtime
  rewrites are unchanged. Publication and public-download verification pending.

### 2026-11-13 — Android 1.2.77 device gate passed, ready to publish
- Correct signed APK cold-started successfully, preserving existing shop/login.
  SM-X900 passed photo/name switching, category-only color changes, draft/cart
  retention across switching, and preference persistence after force-stop/restart.
  Temporary cart item removed; photo mode/default color restored.
- Both kitchen display and printer views show bounded two-column tickets and
  usable controls. Switching output mode saves the test-shop preference and
  rebuilds its shell; restored display mode and returned to Sales. No physical
  printing or saved sale/order/inventory mutation was performed.
- Fresh isolated metadata review also passed (Claude Opus 4.6, read-only tools,
  no MCP or denials). Source review and all 68 tests/analysis were already green.
- Restored normal local `build/` directory; the relocated junction/cache and old
  directory remain ignored backups. Release uses the verified clean D-drive
  source build, not the rejected junction build. No publication yet.

### 2026-11-12 — Prepare Android 1.2.77 (94)
- Owner authorized update. Scope: optional name/color sales buttons and bounded
  kitchen display/printer layouts. No payment, backend or security configuration.
- Bumped pubspec version. Build temporary files are being relocated to the
  explicit D-drive release workspace because C has less than 200 MB free.
  A native cross-volume move stopped on a long generated path; Robocopy completed
  the copy (exit 3), then the build directory became a junction to D. The old
  directory remains as a local backup. C regained about 4 GB free space.
- All 68 focused sales/offline/kitchen tests passed; targeted analysis passed.
- First signed build returned success and installed, but device startup crashed:
  APK inspection found all three `libapp.so` missing after build-directory
  relocation. Rejected this artifact (57,997,357 bytes); restored the previous
  public APK/manifest. No defective build was deployed. Building again from an
  isolated clean source on D and adding explicit native-library checks.
- SM-X900 retains its app data. Clean-build UI verification and independent
  review were pending at the failed-build checkpoint. Fresh isolated Claude
  Opus 4.6 review has now completed (exit 0, read-only tools, no MCP or denials):
  no confirmed introduced defect. Root checked its candidates against source
  and the passing test/analyzer runs. Clean source matches all 260 tracked
  native input files, ignoring checkout line endings. No push/deployment yet.
- Clean build completed successfully (exit 0, 504.1 seconds). All three ABIs
  include both libapp.so and libflutter.so; signing certificate matches the
  previous release. Accepted candidate: 92,403,745 bytes, SHA-256
  `045d56ca6d6b191be45dc0ae52f0db73bceb7a4af7a69f65db8c0f722266d9b6`.
  Installed successfully over the rejected local candidate on SM-X900;
  installed package reports 1.2.77 / 94. Device UI checks running.

### 2026-11-12 — Optional name buttons in sales catalogs
- Committed locally as `f1427dc`; no push or release. This documentation update
  records the final commit and verification state for the next session.
- Owner requested switchable image/name-only product buttons and suggestions.
  Implemented photo-default and name-button modes with five soft category colors
  plus reset. Names, prices and availability remain visible in both modes.
- Presentation preferences are local to the shop/device; they do not mutate
  product records or sync other tills. POS/table/offline entry share them;
  inventory-management and customer-facing ordering are unchanged.
- Added focused coverage for persistence/isolation, malformed saved preferences,
  mode changes with an existing draft, price/disabled behavior and layout/contrast.
  First focused run passed 26 tests. A capture-helper hang in FakeAsync was fixed
  by moving image encoding into tester.runAsync; that initial run was interrupted,
  not counted as passed. Final expanded run passed all 34 tests across
  `sale_display_test`, `sale_product_grid_test`, `table_product_picker_test`,
  `product_catalog_test` and `offline_access_test`; targeted Dart analysis passed.
- Visual review round 1 identified weak completion/selection/unavailable cues.
  Added a filled completion button, selected-table-item check/border and an
  unavailable icon. Round 2 was clean for the four inspected fixtures. Layouts
  cover 320/390/768/1440 widths, light/dark themes and 200% text. These are local
  widget fixtures, not installed-app checkout or physical-device acceptance.
- Evidence: `.remember/tmp/sale-display/` PNGs and
  `D:/pokpok-kitchen-layout-temp/sale-display-final.log`. Tests used D-drive
  TEMP/TMP because C-drive free space is low. No APK, push, deploy or shop write.
- See `docs/ui-layout.md` for the jobs map, design decisions and scope.

### 2026-11-12 — Bound kitchen tickets on tablet workspaces
- Committed local implementation and tests as `c097378`; working tree clean
  after that commit. This handoff records its local-only status for the next
  explicitly requested app release.
- Owner asked why kitchen display and kitchen-printer mode stretch across the
  screen. Read-only capture of connected SM-X900 confirmed the defect; source
  shared one unconstrained ListView between both modes. Standalone Bluetooth
  settings already have a 760-pixel cap and did not need modification.
- Added responsive bounded ticket groups for active, ready, future and history
  work, preserving chronological order, natural heights, notes and keyed ticket
  identity within each group. Large text and narrow remaining workspace use one
  column. Printer controls wrap with spacing; history switches stay near their
  labels. Added the visible hint for tapping table-food rows when ready.
- Ran the new regression on the original source: exit 1, ticket width 1224
  exceeded the 600-pixel limit at a 1440 viewport with a 192-pixel navigation
  allowance. After correction, 34 kitchen tests passed with exit 0; targeted
  Dart analysis exited 0 with no issues. Initial harness runs required the exact
  displayed order label and hit-testable scroll targets; one run also exhausted
  C-drive temporary space. Final tests used isolated D-drive TEMP/TMP and passed.
- Captured 12 fixture screens at 390/768/1440 in both modes and themes under
  `.remember/tmp/kitchen-layout/`. Visual review found adjacent print/progress
  buttons and an over-wide history switch; both were corrected. A second fresh-
  viewer walkthrough found no remaining layout obstacle in the shown screens.
  Existing combined "พร้อมรับ / เสิร์ฟแล้ว" copy is a minor follow-up suggestion,
  outside this width fix. Future/history access and scrolling passed widget
  tests separately from the static visual review. These are local
  widget captures, not screenshots of an updated installed APK.
- No backend, payment, permission, printer transport or paper-width changes.
  No order/settings mutations on the tablet, installation, push or deployment.

### 2026-11-12 — Push and publish website direction fixes
- Owner explicitly requested push and update after the local implementation.
  Pushed source `3fab693` to `patyotaus-gif/shop_pos` master and verified the
  remote SHA. No force push, app build, Codemagic trigger or backend deployment.
- Fresh isolated Claude Opus 4.6 review of `5714a72..3fab693` completed clean:
  read-only Read/Grep/Glob, no MCP, hooks, project settings, saved session or
  auto-memory; 6,457-character report, no permission denials. Binary images and
  rendered behavior were verified separately by local/live browser checks.
- Re-ran 18 marketing pages × 5 widths, the 48-URL cache-policy test and its
  real-browser stale-cache fixture; all passed. JavaScript syntax and outgoing
  ref check for private-key/payment/GitHub token patterns passed.
- Hosting-only deployment `b362e6435d006aad` released at 11:49:26 UTC
  (22:49:26 Sydney), stamped with full source SHA. Previous version
  `b7110c9b1acdcfe9` retained as rollback.
- Hosting API readback confirms all 71 local public files, exactly 25 changed
  paths, expected headers and unchanged runtime rewrites. Public HTTP checks
  confirm 26 response hashes (including unchanged app version.json). Live Edge
  checks passed 4 pages × 3 widths, images, menu/Escape, guide steps and segment
  pricing/monthly/yearly navigation. Inspected the resulting live captures.
- Two initial probe failures were investigated: subscribe was incorrectly
  expected to use marketing no-cache headers; an immediate annual-price check
  still read monthly values. Isolated navigation/click tracing passed without a
  second click or page error. The final smoke explicitly waits for page/fonts
  and the resulting price state; it passed. No website-source fix was needed.
- Evidence: `D:/pokpok-direction-release-20261112/` (review, deployment log,
  Hosting/HTTP readback, pricing trace and live browser captures). The report
  `website-direction-implementation-2026-11-12.md` records public release status.
  Android remains 1.2.76 (93); Functions, rules and payment/security settings
  were unchanged. No physical device installation test in this release.

### 2026-11-12 — Implement six website direction fixes and capture tablet screens

- Scope: website copy, two business landing pages, four homepage screenshot
  cards, illustrated APK/TestFlight setup, footer links, sitemap and cache keys.
  Full user wording matches owner 1 + staff 2; prices and actual entitlements
  unchanged. Signup page edits are limited to those two plan descriptions.
- Device: connected SM-X900, app 1.2.76 (93), existing test-shop Products and
  Kitchen views. Added `inventory-1.2.76.png` and `kitchen-1.2.76.png`.
  Existing 1.2.75 Sales/Reports remain accurately labelled. No record writes.
  Restored density 320, no policy_control override and air_button_onoff 1.
- Verification: `scripts/test_marketing_pages.cjs` passed 18 pages × 5 widths,
  local links/assets/anchors, menu/Escape, segment-to-pricing, billing, guide
  search, FAQ and no-JS content. Focused visual measurements passed at four
  widths; minimum measured text contrast 5.08:1, changed control height 48px.
  Newcomer feedback fixed signup guidance, iOS button order and plan/account
  clarity; second review found no visible dead end. Syntax/diff checks passed.
- Design evidence and limitations: `website-direction-implementation-2026-11-12.md`.
  Retail uses food products from the test shop with an explicit caption.
  No screen-reader, real-network CWV or physical iOS installation claim.
- This work is a local commit only. No push, Hosting deployment, app release,
  Functions/payment/security change or real sale was performed.

### 2026-11-12 — Review live website against both owner briefs

- Owner asked which website changes remain under the saved direction. Reviewed
  the core and PDF content standard against current source and fresh live pages;
  recorded findings in `docs/website-direction-review-2026-11-12.md`.
- Confirmed an actionable entitlement-copy mismatch: Full advertises three staff
  accounts, while `StaffScreen` and `staff_access.js` allow two staff plus owner.
  No entitlement or website code was changed in this review.
- Confirmed four homepage feature cards exist, without task screenshots; Retail
  and Restaurant remain toggled stories rather than separate landing pages.
  Also recorded terminology, illustrated installation, footer FAQ and sitemap gaps.
- Verification: five live pages HTTP 200 with HTML matching local bytes at
  `facfe51`, 390/1440 viewport checks without horizontal overflow or JS page errors,
  pricing type/year toggles, selected screenshot inspection. `/retail/` and
  `/restaurant/` return 404 (not existing broken navigation links).
- Evidence: `D:/pokpok-website-direction-20261112/audit-live.json` and screenshots.
  Browser viewport simulation only; no real-device, payment, full accessibility
  or PageSpeed test. Documentation diff and AGENTS reachability checks passed.
  Documentation only, no deployment or push.

### 2026-11-12 — Preserve owner's website copywriting and content standard

- Request: record the supplied `POKPOK.PDF` as website development guidance.
- Preserved the unmodified 14-page source in
  `docs/references/pokpok-website-content-standard-2026-11-12.pdf` and summarized
  all 11 content sections with page references in `docs/website-content-standard.md`.
- Linked the standard from `AGENTS.md` and `docs/website-development-core.md`;
  retained the earlier visual/structural brief and explicitly recorded differences
  about English feature headings and three versus four footer groups.
- Distinguished brand/writing rules from proposed copy and unverified product
  claims, including the meaning of three staff accounts, offline behavior,
  data retention, trial length, price and payment availability.
- Verification: extracted and read all 14 pages; copied PDF SHA-256 matches source
  (`d974371ff7e9802927cda5a25bf507ab501891067924864ed66ef040703ff996`).
  Documentation links, instruction reachability from AGENTS, UTF-8 and the
  1,800-word guidance budget passed; `git diff --check` passed. Stored in a local
  documentation commit; no push, runtime code change, deployment or device test.

### 2026-11-12 — Denser desktop homepage published and verified

- **Published:**
  - Master was fast-forwarded to `5714a72` and pushed with the branch.
  - Deployed Firebase Hosting only (`--project shop-pos-89294`). Live version
    `b7110c9b1acdcfe9`, released 2026-11-12 08:12:59 UTC.
  - Rollback: `06bd0506b99944b0`.
  - Three files were uploaded: the homepage, the pricing page and `brand.css`.
  - Before the deploy, the ignored local `public/app/pokpok.apk` was confirmed to
    match the live 1.2.76 APK (sha256 `afb8f92f…a9ad`, 97,532,155 bytes).
- **Live checks:**
  - `/`, `/pricing/` and `brand.css?v=20261112-density` match local bytes.
  - The homepage serves `no-cache`.
  - `version.json` is unchanged.
  - The live CTA visibility check passed at 7 widths.
  - Inspected a live 1440 px capture.
- **Not done:** no app, Functions, rules or payment/security changes; no physical-device
  browser check.
- Owner feedback: the website feels empty ("โล่งๆ") on a computer. Live captures at
  1440/1920 px showed that the three middle sections (features, supplier orders,
  guides) were a heading, a paragraph and a button each, leaving about 60% of the
  width blank. Owner previewed and said "อัพขึ้นเว็บเลย".
- Branch `website-desktop-density` (`2e4259b`, `1d0f930`, plus the round 2 fix commit):
  - `#features` became a heading row plus four feature cards: Sales & Checkout,
    Inventory, Tables & Kitchen, Reports. Each card has an English name (inside its
    h3, `lang="en"`), Thai description, benefit and starting plan.
  - That covers parts 1, 2 and 4 of `docs/website-development-core.md` §4. Part 3 (a
    real screenshot per feature) is still pending; icons stand in for it for now.
  - `#marketplace` and `#how` became two side-by-side cards with numbered steps.
  - The features CTA shows above the cards at 801 px and wider, and below them at
    800 px and narrower; exactly one shows at each width.
  - Section ids are unchanged. CSS was appended to `brand.css`, and the cache key was
    bumped to `20261112-density` on the homepage and pricing page.
- Sources for the claims:
  - Plan tiers come from the `/features/` and pricing copy.
  - The Inventory card's Lite items (low-stock alert, low-stock list, scan-to-receive
    button) come from the app: `product_form_screen.dart`, `dashboard_screen.dart`
    and `products_screen.dart`.
  - Day-close is not tier-gated (`dashboard_screen.dart`).
  - Wording follows `docs/website-copy-followup-2026-11-12.md`.
- Independent review (fresh read-only Claude session, `review.py`):
  - **Round 1** (on `2e4259b`) found two Medium issues, both fixed in `1d0f930`:
    - M1: Inventory was described as "deducts on sale from Lite", but the app deducts
      at every plan.
    - M2: absolute promises such as "ยอดไม่ตกหล่น" and "ครัวเห็นทันที".
  - Round 1 also found five Lows, all fixed: the staff step, "เปิดบิล" terminology,
    the CTA after the cards on phones, `lang`/`role="list"`/the ✓ alt text, and
    this log's §4 wording.
  - **Round 2** (on `1d0f930`) found nothing above Low. Its three Lows were fixed:
    - "ทุกบิล" became "ตรวจรายการขายย้อนหลังได้".
    - The English name moved into the h3.
    - This entry was updated.
- Out of scope, noted by round 2: the product edit form opens the stock screen,
  including "สแกนรับสินค้าเข้า", with no tier check. A Solo shop may be able to
  scan-receive even though the card says Lite. This is an app entitlement gap and
  was not changed.
- Local checks on the final tree:
  - `test_marketing_pages.cjs` PASS (16 pages × 5 widths).
  - The CTA visibility check passed at 320/390/800/801/1024/1440/1920 px.
  - `git diff --check` is clean.
  - Inspected local captures at 390, 1024, 1440 and 1920 px.

### 2026-11-12 — Website wording follow-up published and verified

- Owner requested release. Pushed clean reviewed source `5f12130` to `origin/master`
  and deployed only Firebase Hosting, explicitly targeting `shop-pos-89294`.
- Live version `06bd0506b99944b0`, 2026-11-12 01:04:58 UTC; release message contains
  the source commit. Rollback version: `4f04f89cb357738d`.
- Independently ran `test_marketing_pages.cjs`: PASS, 16 pages × 5 widths.
  Fresh isolated read-only Claude Opus 4.6 review completed (exit 0); triaged only
  Low/cosmetic terminology observations. Rationale and revisit triggers are in
  `docs/website-copy-followup-2026-11-12.md`; no unresolved release-blocking defect.
- Hosting inventory: 69 files including two Firebase-generated `/__/` files;
  exactly 17 reviewed content files changed, no added/removed files. Local gzip
  hashes match all 67 uploaded files. APK, app manifest and other surfaces unchanged.
  First inventory preflight needed adjustment for those generated files, then passed.
- Production HTTP checks: all 17 changed files plus app manifest match local bytes;
  changed HTML and app manifest retain `no-cache`.
- Production browser checks: 48 rendered states across 320/390/1440 px on homepage
  and pricing, retail/restaurant and monthly/yearly switching, FAQ, HTML/JS and
  no-JS consistency, and legacy guide-search synonyms PASS; no JS errors/overflow.
  Inspected all eight live screenshots of prices, costs and FAQ at 390/1440 px.
- Evidence: `D:/pokpok-copy-followup-release-20261112/`. No physical-device test,
  app rebuild, Functions/rules deployment or payment/security configuration change.

### 2026-11-12 — Additional website wording from recorded feedback (local)

- Read the 22.4-second clip as ordered frames. Feedback asks for clearer
  Solo/Lite/Full feature lists, costs and service conditions, FAQ questions and
  contact copy, with a professional, simple and reliable tone.
- Updated plan lists in both HTML and JavaScript, costs/service conditions and
  FAQ. Standardized payment, order, supplier and inventory wording across the
  marketing pages, including navigation/footer. Kept exact app menu names in
  quoted instructions and retained old guide search terms as keywords.
- Privacy/Terms bodies are untouched; only shared chrome/script version changed.
  Prices, trial, entitlements, application/backend/payment configuration are unchanged.
- Local verification: marketing browser suite passed 16 pages at 5 widths
  (320/390/768/1024/1440); additional copy check passed 48 rendered states,
  HTML/JS/no-JS plan agreement, monthly/yearly prices and legacy guide keywords.
  Initial extra check compared UL whitespace and failed; corrected the harness
  to compare individual LI text and reran successfully. No product fix was needed.
- Inspected all eight mobile/desktop plan, costs and FAQ preview captures.
  `git diff --check` passed. Details: `docs/website-copy-followup-2026-11-12.md`.
- Initial tree was clean at `6c964c9`. This entry is committed with the copy work.
  Evidence: `D:/pokpok-copy-followup-20261112/`. No push, deployment, production
  data write, app release or physical-device test in this follow-up.

### 2026-11-12 — Correct stale marketing-page cache (published)

- Owner still saw the previous homepage wording after the copy release.
  Fresh GETs to the custom domain and web.app both returned the new bytes, but
  root, index.html, features and pricing all returned `Cache-Control: max-age=3600`.
  This supports browser caching as the cause; the owner's browser storage itself
  was not inspected.
- Added `no-cache` only to root/index.html and the marketing content directories
  in firebase.json. Shared assets, APK/app manifest, order pages, API rewrites,
  payment settings and application code are unchanged.
- Focused regression: scripts/test_marketing_cache.cjs. Live header check failed
  before deployment at `/` with max-age=3600; local policy check passes 48 URLs.
  Real Edge HTTP-cache fixture reproduces stale content with the old policy and
  receives updated content after navigation with the new policy, without clearing
  cache between the two visits. The fixture is not the Hosting emulator.
- Superstatic 10 on this Windows host converts URL slashes to backslashes in
  header matching, so it was unsuitable for validating these headers. Replaced
  that attempted harness with local glob-policy checks plus a read-only live
  Hosting check; the browser fixture independently verifies browser behavior.
- Existing cached copies cannot receive the new header until fetched again:
  Ctrl+F5 once, a fresh query URL, or expiry is needed for the old cached response.
  Already open tabs are not automatically refreshed.
- Run with MINIMATCH_MODULE pointing to Firebase CLI's minimatch dependency,
  PLAYWRIGHT_MODULE and BROWSER_EXECUTABLE as for the marketing gate; optional
  CACHE_CHECK_URL=https://pok-pok.app validates real headers instead of local ones.
- Fresh isolated Claude CLI review of the git-produced release range passed:
  no material findings, 29 turns, exit 0, read-only tools and no tool denials.
  Reviewed the actual findings and the 18-line configuration diff before release.
- Pushed source `05540a7`, then deployed Hosting only to shop-pos-89294.
  Version `4f04f89cb357738d`, released 2026-11-11 14:28:39 UTC. Compared the
  complete 69-file inventory with `00daee4b204effc7`: every file hash is unchanged;
  only Hosting configuration changed. Rollback: `00daee4b204effc7`.
- Live cache regression passed all 48 marketing URLs, shared-asset exclusions,
  and existing app/order policies. The actual live HTML/JS/manifest bytes still
  match local files. Live Edge checks passed on home/features/pricing at
  390/1440 px, including new wording, plan switches, no overflow or page errors.
  Looked at the actual desktop homepage capture. No physical-device/Safari test.
- Evidence: `D:/pokpok-cache-release-20261112/` (independent review, deployment
  result, Hosting file inventory, byte checks and live browser captures).

### 2026-11-12 — Published revised website wording

- Pushed `5c68828` to `origin/master`, then deployed Hosting only to the explicit
  project `shop-pos-89294`. Release version `00daee4b204effc7`, at
  2026-11-11 14:03:49 UTC. Release message records the full source commit.
- Fresh independent Claude CLI review of `1913e1c..5c68828` completed with no
  blocking findings (27 turns, exit 0, read-only snapshot, no tool denials).
  Accepted pre-existing Low observations: JSON-LD description still uses the
  older accurate wording (revisit with metadata edits); bare shared-script URLs
  on non-pricing pages (revisit when shared JS behavior changes).
- Re-ran the local marketing gate: 16 pages × 5 widths passed. Focused copy
  checks passed for 3 pages × 5 widths / 40 states; syntax and diff checks passed.
  Looked at mobile/desktop hero, pricing and feature-story captures.
- Live home, features, pricing, shared JS and app manifest all match local bytes.
  Read both Hosting versions' complete file lists: 69 files each, exactly the
  four intended HTML/JS files changed; no additions/removals and APK unchanged.
- Live Edge/Chromium smoke passed on 3 pages at 390/1440 px: new copy, business
  switches, monthly/yearly prices, no horizontal overflow or page errors.
  No physical-device or Safari test, app build or iOS release in this round.
- Rollback version: `c28bc9b38e17d96e`. No Functions, rules, database,
  payment/security configuration or hosting-routing changes.
- Evidence: `D:/pokpok-copy-release-20261112/` (review, file-list comparison,
  live byte checks and browser captures); copy details in
  `docs/website-copy-2026-11-12.md`.

### 2026-11-12 — Revise website wording from video feedback (local only)

- Replaced colloquial headings/descriptions on home, features and pricing with
  clear Thai for sales, stock, credit, kitchen, checkout, online ordering and
  reports. Updated home search/share descriptions and trial/download CTAs.
- Updated retail Solo/Lite/Full descriptions and fit text in both static HTML
  and shared JS; bumped the script URL on both pricing surfaces. Existing
  prices, tier features, trial terms and iOS TestFlight qualification preserved.
- Updated the existing retail-toggle assertion to use the revised copy.
  Local regression passed: 16 pages × 5 widths. Focused text geometry and
  pricing-state agreement passed: 3 pages × 5 widths, 40 rendered states.
  No physical-device/Safari test; no push, deployment or app build.
- Details: `docs/website-copy-2026-11-12.md`; evidence on
  `D:/pokpok-copy-20261112/` and `.remember/tmp/brand-preview/`.

### 2026-11-11 — Public website checklist audit (read-only; recorded 2026-11-12)

- Audited live source a9b2673: 16 routes at 320/390/768/1440 px, 29 HTTP(S)
  links and 13 interaction flows. No horizontal overflow, broken checked links
  or page exceptions. Full report: `D:/pokpok-audit-20261111/website-audit-2026-11-11.md`.
- Lighthouse/Edge lab Performance: home mobile/desktop 100/100, pricing mobile
  99, features mobile 98. PSI API returned 429 and PSI UI could not resolve
  the URL: real-user Core Web Vitals remain unverified.
- Pending findings: no conversion tracking on marketing pages; oversized POS
  screenshot/Pexon raster; stale sitemap lastmod; color-only breadcrumb links
  and missing main landmarks in two blog articles; expanded mobile menu outside
  a navigation landmark. Menu keyboard interaction itself passed.
- No site changes, deployment or physical-device/Safari test in that audit.
  Its handoff write was deferred because C: was full; space became available
  before this entry was merged. Original evidence remains on D:.

### 2026-11-11 — Released Android 1.2.76 (93) and website screenshots
- Fast-forwarded master to `1913e1c` and pushed, then deployed Hosting only to
  `shop-pos-89294`; deployed Hosting version `c28bc9b38e17d96e`.
- Verified public `https://pok-pok.app/app/version.json` matches the staged
  manifest. Downloaded the public APK: 97,532,155 bytes, SHA-256
  `afb8f92f10568907da090296ff5cb9e5788628d506a193453ff8bebf5a74a9ad`, identical
  to the signed APK installed and checked on the tablet.
- All 7 changed HTML files and 3 new screenshots fetched from pok-pok.app match
  local bytes. Verification finished at 2026-11-11 03:11:57 UTC; evidence in
  ignored `.remember/tmp/release-1.2.76/live-verification.json`.
- Refreshed the existing Google Drive provenance document in the screenshots
  folder with the deployment result, preserving its file ID and sharing.
  Metadata readback confirms the new size (9,363 bytes) and modification time.
- Water removal was verified again in the updated tablet's product list.
  Ten other demo products remain; no sales or historical stock records changed.
- Previous APK/manifest retained in ignored release scratch for rollback.
  iOS/TestFlight was not built or triggered. No backend/security/payment changes.

### 2026-11-11 — Prepared Android 1.2.76 (93) and tested on the tablet
- Release APK built successfully (97,532,155 bytes), version read from APK
  packaging: 1.2.76 / 93. SHA-256:
  `afb8f92f10568907da090296ff5cb9e5788628d506a193453ff8bebf5a74a9ad`.
  apksigner verification passed; certificate matches the previous release.
- Installed with `adb install -r` on SM-X900; existing login and data retained.
  Package manager confirms version/build. Two existing table tickets appear on
  the kitchen screen with zero bill/close-table shortcuts. Opened table 1 from
  Sales > dine-in; its bill and รับชำระเงิน button remain available.
  No payment, sale or kitchen-status change was made during this check.
- Local analyze and 21 focused kitchen tests passed; website checks passed
  16 pages × 5 widths. Source review round 7 was clean. Metadata review round 8
  (bundled Claude Code 2.1.322) returned no report after 705 seconds and was
  stopped, not counted as a pass. Fresh read-only Codex round 9 independently
  checked commit 33207c0, metadata/update-service/hosting interactions and both
  APK hashes, with no finding. Signature and device checks were run separately.
- Staged APK and matching public/app/version.json; previous APK/manifest backed
  up in ignored release scratch. Still not deployed. iOS is not built locally;
  Codemagic's TestFlight workflow has no push trigger and was not started.

### 2026-11-11 — Removed water from the demo menu before publishing
- Owner explicitly requested removing น้ำเปล่า. Verified the authorized demo
  shop, saved the complete product and SKU-index record in ignored local
  release scratch, then deleted only that product and its matching SKU index.
  The transaction checked no online stock reservation and no concurrent edit.
- Readback: 10 products remain; every other product's update time is unchanged.
  Connected SM-X900 product screen also lists the remaining products without
  น้ำเปล่า. Existing orders, sales and inventory history were not modified.
- The three prepared website screenshots contain no water product, so their
  original captures are retained. No release has been published yet.
- Release checks so far: Flutter analyze PASS; kitchen output, regression and
  chef journey tests PASS (21); marketing checks PASS (16 pages × 5 widths).
  APK 1.2.76 (93) build is running. Independent review round 7 (fresh, read-only
  Codex process, no inherited conversation) read the full unreleased source and
  found no blocking defect. It checked old 1.2.75 artifacts; new APK metadata,
  signature and installation must be verified after the build.

### 2026-11-11 — Replaced website app screenshots with real 1.2.75 captures
- Captured POS (curated pasta photos and draft cart), unpaid demo order, and
  report overview from the connected SM-X900 running 1.2.75 (92). Updated home,
  features, two guides and three blog/share surfaces; replaced outdated image
  references, alt text and captions. Removed the four unused legacy images from
  public assets. No app UI, price, payment or security configuration changed.
- Used the authorized demo shop. Created one clearly labelled pending-payment
  order solely for capture, never confirmed payment; deleted it with a status
  guard and verified absence. Cleared the temporary POS cart. Restored tablet
  display density/system-bar settings and S Pen setting after capture.
- Local: marketing checks PASS, 16 pages × 5 widths. Separate image geometry
  checks PASS, 3 pages × 4 widths; original aspect ratios retained and full-size
  image link opens. Reviewed actual browser screenshots at 390/768/1440.
  A screenshot-only newcomer walkthrough found a capture artefact (sticky header
  over a scrolled element); full viewport recapture confirms normal page layout.
- Source and provenance: `docs/website-screenshots-2026-11-11.md`. Copied approved
  screenshots, desktop/mobile website previews and that document to the team's
  dated 03_App Assets folder; Drive file readback verified separately.
- Website source only, **not deployed**; no new APK or Functions release. These
  captures do not resolve or certify the previously recorded checkout bugs.

### 2026-11-11 — Recorded the owner's website development core
- Owner designated four supplied screenshots as the standing website direction.
  Recorded all ten areas in `docs/website-development-core.md` and routed future
  website planning, edits, reviews and releases to it from `AGENTS.md`.
- Covers hero clarity, visual identity, retail/restaurant pages, feature proof,
  pricing, trust, CTAs/install guidance, mobile, SEO and footer. Explicitly records
  the latest English-feature-name/Thai-description direction over the older
  "Thai names first" planning note; no website copy changed in this task.
- Documentation only; no application build, deployment or device test.

### 2026-11-11 — Curated photos applied to the authorized demo shop
- With owner authorization, replaced names/photos for eight demo products using
  the curated Pexels set, grouped them into pasta, salad, desserts and drinks,
  and pinned them. Kept the other three in เมนูเดิม, unpinned; no products deleted.
- Backed up the original documents locally under the ignored food-set review
  directory before writing. Atomic updates guarded against concurrent edits.
  Readback verified all eight image downloads and unchanged other product fields
  including price and stock. Sales history was not edited.
- Data change only; no new app build. ADB showed no connected device, so the
  updated menu has not been checked on a real device.

### 2026-11-11 — Kitchen screen no longer opens bills (Gif feedback)
- Gif: "ไปที่บิล ปิดโต๊ะ ไม่อยากให้ครัวกดได้ อยากให้กดได้แค่แคชเชียร์". Her kitchen
  device is logged in as the owner, so a staff-position check would not help.
  Removed the "ไปที่บิลโต๊ะ / ปิดโต๊ะ" button from the kitchen screen for
  everyone; bills are opened/closed from โต๊ะ. Branch `kitchen-no-bill-button`.
- Verified locally: analyze clean; kitchen tests 16 pass (test now asserts the
  button is absent); full suite 397 pass, only the 5 pre-existing failures.
  Not released (needs an APK release); not on a device.

### 2026-11-10 — Demo data for website screenshots (paused by owner)
- Owner allowed turning the shop logged in on SM-X900 (1.2.75 installed) into a
  demo shop. Added through the app UI: categories อาหาร and เครื่องดื่ม; 7 dishes
  (ข้าวกะเพราหมูกรอบ 60, ข้าวผัดกุ้ง 70, ผัดไทยกุ้งสด 80, ต้มยำกุ้งน้ำข้น 120,
  ข้าวมันไก่ 55, ส้มตำไทย 50, ไข่เจียวหมูสับ 45) and 4 drinks (ชาไทยเย็น 40,
  กาแฟเย็น 45, โกโก้เย็น 45, น้ำเปล่า 10), stock 50/100; tables 3–6. Old items
  (ยาดม, เลย์, ขนม/ยา) and the empty open orders on tables 1–2 are unchanged.
- Installed ADBKeyboard (senzhk/ADBKeyBoard v2.5-dev, no permissions) on the
  tablet with owner approval so adb can type Thai; Samsung Keyboard restored as
  the default. Uninstall with `adb uninstall com.android.adbkeyboard` when done.
- Later the owner added a local allow rule (`.claude/settings.local.json`, not
  committed) for one scratchpad script that uses the owner's gcloud login and is
  locked to the demo shop (owner's own shop, the one on the tablet). Verified the
  11 new products, then (owner request) deleted ยาดมตราโอ้ยเสี้ยน and เลย์ (and
  the ยาดม Storage image), and gave all 11 dishes photos: uploaded to
  `shops/<uid>/products/<id>.jpg` with a download token and `imageUrl` set, the
  same layout the app uses. Photos are CC0 / public domain only (Wikimedia
  Commons: Basil fried crispy pork with rice Chiang Mai 2017-07-11 (002); Khao
  Phat Kung; Phat thai Chiang Mai 2017-07-08 (002); Tom Yum Soup; Som Tom
  (Papaya Salad) Little Thai 2024-06-14; FoodOmelete; Thai Red Ice Milk Tea Siam
  Siam 2024-07-31; Iced Coffee 20240730-135859; Classic Iced Chocolate MOGUMOGU
  2025-04-16, cropped to the glass so no faces; This is a cold water bottle.
  Flickr PDM: "Hainan Chicken Rice" 54909670636), square-cropped to 600 px.
  Seen on the tablet 2026-11-11: photos show in the POS grid and table picker.
- 2026-11-11 on the tablet: table 1 has 3 dishes sent to kitchen + bill
  requested (รอชำระเงิน, ฿220); table 2 has 3 dishes sent (กำลังใช้งาน, ฿155).
  Website screenshots saved locally (not committed): tables.png, pos.png in the
  session temp folder `web-shots/`.
- **Unresolved, investigate before more demo work:**
  1. The sale screen keeps jumping back from สั่งกลับบ้าน to the tables view
     (ทานที่ร้าน) by itself; once the counter cart was emptied too.
  2. A counter cash sale (฿190, received ฿200) was confirmed, the screen jumped
     to the tables view with no receipt, and รายงาน still showed 0 bills.
     Not yet known whether it is queued (see "ขายออฟไลน์ / บิลค้าง" on the POS)
     or lost. Once, the payment sheet showed "ติดต่อระบบไม่ได้" although the
     tablet's network was fine (ping to Firestore OK).
  3. The green "ส่งเข้าคิวครัวแล้ว" SnackBar (with action จอครัว / พิมพ์) never
     times out, stacks per send, and covers the checkout buttons until swiped.
  ADBKeyboard is installed but the Samsung keyboard is the default.
- Next: add items to tables (one awaiting payment), a counter sale, then take
  screenshots of tables, POS and reports for the website.

### 2026-11-10 — Website round 1 deployed
- Owner approved; fast-forwarded master to `0089fd2`, deployed hosting. Verified
  live: new H1, `#plans` section, new site.js; version.json still 1.2.75/92.
- Home hero: the H1 now names the product ("แอป POS สำหรับร้านค้าปลีกและร้านอาหาร");
  the slogan moved to the eyebrow; the subtitle lists plain benefits (phone or
  tablet the shop already has, cash/transfer/QR, low stock, debts, daily sales,
  table orders to the kitchen).
- Home page now shows the real pricing cards (monthly/yearly and shop-type
  toggles) instead of a one-line summary. Both home and `/pricing/` cards add a
  "เหมาะกับ…" line per plan and shop type, a yearly per-month average (฿166 /
  ฿333 / ฿499), and a named CTA per plan. Prices unchanged.
- Section id is `plans`; legacy `/#pricing` still redirects to `/pricing/`.
  CSS/JS links carry `?v=20261110-plans`.
- Verified locally: `scripts/test_marketing_pages.cjs` PASS (16 pages × 5
  widths, plus new home-pricing checks); screenshots at 390 and 1440 reviewed.

### 2026-11-10 — Released Android 1.2.75 (92)
- Owner said "ปล่อยก่อน" while review round 6 was running; round 6 then
  finished with nothing above Low (backlog). Rounds 4–6 found only Lows.
- Merged the branch into master (`7458f2f`, HANDOFF add/add conflict resolved
  with the branch copy; trees identical afterwards).
- Before deploy: Functions `npm test` 174 + 16 pass; emulator `test:rules`
  exit 0; `staff_work.integration.cjs` exit 0.
- Deployed Functions `tablePromotions`, `staffWork`, `staffCheckout`,
  `createRefund` (asia-southeast1) — all "Successful update".
- Bumped to 1.2.75+92, built the release APK, verified the signing cert
  `f7dc70e0…` and versionCode 92, copied to `public/app/pokpok.apk`, updated
  `version.json`, then deployed hosting (only `version.json` changed in public/).
- Verified live: served `version.json` is 1.2.75/92 and the downloaded APK's
  sha256 and size match the build.
- Not verified: 1.2.75 on a real device.

### 2026-11-10 — Review round 5 fixes
- Round 5 (subject `6649b09`): nothing Critical, High or Medium; five Lows.
- Fixed **L-1**: going back with only a phone no longer makes the phone the new
  customer's name (test added). Fixed **L-5**: loyalty messages now clear the
  whole queue, and redemption messages use the same path. Fixed **L-3**: the
  attach timeout message names the customer still on the bill and is silent
  after ✕.
- Backlog: L-2, L-4 (see Current state).
- Verified locally: analyze clean; flutter test 397 pass, only the 5
  pre-existing failures. No server code changed. Not on a device.

### 2026-11-10 — Review round 4 fixes
- Round 4 (subject `45bb0d6`): nothing Critical, High or Medium; four Lows
  plus a test-gap note.
- Fixed: going back in the debt picker no longer forces the old name over a new
  search; loyalty messages replace each other instead of queuing (a stale
  "รอสักครู่" could delay the attach result; only partly true, completed in
  round 5); attaching a customer allows 12 s
  for the create write and the timeout message says the customer may already be
  saved; ✕ while an attach is loading now cancels it.
- Verified locally: analyze clean; flutter test 396 pass, only the 5
  pre-existing failures. No server code changed. Not on a device.

### 2026-11-10 — Review round 3 fixes
- Round 3 (subject `9e56dbe`): one Medium, five Lows; nothing Critical/High.
  It also flagged, outside its subject, that attaching a loyalty customer on a
  slow network could finish while the payment sheet was open and reset the
  points discount (QR/transfer sale saved at full total with less paid).
- Fixed: attaching a customer and choosing points now share one lock with
  checkout and bundles, in both directions. Every loyalty read has a 6 s timeout
  (falls back to the shown balance or shows a connection message). While loading,
  the strip shows a spinner that absorbs taps, and checkout/bundles say why they
  wait. ✕ always works.
- Fixed: a balance that covers only part of the applied points caps the
  redemption to the new maximum with a message (round 2 only handled zero).
- Debt picker: hidden list rows can no longer take keyboard focus
  (`ExcludeFocus`); going back to the list keeps the typed new-customer name.
  Tests now check the search text, the restored name and the focus exclusion.
- Verified locally: analyze clean; flutter test 396 pass, only the 5
  pre-existing failures. No server code changed. Counter POS lock still has no
  automated test (backlog L-4). Not on a device.
- Round 3 Lows L-1 to L-4 fixed as above; L-5 (POS tests) is backlog.

### 2026-11-09 — Review round 2 fixes
- Round 2 (subject `d841f9b`): one Medium, four Lows; nothing Critical/High.
- Fixed **M-1**: the counter redeem flow awaited a balance read with no guard,
  so a slow network could apply a points discount mid-checkout or to the next
  bill. It now holds a `_redeeming` lock (button, ✕, checkout and bundles
  blocked) and re-checks the attached customer after every wait.
- Fixed **L-2**: if the re-read balance no longer covers the applied points, the
  redemption is cleared with a message; the prefill never exceeds the maximum.
- Fixed **L-1**: the phone-conflict message points to a new "กลับไปรายชื่อ"
  button that returns to the list searched by that phone. The list now stays
  mounted while adding (a new test caught a re-listen crash there).
- Verified locally: analyze clean; flutter test 395 pass, only the 5
  pre-existing failures. No server code changed. Not on a device.
- Backlog L-3, L-4: see Current state. Next: review round 3.

### 2026-11-09 — Review round 1 fixes
- Round 1 report: H1, M1 and L1–L6, all introduced; nothing Critical.
- Fixed **H1**: the staff tables grid crashed ("Stream has already been
  listened to") after one failed poll. The bill stream is now listened once in
  `initState`. A regression test fails on the old code and passes now.
- Fixed **M1**: a new ค้างชำระ customer whose phone belongs to a differently
  named customer is now refused with a message naming that customer, instead of
  booking the debt to them.
- Fixed **L3**: setting a manual discount now shrinks the points redemption.
  Fixed **L4**: the counter redeem dialog re-reads the points balance.
- Verified locally: flutter analyze clean; flutter test 395 pass, with only the
  5 pre-existing failures. No server code changed. Not yet on a device.
- Backlog L1, L2, L5, L6: see Current state. Next: independent review round 2.

### 2026-11-09 — Pushed; release started with an independent review
- Owner asked to push and release. Pushed `master` (3679443) and
  `gif-feedback-2026-11` (7b805f2) to GitHub. Pushing deploys nothing: no GitHub
  Actions, and `codemagic.yaml` has no push trigger.
- Security: the `origin` remote URL embeds a GitHub personal access token in
  plain text in `.git/config`. Owner advised to revoke it and switch to a
  credential manager. Not changed yet.
- Owner chose an independent review before release (release-gate). Round 1:
  fresh headless Claude Code 2.1.319 (`--restricted`, read-only), subject
  `d29153f..gif-feedback-2026-11`. Grok not installed. Use the VS Code bundled
  `claude.exe`; `~/.local/bin/claude.exe` is 2.1.77 and lacks `--restricted`.
  Python for the wrapper: `~/.local/bin/python3.12.exe`.

### 2026-11-09 — Handoff log introduced
- Added this file and the "Handoff log (required)" rule in `AGENTS.md`
  (branch `467777f`, `2c1b713`). At the owner's request both were also
  cherry-picked onto local master as `42dce63` and `3679443`, so any assistant
  starting from master sees them. Nothing pushed.

### 2026-11-09 — Device test, refund bug fix, cleanup
- Installed the branch build on SM-X900 and tested on the real shop (owner approved):
  table status (ว่าง / กำลังใช้งาน / รอชำระเงิน), bill-request toggle, drag to
  swap tables (order persisted, then restored), debt customer picker, counter
  loyalty earn (1 point) and redeem (฿1 off → ฿19), short-balance warning,
  report wording ค้างชำระ. All worked.
- Found refunds from the sales report silently doing nothing (sheet context used
  after it closed). Fixed in `0de7903` with `test/report_refund_test.dart`;
  verified on device by refunding all three test sales.
- `bc8a3e8`: redeem dialog helper text no longer truncated; sale-complete summary
  shows ค้างชำระ for debt bills; debt refund dialog label no longer overlaps.
- Not tested on device: table-bill loyalty and staff bill request (need the
  Functions deploy).

### 2026-11-08/09 — Gif restaurant feedback batches (branch commits)
- `fbffe9a` staff counter checkout retries closed transactions.
- `719f8b9` refunds retry closed transactions.
- `fd61b2f` ทานที่ร้าน / สั่งกลับบ้าน labels, kitchen button mentions gifts only
  when present, checkout pin removed, ขายเชื่อ → ค้างชำระ in the app (accountant
  CSV keeps ขายเชื่อ).
- `415c4f6` ค้างชำระ uses a customer picker linked to the customer list.
- `0ccba72` three table states with a bill-request action (`billRequestedAt` on
  the open tableOrder; staff via `staffWork` action `bill`).
- `8a3044e` product form shows live cost / profit / margin and points to recipe mode.
- `40be401` owners drag tables to swap places (`sortOrder`).
- `d6805c8` counter loyalty redemption with a shop rate (default 10 points = ฿1).
- `d2265f3` table-bill loyalty via `tablePromotions` action `loyalty`.
- Verified locally each time: flutter analyze clean, Flutter tests (only the 5
  pre-existing failures), Functions unit tests, emulator `test:rules`.
