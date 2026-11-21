# Android 1.2.81 (98) — table sales workspace

Owner authorized publication on 2026-11-21 after viewing the local Flutter
previews. Candidate source starts from `b0f7ac1`; the last published Android
source is `372a8ab` (1.2.80 / 97). Root `master` is the source branch; Firebase
Hosting is an explicit deployment. This release publishes Android APK and its
update manifest; iOS uses the separate manually triggered Codemagic workflow.

## Scope and verification

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
- Final signed build from `a602c8d` passed, exit 0. All 422 native source inputs
  match the isolated build copy after normalizing line endings; tracked credential
  and signing-file scan covered 1,136 paths with zero matches.
- APK: `app.pokpok.pos`, 1.2.81 / 98, **93,116,248 bytes**, SHA-256
  `4546aeb0a2612c75bdc21d47d9ca42cbd328a861484a9c3cc2be56f86306aae2`.
  Signer matches build 97. arm64-v8a, armeabi-v7a and x86_64 libraries exist;
  each compiled `libapp.so` differs from the old release. Evidence: `artifact.json`,
  `native-code.json`, `source-verified.json`, `build.log`.
- Installed via `adb install -r` on Samsung SM-X900, retaining app data. Package
  readback reports 1.2.81 / 98. After the owner unlocked the screen, table entry,
  full catalog/cart, local draft selection, quantity 1 to 2 and Back/discard passed.
  Original table lines, total and pending-kitchen count remained unchanged. Left
  the new sales page open with no draft. No real sale, kitchen send or payment
  was invoked; popup/payment behavior was tested with fixtures, not shop data.
  Native captures are in `device/updated-*.png` and XML outside Git.
- APK/manifest staging succeeded. Hosting preflight confirmed exactly the two
  allowed changed paths; all other 77 live files matched.

## Published release

- Release metadata/device evidence commit:
  `2fa94e13aaa950c81aa13a8ce83d7a6a85174feb`; pushed to `origin/master` and remote
  HEAD verified. Native inputs remain identical to source commit `a602c8d`.
- Deployment from that clean commit:
  `firebase deploy --only hosting --project shop-pos-89294 --non-interactive`
  with message `Pokpok 1.2.81 (98) 2fa94e13aaa950c81aa13a8ce83d7a6a85174feb`.
  Exit 0; live release at **2026-11-21 03:32 UTC**, Hosting version
  `sites/shop-pos-89294/versions/3e7b45bdbd61440b`.
- Post-deploy comparison: all **79 hosted file hashes match**, no drift, and
  deployment message identifies the release commit. Public version manifest
  reports 1.2.81 / 98. Full cache-busted APK download at **03:32:34 UTC** matches
  the exact size/hash above. Homepage and wordmark CSS match their existing files.
- Public download: <https://pok-pok.app/app/pokpok.apk>. No iOS release, backend
  deployment, payment-mode change or real payment acceptance is claimed.
- Evidence directory: `D:/pokpok-release-1.2.81/`, including `deploy.log`
  (`DEPLOY_EXIT=0`), `live-verification.json`, `git-2fa94e1.json` and
  `device-smoke.json`. Following documentation-only commits do not change the
  deployed artifact or require another upload.

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

Hosting rollback uses the unchanged previous
version above; it restores download/manifest availability, not already-installed
Android clients (those require a higher build number).
