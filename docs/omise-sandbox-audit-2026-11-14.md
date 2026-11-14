# Omise sandbox audit — 2026-11-14

Scope: inspect and test the existing sandbox. Source baseline: `55d187e`.
No application/backend code change or deployment was made during this audit.
No real sale, stock change, live payment or security-enforcement change occurred.

**Update after owner-authorized correction:** the defect below is now fixed and
verified locally. It is **not deployed**. The original audit evidence is preserved
below; see the final correction section for current results and remaining checks.

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

**Release status:** local code/docs only; no push, backend deployment, app build,
mode change or App Check change. The deployed backend still has the original
predicate. Before claiming tablet payment completion, deploy the scoped backend
fix, verify authenticated polling and actual provider webhook delivery, and run
the three isolated sandbox journeys on the device. Do not use real shop sales or
enable Live Mode for these checks.
