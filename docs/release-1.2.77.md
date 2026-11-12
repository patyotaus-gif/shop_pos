# Android 1.2.77 (94)

Prepared 2026-11-13. Owner authorized release; publication pending.

## Changes

- Optional name-only product buttons beside the existing photo view in sales,
  table selection and offline entry. Five category colors and reset; preferences
  are scoped to this shop/device. Cart and sales rules remain unchanged.
- Kitchen display and printer tickets use bounded columns on tablets; history,
  guidance and print controls no longer stretch across the workspace.

Source: sales `f1427dc`, kitchen `c097378`, release prepared from `fc97d2b`.
Only the APK and version manifest change in Hosting. Website content, backend,
payment mode and security enforcement are unchanged.

## Verification

- 68 focused sales/display/offline/table/kitchen tests passed; targeted Dart
  analysis reported no issues.
- Prior visual fixtures cover phones/tablets, light/dark and 200% text. Fresh
  isolated source and release-metadata reviews completed with no confirmed defect.
- Clean source matches all 260 tracked native input files (ignoring line endings).
  Signed release build passed; all three ABIs contain libapp.so/libflutter.so.
  Package version and signing certificate match the intended release/previous key.
- Installed on SM-X900. Cold start, preserved login/shop, both sales modes,
  category colors, cart retention and preferences after restart passed.
- Display/printer kitchen views checked with existing test orders. Temporary
  output-mode setting restored. Test cart cleared and photo/default color restored.
- No physical printing, new payment/checkout or physical iOS test in this release.
  iOS/TestFlight is not built or triggered by this Android publication.

An earlier local build after relocating generated files lacked libapp.so and
crashed at startup. It was rejected and never published. The accepted APK comes
from an isolated clean build on D; normal local build-directory behavior restored.

## Artifact and publication

- Size: 92,403,745 bytes.
- SHA-256: `045d56ca6d6b191be45dc0ae52f0db73bceb7a4af7a69f65db8c0f722266d9b6`.
- URL: https://pok-pok.app/app/pokpok.apk
- Manifest: https://pok-pok.app/app/version.json
- Previous Android: 1.2.76 (93).
- Hosting rollback target: `b362e6435d006aad`.
- Release source `2d1cbce` pushed to master and remote SHA verified.
- Hosting preflight passed: only APK and version manifest differ from live.
- Hosting deployment and public download verification: pending.

Local evidence: `D:/pokpok-release-1.2.77/` (test/analyzer logs, isolated reviews,
clean build log, APK validation, tablet screenshots/XML). Device captures remain
local and are not added to marketing assets.
