# Android 1.2.81 (98) — table sales workspace

Owner authorized publication on 2026-11-21 after viewing the local Flutter
previews. Candidate source starts from `b0f7ac1`; the last published Android
source is `372a8ab` (1.2.80 / 97). Root `master` is the source branch; Firebase
Hosting is an explicit deployment. This release publishes Android APK and its
update manifest; iOS uses the separate manually triggered Codemagic workflow.

## Scope and release progress

- Table **เพิ่มสินค้า** opens the shared takeaway catalog/cart workspace.
  **ชำระเงิน** saves the draft once and opens the existing centered tablet payment
  popup over the sales page. Phones keep the shared compact catalog/cart flow.
- Includes previously committed settings category alignment and consistent
  tablet category-button widths. No backend, rules, payment mode or provider
  configuration change is required.
- Live Hosting baseline verified: `18b6c596b2d82616`, 79 files, no local public-file
  drift before staging. Only `/app/pokpok.apk` and `/app/version.json` may change.
- Build inputs are copied to `D:/pokpok-release-1.2.81/source`; signing continues
  with the existing ignored release key. Artifacts, private device captures and
  logs stay outside Git under `D:/pokpok-release-1.2.81/`.
- Final release gate: **131 tests in 18 suites passed**, exit 0. Targeted analysis
  of 11 changed production Dart files and the new regression fixture passed,
  exit 0. Logs: `tests-final.log`, `analyze-final.log` in the evidence directory.
- Source review covered the entire native-client range from `372a8ab`; two
  follow-ups reviewed the cash-close fix and staging checks. Fresh ephemeral
  read-only `gpt-6.2-sol` xhigh was used because Grok/Claude CLIs were unavailable.
  Final follow-up found no material introduced failure.
- Initial source review found that cash-close table entry disposed the catalog
  callback owner on a failed poll. It now retains the keyed table state through
  retryable errors, blocks new catalog saves while error is present, and resumes
  after a valid record. A follow-up retained the previous explicit raw `open`
  status requirement; unknown/missing/closed records expose no active view.
- Both regressions were reproduced against their broken implementations before
  the final green gate (`cash-close-baseline-red.log`, `cash-status-red.log`). An
  initial fixture also asserted route disposal after an arbitrary 300 ms; that
  timing assertion was removed while keeping same-state/no-write/save assertions.
- The staging script's app-id and version regex now requires literal periods.
  APK source-input, signer, version/ABI and final live-byte checks remain separate
  operator checks; static review alone is not artifact verification.
- The initial signed build succeeded; the build including cash-close recovery
  is running. SM-X900 still reports 1.2.80 (97) until installation verification.

## Retained limitations

The two Low recovery limitations in `table-takeaway-review-20261121.md` remain
explicit: an already-open payment dialog can finish the same still-valid bill
after a background stream error, and reversed independent staff poll/read
responses can temporarily show an older cart. The backend still validates bill
identity, signature/revision and total; the draft write remains idempotent.
No claim of multi-device or real-payment acceptance is made. The pending trigger
for a shared backend revision is the next multi-device synchronization change or
a field report of stale carts, rather than adding client arrival-order guesses
to this presentation release. Automatic authoritative quote sync stays enabled.
An open catalog also keeps its current existing-lines baseline while another
cashier changes that bill; returning to details refreshes it. This display-only
case was rated Medium by source review and retained as Low after verifying no
lost write or incorrect charge. Terminal permission/record errors that cannot
recover require reopening or repairing the session; automatic retry recovery is
for transient network errors, not a promise to bypass terminal failures.

This file will record build, signature/device evidence and live readback before
the release is reported complete. Hosting rollback uses the unchanged previous
version above; it restores download/manifest availability, not already-installed
Android clients (those require a higher build number).
