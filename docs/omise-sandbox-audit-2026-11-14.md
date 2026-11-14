# Omise sandbox audit — 2026-11-14

Original audit scope: inspect and test the existing sandbox at source `55d187e`.
The original audit made no code change or deployment; the owner subsequently
authorized the correction and release documented below. No real sale, stock
change, live payment or security-enforcement change occurred.

**Update after owner-authorized correction:** the defect below is now fixed and
verified locally and **deployed as source `d262183`**. All three payment methods
passed on the physical tablet in Test Mode. The original audit evidence is
preserved below; see the final release section for current results and limits.

## Original audit result: automatic confirmation was blocked

**P1 — `functions/omise_sandbox.js:59` requires a field absent from actual Omise
charge responses.** A successful charge must satisfy `charge.captured === true`
to become `successful`. All three successful provider tests returned
`status: "successful"`, `paid: true`, and `capture: true`, but no `captured`
property. The current handler consequently leaves the isolated test order in
`awaiting_payment`.

| Test, THB 100 each | Actual Omise Test Mode result | Current local handler result |
| --- | --- | --- |
| Card: successful authorization | successful, paid | pending / awaiting_payment |
| Card: insufficient funds | failed, unpaid | failed / payment_failed |
| TrueMoney | successful, paid | pending / awaiting_payment |
| PromptPay | successful, paid | pending / awaiting_payment |

Polling (`omise_sandbox.js:170`) and webhook handling (`:177`) share `record()`
and `validateCharge()`, so neither path resolves this mismatch. The browser also
keeps the new-payment action hidden while an attempt is pending.

The same assumption exists in `functions/online_payment_evidence.js:23`. That is
an internal foundation for live payments, without a customer endpoint accepting
this evidence; this audit does not establish an incident involving live money.

Existing fixtures in `omise_sandbox.test.js:9`,
`omise_sandbox.integration.cjs:20`, and `online_payment_evidence.test.js:13`
invent `captured: true`, which explains why the existing suites pass.

Omise documents `paid` as payment/capture evidence and `capture` as the automatic
capture setting. **Do not simply rename the check to `capture`: that setting is
not proof of payment.** The correction should use verified provider status and
paid evidence, retaining the account/mode, instrument, order metadata, amount,
currency, refund and reversal checks. The observed pinned-version responses also
omit `captured_amount`; adding a mandatory check for it would need separate
compatibility verification. See [Omise Charges API](https://docs.omise.co/charges-api).

## What the tests actually exercised

- Existing unit suites: `npm.cmd run test:omise`, exit **0**, 24 tests. Provider
  responses and database/auth are fixtures.
- Browser: `node scripts/test_omise_sandbox_browser.cjs`, exit **0**. Mocked
  Firebase/Omise; covers all three payment choices, polling/reload, pending
  recovery, duplicate prevention and 360/820-pixel layouts.
- Firestore emulator: `omise_sandbox.integration.cjs` through Firebase
  `emulators:exec`, exit **0**, with Java 21 from Android Studio's JBR prepended
  to PATH. Checks concurrent attempts and denied direct client writes against
  real emulator rules. Provider is mocked. The first Java 17 run failed before
  the tests; only the Java 21 rerun passed.
- Flutter: `flutter test test/payment_journey_test.dart` using the repository
  SDK, exit **0**, 20 tests; includes default sandbox visibility and cancellation
  without confirming a real bill. This is widget verification, not a tablet run.
- Actual provider: created four sandbox charges with the existing test-key pair
  and API version `2019-05-29`. Successful card used the provider's test
  authorization page. TrueMoney and PromptPay were completed with the official
  test-only `mark_as_paid` endpoint after checking mode, amount and audit metadata.
  PromptPay QR downloaded successfully as SVG. Repeated create for each same
  attempt returned the same charge. Failed-card handling worked.
- Provider-backed handler tests used **in-memory database and auth fixtures**.
  Per-charge production webhook URLs were removed from these test requests;
  return URLs pointed to `example.invalid`. Status and duplicate webhook tests
  invoked local handlers that retrieved actual charges from Omise. They did not
  exercise authenticated deployed callables or actual webhook delivery.
- Four charges remain in Omise **Test Mode** history (three successful, one
  failed). No new attempt documents were written to production Firestore.
- A minimized, synthetic-ID reproduction asserts the three successful response
  shapes must confirm. `node --test
  .remember/tmp/omise-provider-contract-repro-20261114.cjs` exits **1** with all
  three assertions failing (`pending` instead of `successful`). It is a scratch
  audit reproduction, not a test added to the normal suite.

Official test references: [API testing](https://docs.omise.co/api-testing),
[PromptPay](https://docs.omise.co/promptpay),
[TrueMoney Wallet](https://docs.omise.co/truemoney-wallet).

## Deployed checks and limits

- `/payment-test/index.html` and `/payment-test/sandbox.js` return HTTP 200 and
  match local SHA-256 hashes. Create/status/webhook functions are active and use
  the existing test-secret version. The test account and required channels are
  available. The deployed backend bundle was not downloaded/hash-compared.
- Signed-out config/status requests return 401 `UNAUTHENTICATED`. Webhook GET
  returns 405 and malformed POST returns 400. These are narrow checks, not a
  complete security audit.
- One older PromptPay attempt remains `pending` in Firestore while its provider
  charge is `expired`. This is a reconciliation follow-up, not proof that all
  webhooks are broken. Foreground polling should be tested after reopening it.
- No physical tablet payment journey was completed. Automatic approval review
  rejected the ADB browser-launch/forward command with only `blocked by policy`;
  it was not retried through another route. Manual browser login was requested
  while the independent provider checks continued.

## Required follow-up

1. **Completed locally below:** correct the success predicate and replace invented
   response fields in fixtures, preserving all binding checks.
2. **Completed locally below:** prove success, pending/unpaid, failed/expired,
   refunded/reversed and duplicate processing; reproduction now passes.
3. Verify authenticated deployed polling and real webhook delivery with isolated
   sandbox attempts, then complete all three journeys on the tablet.
4. Old expired-attempt foreground reconciliation: **verified below**. A successful
   payment's polling/webhook confirmation still needs the predicate fix and retest.

## Login navigation follow-up

The owner reported reaching Subscribe when trying to log in for the tablet test.
On 2026-11-14, live signed-out Edge reproduced the homepage's **เข้าสู่ระบบ**
link opening `/subscribe/` (subscription management). Direct `/payment-test/`
stayed on the sandbox page and displayed its own **เข้าสู่ระบบด้วย Google**
button. Both the sandbox HTML and JS still matched local hashes; `/payment-test`
without a trailing slash canonicalized to `/payment-test/`, not Subscribe.
The sandbox uses popup/email sign-in and contains no Subscribe redirect.
The exact button the owner tapped and the authenticated tablet result were not
observed, so this is a verified navigation explanation, not a reproduced OAuth
redirect defect. Open the sandbox URL directly and sign in there; no subscription
purchase is required for the founder-only sandbox. No source change or deployment.

## Tablet login and status refresh verified — subsequent check

After the owner reported login complete, read the already-open SM-X900 Chrome
page at `/payment-test/`. The authenticated sandbox controls were visible with
the old THB 100 PromptPay attempt now shown as expired. Tapped only the observed
**ตรวจสถานะล่าสุด** control; the UI retained the correct expired result and
offered **เริ่มรายการทดลองใหม่**.

Server logs corroborate authenticated config/status HTTP 200, including the
refresh POST at `2026-11-14T04:44:52Z`. A read-only Firestore check confirms the
old isolated attempt is `expired` / `payment_failed`, resolving the earlier
stale-status observation through foreground reconciliation. No new charge was
created. The existing sandbox status handler updated the isolated attempt during
reconciliation; real order, stock and sales collections were not changed.

This follow-up used screen inspection and the existing refresh button, not the
previously rejected browser-launch/port-forward command. It proves tablet login,
founder access and expired-attempt status retrieval. It does not prove successful
payment confirmation: the missing-`captured` predicate defect is still unfixed.
Sanitized corroboration: `.remember/tmp/omise-tablet-server-check-20261114-results.json`.

Local sanitized audit evidence is under `.remember/tmp/` in
`omise-audit-20261114-results.json`, `omise-provider-probe-20261114-results.json`
and `omise-reconcile-probe-20261114-results.json`. No credentials or customer
identifiers are included in this report.

## Correction verified locally — 2026-11-14

Owner authorized the fix after tablet login was verified. The implementation uses
`status === 'successful'` and `paid === true`, not `capture` (automatic-capture
configuration), and no longer requires the nonexistent `captured` field. The same
correction applies to the internal future-live verifier; live payments remain
unavailable and were not exercised.

Mode, account/actor, exact attempt/order, instrument, amount and currency checks
are retained. A nonzero refund or reversal cannot confirm. Missing/invalid refund
evidence leaves a sandbox attempt pending; the live verifier rejects it. If
`captured_amount` is returned, it must equal the charge amount to confirm; older
observed responses omit it. Refunded/reversed test orders cannot be reconfirmed by
an older successful response.

Verification performed:

- Updated provider fixtures first: `npm.cmd run test:omise` failed **14/27** on
  the old production code. After the correction, **27/27 pass**. Coverage includes
  all three methods, manual-vs-automatic capture configuration, unpaid/pending,
  explicit partial capture, failed/expired, refunds/reversals, binding failures,
  duplicate callbacks and no duplicate confirmation timestamp.
- Firestore emulator integration with real-shaped provider fixture: **pass**.
  Concurrent claim produces one charge; writes remain isolated; direct client
  reads/writes are denied. Emulator transaction-lock retries resolved; exit 0.
- Existing mocked browser suite at mobile/tablet sizes: **pass**. This is a
  frontend regression check, not an actual tablet payment or provider UI test.
- Original minimized three-channel contract reproduction: **3/3 pass**, unchanged.
- Actual Omise Test Mode **read-back only** at `2026-11-14T05:11:36Z`: 16 GET
  requests across four existing audit charges, no new charge or payment-state
  mutation. Each local status handler and two duplicate local webhook invocations
  fetched the actual provider result. In-memory DB/auth; zero production writes.

| Existing TEST charge | Provider result | Corrected local handler |
| --- | --- | --- |
| Card paid | successful / paid | successful / confirmed |
| Card insufficient funds | failed / unpaid | failed / payment_failed |
| TrueMoney paid | successful / paid | successful / confirmed |
| PromptPay paid | successful / paid | successful / confirmed |

All duplicate callbacks preserved confirmation time. Sanitized read-back evidence:
`.remember/tmp/omise-fixed-readback-20261114-results.json`. Real test identifiers,
keys and customer details are not included here.

**Status at the end of local verification:** code/docs only. Deployment and
device verification were subsequently authorized and completed as follows.

## Release and physical tablet verification — 2026-11-14

Deployed only `omiseSandboxCreate`, `omiseSandboxStatus` and
`omiseSandboxWebhook` to `shop-pos-89294`, `asia-southeast1`, at 05:26 UTC.
All three are ACTIVE on Node.js 22:

| Function | Deployed revision |
| --- | --- |
| Create | `omisesandboxcreate-00008-vit` |
| Status | `omisesandboxstatus-00008-pos` |
| Webhook | `omisesandboxwebhook-00007-men` |

Downloaded each function's exact-generation deployment source archive and
compared `omise_sandbox.js`, `online_payment_evidence.js`, `index.js`,
`package.json` and `package-lock.json` with reviewed local source. All match.
All archives have SHA-256
`c2d8671b28e818caf62970a4a5ee4e8194635ff5c2328d9f46b5f2e3dad89661`.
Test secret version 3, instance limits, authentication and App Check settings
were unchanged. No Hosting deployment, APK build or version bump was required;
the native app remains 1.2.78 (95).

Before deployment, the 27 focused tests and mocked browser checks passed again.
A fresh read-only Codex review of `55d187e..d262183` found no defects. This was
source review; the following provider/device evidence is separate.

### Device and provider results

Used the owner's already-authenticated Samsung SM-X900 Chrome page at
`/payment-test/`. Each new attempt uses THB 100 of simulated money and writes
only `omiseSandboxAttempts`.

| Physical tablet journey | Observed final result | Confirmation time (UTC) |
| --- | --- | --- |
| Official successful test card entered in the form | successful / confirmed | 05:27:08.627 |
| PromptPay QR generated; official TEST API marks it paid | successful / confirmed | 05:28:34.451 |
| TrueMoney redirects to provider TEST page; select paid and return | successful / confirmed | 05:32:55.528 |
| Second TrueMoney attempt; select failed and return | failed / payment_failed | No confirmation timestamp |

For PromptPay, moved Chrome to the background using Android HOME before the
official test-payment action. The provider webhook reached the deployed revision
at 05:28:34.195 UTC (HTTP 200), and the attempt confirmed at 05:28:34.451 UTC.
The prior status poll was 05:28:25.319 UTC and the next was 05:31:29.170 UTC.
This proves the deployed webhook confirmed independently of browser polling.
Returning to Chrome displayed success without a manual status-refresh tap.

Actual provider webhook deliveries also returned HTTP 200 for card and both
TrueMoney outcomes. TrueMoney success arrived at 05:32:55.300 UTC; failure at
05:37:03.896 UTC. The return page restored the signed-in session and displayed
the matching result. Failed payment did not confirm an order.

Repeated each successful charge callback twice against the deployed webhook.
All six requests returned HTTP 200; read-back by exact attempt ID verified all
three original confirmation timestamps were unchanged. Posted callbacks contain
only the charge ID; the backend fetches payment evidence from Omise itself.

Sanitized machine results: `.remember/tmp/omise-deployed-test-results.json`.
Raw device captures and identifier-bearing audit files remain in ignored local
scratch storage, not in the repository. Tablet is left on the completed failed
TrueMoney test result; no pending attempt remains from these four journeys.

### Limits and follow-up

- These are physical-tablet **Chrome sandbox** tests, not native app/iOS checkout
  tests or actual bank/card/wallet debits. Live Mode remains unavailable.
- No real shop order, stock, sales, accounting or cash-round data was created.
- Existing sandbox UI briefly retains the previous success label while creating
  a new attempt, then correctly displays pending. This transient display issue
  is a separate frontend follow-up; no new attempt was incorrectly confirmed.
- Previous revisions/source were retained for rollback: create `00007-xod`,
  status `00007-tik`, webhook `00006-xew`. No rollback was needed.

## Installed Android app follow-up — 2026-11-14

After the owner asked whether the app itself had been tested, used installed
`app.pokpok.pos` 1.2.78 (95) on the same SM-X900 and the authorized test-shop
founder session. No APK, Hosting, backend or security changes in this pass.

Started in Sales -> Takeaway with an initially empty cart. Added one temporary
THB 80 item and opened the native payment sheet. The founder-only Omise test
entry opened its separate THB 100 test-order screen, then Android Chrome Custom
Tab. The existing browser session worked without sign-in or Subscribe redirect.

| Native-started journey | Result after closing Custom Tab |
| --- | --- |
| Generate PromptPay TEST QR, simulate paid with official TEST API | Native app automatically displayed confirmed; exact native attempt matched backend |
| Create another native attempt, generate TEST QR, simulate failure | Native app automatically displayed payment_failed; no confirmation timestamp |

The first attempt was created at 05:49:33.527 UTC and confirmed at
05:50:08.253 UTC. Its actual provider webhook at 05:50:08.001 UTC returned 200.
The second was created at 05:51:00.966 UTC. Its failure webhook at
05:51:18.989 UTC returned 200; isolated Firestore read-back showed failed /
payment_failed. Both simulations validated TEST mode, THB 100 and matching
attempt/instrument bindings before using the provider's TEST-only action.
No native refresh button was tapped; returning to the app updated the result.

Returning from sandbox to the payment sheet preserved the one-item THB 80 cart
and unpaid state. Cancelled payment, removed only the temporary item, verified
zero items/THB 0, and restored the sales channel chooser. No actual shop sale,
stock adjustment, cash-round entry or real debit was submitted.

Local ignored evidence: `.remember/tmp/omise-native-test-start-20261114.json`,
`omise-native-promptpay-qr-20261114.png`,
`omise-native-promptpay-success-20261114.png`,
`omise-native-promptpay-failure-20261114.png`,
`omise-native-cart-preserved-20261114.png`, and
`omise-native-cart-cleaned-20261114.png` in the same scratch directory.
Backend results are in `.remember/tmp/omise-deployed-test-results.json`.
Raw captures may contain the signed-in account, so are not tracked/public assets.

Scope: this proves the native Android sandbox entry/return and two PromptPay
outcomes. The next pass extends native coverage to card and TrueMoney. Neither
pass proves iOS, live payments or completing the real POS cart through Omise;
the sandbox deliberately cannot settle that cart.

## Native card and TrueMoney follow-up — 2026-11-14

Completed the owner's requested tests on the same installed Android app
1.2.78 (95), using the authorized test-shop session. Started from the native
takeaway payment sheet, then its separate THB 100 sandbox. Each attempt opened
Android Chrome Custom Tab with its own native-generated identifier.

| Native-started journey | Native result on return | Backend confirmation (UTC) |
| --- | --- | --- |
| Official successful test card submitted in checkout | Automatically confirmed | 06:00:02.501 |
| TrueMoney TEST authorization page: paid | Automatically confirmed | 06:03:58.263 |
| New TrueMoney attempt: failed | Payment failed; order unconfirmed | No confirmation timestamp |
| Official insufficient-funds test card | Payment failed; order unconfirmed | No confirmation timestamp |

The failure card is from the provider's [official testing documentation](https://docs.omise.co/api-testing).
All card and wallet details used were provider test fixtures. Browser prompts
to save test cards were declined; no saved real payment instrument was selected.

Closed Custom Tab using its X control after each outcome. Every native screen
displayed the result for the same original identifier automatically, with no
manual refresh, login or Subscribe redirect. Exact-ID backend read-back after
the fourth test verified all four attempts had testMode true, amount 10000
satang, THB currency and the expected method/status/orderStatus. Both failures
had no confirmedAt value. The TrueMoney failure attempt was created at
06:05:21.738 UTC; the card failure at 06:10:52.885 UTC.

Actual provider webhook requests returned HTTP 200: card success at
06:00:02.605 UTC, TrueMoney paid at 06:03:57.990 UTC, TrueMoney failed at
06:05:50.193 UTC and card failure at 06:10:53.754 UTC. Card confirmation may
also be reconciled from its synchronous create response; these timestamps do
not imply its webhook was the first confirmation path.

Returned to the native payment sheet and verified the original one-item THB 80
cart stayed unpaid and intact. Cancelled payment, removed only the temporary
item, verified zero items/THB 0, and restored the sales channel chooser.
No actual shop sale, stock adjustment, cash-round entry or real debit was submitted.
This pass required no code changes, APK, Hosting or backend deployment.

Local ignored screenshots in `.remember/tmp/`:

- `omise-native-card-success-20261114.png`
- `omise-native-card-failure-20261114.png`
- `omise-native-truemoney-success-20261114.png`
- `omise-native-truemoney-failure-20261114.png`
- `omise-native-card-wallet-cart-preserved-20261114.png`
- `omise-native-card-wallet-cart-cleaned-20261114.png`

Together with the earlier native PromptPay pass, success and failure are now
verified for all three sandbox channels on physical Android. This verifies
app entry, provider TEST handling and automatic native status on return; it
does not establish iOS behavior, Live Mode readiness or settlement of a real
POS cart. The previously documented transient label during new-attempt creation
remains a separate UI follow-up.
