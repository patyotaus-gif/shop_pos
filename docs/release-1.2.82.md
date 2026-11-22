# Android 1.2.82 (99) — sales color hierarchy

Owner explicitly authorized release on 2026-11-22 after the actual Flutter
previews. The change keeps ordinary prices and secondary sales actions neutral
while totals and primary actions retain the existing brand accent. Both light
and dark themes use existing theme tokens. No calculation or data-flow changes.

Root `master` is the source branch; Firebase Hosting is deployed explicitly.
This release updates the signed Android APK and its manifest at
`https://pok-pok.app/app/pokpok.apk`. No iOS/backend release is included.

## Release run

1. Source: bumped to 1.2.82+99. Previous Android 1.2.81/98 was built from
   `a602c8d`, published with `2fa94e1`. Native inputs did not change between that
   release and the reviewed/deployed website source `9291481`; current native
   delta is six sales widgets plus the new version.
2. Gate: final rerun passed all 62 cases in seven existing sales/catalog/table/
   checkout suites. Targeted analysis of all six changed widgets found no issues.
   Actual Flutter light/dark previews were regenerated after the focused-label
   adjustment; these use synthetic data at 1440/768/390 logical pixels.
3. Independent review: fresh Codex CLI processes, read-only, ephemeral, no user
   config/rules, MCP or inherited build conversation; `gpt-6.2-sol` at `xhigh`.
   Grok and Claude were unavailable, so Codex was the fallback. The full native
   unreleased range was reviewed, then the follow-up delta. The focused-label
   contrast issue was fixed with `onSurface`; follow-up found no Dart regression.
   Operator follow-ups covered source/config/receipt/PowerShell launch guards.
   All applicable findings are resolved; see dispositions below for the
   unsupported custom-caller finding in the final round.
4. Build: signed APK built successfully from pinned native source
   `fbcf582f379a9ce98ef329d20b3a068077623765` in
   `D:/pokpok-release-1.2.82/source/`. Package `app.pokpok.pos`, version
   `1.2.82`, build `99`; release certificate matches the existing signer.
   All three ABI app libraries differ from published build 98. The final APK
   also differs from the earlier candidate made before the focused-label fix.
   422 native inputs match the pinned Git blobs; drift and extra-manifest
   rejection probes passed. Successful-build receipt and staging validation
   passed; the final rebuilt artifact is identical to the tablet-tested APK.
5. Device: data-preserving install succeeded on the connected SM-X900; package
   readback confirms 1.2.82/99. Launch, takeaway catalog and display-controls
   dialog passed; prices/settings/quantity are neutral while total/checkout
   retain the accent. Added one item to the local in-memory cart, increased its
   quantity to two, removed it and confirmed an empty cart. No checkout, table
   save or sale write. Physical smoke used light mode; dark and phone layouts
   were covered by synthetic Flutter captures/tests.
6. Publish: exact-two-file Hosting preflight passed against 92 live files, with
   CLI-resolved headers/rewrites equal to the live baseline. Source push,
   Hosting-only deploy and direct public APK/manifest readback remain pending.

Evidence/logs and private device captures stay outside Git under
`D:/pokpok-release-1.2.82/`. Current public Android is still 1.2.81 (98).

## Review dispositions and scope

- Fixed operator checks for source drift, unexpected native inputs, Thai release
  note encoding, and Hosting configuration. The official installed Firebase CLI
  resolves the local configuration against existing backends; it matches the
  live baseline before publication. Staging requires a successful pinned build
  receipt containing the APK digest.
- The warning that removing the ignored Gradle wrapper JAR would block staging
  was rejected as a release defect: staging should fail if a required verified
  input disappears. Both copies exist and match on this release machine.
- Fixed PowerShell launch detection and verified success, nonzero exit and
  command-not-found behavior from a script. The final reviewer described a
  custom caller that explicitly creates a nearer `LASTEXITCODE` variable. That
  caller is not used here: operator commands run in fresh PowerShell processes,
  without a caller-local override of that automatic variable. Rejected as a
  blocker for this release, not claimed to support arbitrary wrapper scopes.
  The real build exited zero, logged the completed Flutter build, passed both
  source checks, and produced the independently inspected/tablet-tested digest.
- Existing Kotlin incremental-cache cross-drive warnings used the compiler
  fallback during the first build; it completed successfully. No dependency,
  Flutter SDK, backend, payment mode or security policy was changed.
- Source review is static; widget captures and physical-device checks are
  separate evidence. No whole-app accessibility or payment certification claim.

Rollback baseline: Hosting version `9703c7514cedaa31` (current homepage plus
Android 1.2.81/98). Only `/app/pokpok.apk` and `/app/version.json` may change in
this publication; all other 90 hosted files and Hosting config must match.

Candidate artifact: 93,116,248 bytes; SHA-256
`3d672c9a665b5f179cfb65c83ca04da6dd8a450efd53914285b9f2af7aaf2062`.
