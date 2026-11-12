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

## Current state (updated 2026-11-12)

**Branch:** `master`. Denser desktop homepage (branch `website-desktop-density`) merged; see the Log for its deploy status.
Android 1.2.76 remains the artifact released from commit `1913e1c`.

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

**Live app (released 2026-11-11):** Android **1.2.76 (build 93)**, served at
`pok-pok.app/app/version.json` (sha256 `afb8f92f…a9ad`, 97,532,155 bytes, signed
with the release key `f7dc70e0…`). New website screenshots are also live.
Website rollback: `4f04f89cb357738d`. Functions `tablePromotions`, `staffWork`,
`staffCheckout`, `createRefund` remain at their 2026-11-10 deployment;
this release changed no Functions, rules or payment/security settings.

**Test tablet (SM-X900):** installed and verified **1.2.76 (93)** on 2026-11-11.
Kitchen table tickets have no bill shortcut; table billing remains reachable
from Sales > dine-in > table. Fresh website screenshots retain their real capture
version, 1.2.75 (92); the only app UI change is outside those screenshots.

**App release verification (2026-11-11):** downloaded the live APK and checked its size/hash against
the signed, device-tested artifact; live version.json and all 10 changed website
HTML/image files match local bytes. Source review, focused checks, signed APK
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
  Still to do: 3–4 feature blocks with real screenshots (follow the latest
  owner-approved naming direction in `docs/website-development-core.md`),
  separate `/retail/` and `/restaurant/` pages, real shop photography.
- Website direction: owner approved the ten-part brief in
  `docs/website-development-core.md` on 2026-11-11. Read it before website work;
  it is the target direction, not a claim that all ten parts are implemented.

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

### 2026-11-12 — Denser desktop homepage (owner approved release)

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
