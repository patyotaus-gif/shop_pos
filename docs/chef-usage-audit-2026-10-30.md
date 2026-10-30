# Chef workflow audit — 2026-10-30

## Fixes released in Android 1.2.65+82

- Paid table orders remain in the chef queue until sent food is ready, even after drawer closing or reuse of the same table. Ready writes now use the authorized server operation for both owners and staff. Repeated readiness writes preserve the first actor/time and do not change stock, prices, sales, or table occupancy.
- Staff kitchen reads include legacy unfinished paid bills with pagination. Initial/ten-minute reconciliation checks historical rows; normal polls reread open work, recent closures, and known unfinished paid IDs rather than downloading all historical bills every five seconds. Overlapping closure timestamps protect commit boundaries; malformed cursors/IDs and more than 500 active kitchen bills produce explicit errors.
- Tickets grow with their content and use the page's scroll area. Current table/online work is ordered together; ready work is separate, and future-day paid pickups are collapsed under their own section. Thai midnight moves scheduled work into the current section automatically; work already accepted stays active.
- Read-only staff streams retry transient errors with a delay capped at 30 seconds and a 20-second request timeout. Cancellation and account changes discard late results; permission errors stop polling. Kitchen errors hide stale actions and provide retry, while preserving the other stream subscriptions during recovery. No write is automatically retried by this helper.
- Added regression coverage for paid unfinished food, reused tables, duplicate readiness, gift/modifier preservation, 500 historical rows, authorization/revocation, large Thai text, future-day grouping, reconnection, timeout and stale responses. The two originally failing edge probes now pass. See release notes in `android-user-feedback.md` for publication status and final checks.

The findings below record the original audit before these fixes.

Scope: user requested testing as a chef and selected simulated data. No production sales, stock, settings, staff accounts or kitchen statuses were changed in this audit. The connected SM-X900 (build 81) showed the owner's empty kitchen screen; this was not a physical chef login. Role enforcement was tested using an isolated Firestore emulator and kitchen staff claims. UI interaction used the actual KitchenScreen with injected streams and a fake database.

## Findings

### High: closing a table bill removes unfinished cooking

- Reproduced with a sent kitchen item, then a successful cashier close/payment while the item remains `sent`.
- Screen mode filters out closed table orders. The staff queue endpoint also returns only open table orders, so the chef loses the task entirely.
- Attempting to mark that item ready after payment is rejected by the backend because the bill is closed. Merely displaying the card again would not fix the workflow.
- Both UI regression probe and emulator scenario reproduced this. The emulator confirmed `status=closed`, the item still `sent`, absence from the staff queue, and rejection of the ready action.
- Suggested fix: track kitchen completion independently of payment. Preserve pending cooking after payment and allow a narrowly scoped, authorized ready transition on the original item without reopening the table or changing amounts/stock. Keep cancelled orders distinct; audit the actor and make retries idempotent.
- Relevant code: `lib/screens/kitchen_screen.dart` eligibleTables / editable, `lib/services/table_service.dart` watchKitchenOrders / _edit, `functions/staff_work.js` tableOrders query and ready-action guard.

### Medium: ticket header can displace all food rows

- Reproduced at 320×568 logical pixels with 2× text and a long Thai table name using the bundled IBM Plex Sans Thai font.
- The fixed 360-pixel table ticket overflows vertically by 55 pixels. The header consumes the space intended for the item list.
- Suggested fix: remove the fixed-height assumption or make the entire ticket scroll safely, with a clear reachable ready action and readable full table identification.

### Workflow improvement: future online orders precede current table work

- The screen renders all eligible online orders before any table tickets. A paid order for tomorrow therefore appears before a table currently waiting for food.
- This ordering was confirmed in the source and simulated layout; it is a prioritization problem, not a missing-order defect. Pickup labels are shown when present in the saved order.
- Suggested fix: separate current work from future appointments and completed/ready work. Order current tasks by a deliberate preparation priority, retaining pickup time and source/table identification.

### Reliability concern from source review: staff polling has no recovery loop

- `StaffAccessService.watch` fetches then waits five seconds. A thrown callable error exits the async generator; it does not automatically retry after the connection returns.
- KitchenScreen shows a load-error message asking the user to reopen the screen. Recovery during an actual network outage has not been tested on a signed-in physical chef device.
- Suggested follow-up: test transient loss/reconnection; add bounded retry and a visible retry/stale-data state without treating unknown writes as failures safe to duplicate.

## Passing checks

- Existing kitchen/output and staff-permission widget suites: **15 passed**.
- New `test/kitchen_chef_journey_test.dart`: **5 passed**. Live queue arrival/removal; allergy note and modifiers; actual table ready tap through the service into fake Firestore; no sale creation or stock mutation from ready; online lifecycle presentation; last item reachable in a 20-item ticket on a 1480×924 tablet in both themes.
- Existing `functions/staff_work.integration.cjs` completed successfully in an isolated emulator for cashier, waiter, kitchen and manager. It covers table send/ready, online accepted→ready→completed, prices, duplicate requests, actor attribution, restricted operations, permission changes and revocation.
- Dedicated close-before-ready emulator probe reproduced the high-priority finding and exited successfully after asserting the observed defect. Its inherited final summary text names four positions, but this dedicated probe deliberately runs kitchen only; the original suite separately ran all four.
- Edge probes: **two expected failures** (unfinished task disappears; large-text overflow), plus two successful tablet renders. The passing baseline tests do not mean these defects are fixed.

## Evidence and limits

Local evidence: `.remember/tmp/chef-existing-widget-tests.log`, `chef-journey-tests.log`, `chef-staff-integration.log`, `chef-close-integration.log`, `chef-edge-tests.log`, `chef_edge_audit_test.dart`, and `chef-tablet-light.png` / `chef-tablet-dark.png`. UI images are simulated widgets, not screenshots of a logged-in chef. Test-rendered icon glyphs may differ from the installed application.

No kitchen production code was changed or deployed during this audit. The earlier pending tablet-width changes remain separate. Physical chef login, reconnect behavior, audible notifications and physical kitchen printing remain unverified.
