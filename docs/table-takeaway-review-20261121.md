# Table sales workspace review — 2026-11-21

The owner rejected the first full-page picker (`5b8557d`) and requested the
same sales screen as takeaway. This revision reuses the shared catalog, basket,
display settings and checkout controls. New items remain a draft until the
existing idempotent table batch operation saves them. Pay then opens the table's
existing confirmed-quote payment popup over the sales screen.

## Independent review record

Fresh ephemeral Codex CLI reviews used `gpt-6.2-sol` with xhigh reasoning,
read-only sandbox, ignored user config/rules, and no builder conversation.
This was the available CLI fallback; the reviewers only read source and fixtures.
Generated documentation and images were context, not review subjects.

Round identifiers here are `table-takeaway-20261121-1`, `-2` and `-3`; they are
distinct from the superseded catalog review in `table-catalog-review-20261121.md`.

| Round | Findings | Resolution |
| --- | --- | --- |
| 1 | High: draft callback can follow a replacement bill; Medium: stale poll/timeout replies overwrite confirmed state; Medium: stream error disposes the callback owner; Medium: search omits notes; Medium: quantity dialog result is lost on row insertion/rotation; Low: receipt leaves an extra detail route. | Bound bill/session checks, deferred active-session polls and read generations, retained keyed table state, notes in search, quantity editor owned by stable page/item ID, correct receipt route removal. Covered by focused flow/recovery tests. |
| 2 | Medium: a conflicting-order stream error leaves cached bill writable; Medium: a late return read can overwrite a newer detail snapshot. | Any order-stream error now preserves the draft but blocks new catalog save/checkout attempts until recovery and shows the actual error. One order epoch replaces the save-only epoch and covers accepted detail snapshots, catalog entry, save/retry and return-read results/errors. Regression fixtures cover both cases. |
| 3 | Reported High: already-open payment can finish after stream error; Medium: automatic quote sync continues during error; Medium: a stale poll accepted on return can supersede a newer read. | Manual triage below retains the first and third as Low recovery limitations and accepts continued quote sync. No wrong-bill/amount or duplicate payment was demonstrated. No further implementation changes after this round. |

Reports remain outside Git at `D:/pt/table-takeaway-review.md`,
`D:/pt/table-takeaway-review2.md` and `D:/pt/table-takeaway-review3.md`.
Each substantive review's source reads and findings are checked by the operator.

## Final triage and retained follow-up

The final review is not described as an empty report. Its mechanisms are real,
but the assigned severities exceed the demonstrated user consequence:

1. **Low — payment dialog already open when an order-stream error arrives.**
   An error on the underlying route does not dismiss that dialog. Confirming
   still submits the bill the cashier chose. The server checks the bill is open,
   `table.currentOrderId`, promotion signature/revision, expected amount and
   payment values (`functions/table_promotions.js:133` onward), and closing an
   already-closed bill returns its existing sale ID. A legacy duplicate open tab
   does not let this close a replacement bill or charge a different amount.
   The remaining discrepancy is between the background error and the dialog's
   availability. Revisit explicit dialog invalidation before changing payment
   recovery or accepting a rollout for shops with conflicting legacy tabs.
2. **Accepted behavior — automatic quote maintenance during stream error.**
   The retained controller can run `ensure(send: false)`. Its server-side `sync`
   validates the same active bill pointer and recalculates current promotion
   data; it neither sends kitchen lines nor creates a sale or deducts stock.
   A stream error is not a blanket suspension of all server-validated work.
   Keep this distinction in the docs; revisit only if product policy requires
   all quote maintenance to pause during connectivity/reconciliation errors.
3. **Low — reverse ordering of independent staff poll and return read.**
   A poll that read before the batch save but arrives after return starts can
   replace the visible detail snapshot and invalidate the return read. The batch
   is still persisted exactly once. The next poll corrects details; immediately
   reopening the catalog before that poll can temporarily show the old cart,
   requiring Back/refresh. This does not silently remove saved products or
   bypass the payment quote checks. Revisit before multi-device restaurant
   acceptance, preferably using a shared backend revision for list/read results
   rather than more client arrival-order flags.

Adding separate timers, invalidation listeners and revision guesses for these
cases would make a presentation change substantially harder to maintain without
establishing true cross-request freshness. This local change stops at the
bounded session guard; it is not a claim of production/device release readiness.

## Local validation

- All **105 tests in 11 suites passed**, including table picker, sale display,
  payment journey, table promotions, table sales flow/recovery, product image,
  product catalog, shared sales workspace, checkout panel and basket checkout.
- Targeted `flutter analyze` of the six changed implementation files and four
  changed/new test files passed with no issues. `git diff --check` passed.
- The recovery cases include a true simulated 25-second timeout followed by a
  late reply, original/replacement bill isolation, draft retry after stream
  error, newer-snapshot preservation on return, quantity editing across a layout
  change and receipt-to-table-selection navigation.
- Actual Flutter widgets were rendered and visually checked at 1480 and 390 px
  using synthetic products. See [sales preview](previews/table-takeaway-sales-20261121.png)
  and [payment popup](previews/table-takeaway-payment-20261121.png).
- Gate logs: `D:/pt/table-sales-gate-final.log` and
  `D:/pt/table-sales-analysis-final.log`; visual log:
  `D:/pt/table-takeaway-visual.log`.

Existing saved lines remain read-only in this sales workspace and editable in
table details. New selections support quantity, weight, modifiers and notes.
The workspace labels its amount as product subtotal; the payment popup uses the
authoritative promotion/service/loyalty total. Incoming background polls are
deferred while the sales page is open, with fresh reads for save/payment/return.

At this pre-release review, no APK build, tablet installation, real transaction,
payment provider change, backend deployment or public release was performed.
The tablet then ran 1.2.80 (97); earlier recordings show the old product popup.
Subsequent build, device and publication evidence is in [release 1.2.81](release-1.2.81.md).
