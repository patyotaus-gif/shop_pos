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
2. Gate: pending release rerun of seven relevant existing suites and analysis.
3. Independent review: pending fresh isolated read-only source review.
4. Build: pending signed APK in `D:/pokpok-release-1.2.82/source/` using the
   existing ignored key; verify app ID, version, signer, ABIs and source inputs.
5. Device: pending data-preserving install and read-only visual/navigation smoke
   on the connected SM-X900. No real sale, table save or payment is required.
6. Publish: pending exact-two-file Hosting preflight, source push, Hosting-only
   deploy and direct public APK/manifest readback. Preserve the live homepage.

Evidence/logs and private device captures stay outside Git under
`D:/pokpok-release-1.2.82/`. Current public Android is still 1.2.81 (98).
