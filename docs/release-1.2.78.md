# Android 1.2.78 (95) and website refinement

Owner authorized implementation and publication on 2026-11-13. In preparation;
not yet live. Previous Android is 1.2.77 (94). Hosting rollback baseline is
`cb06af000098f85d`. Release subject is all source after `17fd271` plus this change.
Master is the source branch; Firebase Hosting is deployed explicitly by CLI.
Release source commit: `7c67501`. Preflight verified exactly eight expected public
path changes against the rollback version; runtime rewrites remain unchanged.

## Changes

- Restaurant sales starts with dine-in/takeaway selection. Visited workflows and
  cart stay mounted when switching; retail opens the catalog directly.
- Search, categories and favorites share one catalog; display settings and
  secondary bill actions move into menus. Cashier identity, recovery notices,
  customer/points and payment remain accessible. See `ui-layout.md`.
- Homepage and pricing page use three bounded white cards, stronger feature
  hierarchy, clear plan inheritance and user limits. Prices remain unchanged.
- Pale rose mortar curves behind the actual app screenshot and a pale rose price
  band add brand character. Only the device image enters once, with reduced-motion
  support. No new image assets, third-party libraries or continuous animation.

## Verification and publication checklist

- [x] Repository destination verified as `patyotaus-gif/shop_pos`; no remote-only commits.
- [x] Pricing browser gate: 56 states, seven widths, both routes, shop types and
  billing cycles; keyboard, 200% text, contrast, forced colours and trial links.
- [x] Hero/pricing captures at 1440, 768, 390; no overflow, reduced-motion and
  one-shot entrance checked with local browser. Real screenshot remains fully visible.
- [x] Marketing regression gate: 18 pages × five widths; links/assets, menus,
  headings, guide search, FAQ, no-JS content and overflow passed.
- [x] 53 focused app tests across eight files; targeted analysis of 13 Dart files
  reported no issues. All ran again in this release session.
- [x] Fresh isolated source review of the whole outgoing range: clean, no verified
  blockers. Separate screenshot review: no definite hard blocker; optional polish below.
- [x] Signed APK built from isolated native input copy; all 406 inputs match.
  Package/version, three ABIs and existing signing certificate verified.
- [x] Final metadata review clean after one deployment-helper fix and regression check.
- [ ] Clean reviewed source committed and pushed; remote SHA read back.
- [ ] Hosting file/config preflight; explicit `shop-pos-89294` deployment stamped with commit.
- [ ] Live file hashes, APK download and version manifest verified.

ADB currently lists no device. Physical-device validation is not claimed.
No backend, payment/security configuration or customer data change is required.
This local Windows build publishes Android; iOS/TestFlight needs its existing
Codemagic workflow and is tracked separately, not inferred from a Git push.

Evidence: `D:/pokpok-release-1.2.78/`; local website captures:
`.remember/tmp/background-20261113/`.

Artifact: 92,469,169 bytes; SHA256
`5db45df2aac60b3eed6fadbd98c9aa99e06a8bf1d4b75287100023e60754d951`.
The initial PowerShell wrapper terminated on a native compiler deprecation
warning. An incremental rebuild captured stdout/stderr separately and returned
actual Flutter exit 0 (40.3 seconds); staged artifact checks used that output.

Metadata review round 1 found one stale-preflight guard issue in the local
deployment helper. The helper now invalidates saved success, runs preflight
synchronously inside deployment, and verifies its commit. A simulated failed
preflight blocks the upload despite older success; successful fresh checks permit
it. Round 2 independently reviewed the helper delta and was clean. These checks
do not deploy or modify app/backend behavior.

Visual review: isolated, ephemeral read-only Codex CLI (fallback after Claude's
previous usage limit), screenshots only. No definite hard blocker. Plan comparison
on stacked mobile cards, larger-image inspection, and fuller TestFlight/printing
guidance are optional follow-ups; existing full-image link and guides remain.
Plan selection happens explicitly during app signup as stated beside the cards.
The screenshot reviewer saw retail/monthly; the browser gate independently tested
both types/cycles. Scoped design score 18/20: accessibility 3, performance 3,
theming 4, responsive 4, integrity 4. This is not a full WCAG/PageSpeed certification;
no physical keyboard, screen-reader or device pass is claimed.
