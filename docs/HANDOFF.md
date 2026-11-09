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

## Current state (updated 2026-11-09)

**Branch:** `gif-feedback-2026-11` on top of `d29153f` (master), pushed to GitHub.
Not merged; nothing deployed or released from it. Release in progress: review round 4 next.

**Live:** Android 1.2.74 (build 91) from `d29153f`, served at
`pok-pok.app/app/version.json`. Functions on production are the pre-branch versions.

**Test tablet (SM-X900):** runs a build of this branch, labelled 1.2.74 (91),
signed with the release key. The owner's test shop is logged in.

### Must do before releasing this branch
1. Deploy Functions first: `tablePromotions`, `staffWork`, `staffCheckout`, and the
   refund callable (`createRefund`, implemented in `functions/refund.js`). The app
   calls new server actions (`bill`, `loyalty`) and relies on the refund fix.
2. Bump `pubspec.yaml` to 1.2.75+92, build the release APK, then follow the
   self-hosted release steps (copy APK to `public/app/`, update `version.json`,
   deploy hosting). Copy the APK before deploying hosting.
3. Every step needs the owner's go-ahead.

### Review backlog (round 1, Low, accepted for this release)
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
- Pre-existing: if the typed debt phone matches nobody, `ensureByName` falls back
  to an exact name match and drops the phone (same-name customers merge).
- L3 part not fixed: counter redemption maximum ignores bundle discounts;
  checkout still blocks a negative total.

### Known issues and leftovers
- **Live bug on 1.2.74:** refunds started from the sales report do nothing
  (fixed on this branch in `0de7903`). Refunds from the receipt screen work.
- Test data left in the owner's test shop: loyalty customer `TEST-CLAUDE`
  (0990000001, 0 points) cannot be deleted from the app. Three test sales from
  2026-11-09 are refunded. Loyalty rate was restored to 10 points = ฿1.
- Because production `createRefund` is still old, refunding a bill that redeemed
  points does not return those points until Functions are deployed.
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
