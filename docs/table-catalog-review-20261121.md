# Table catalog / payment presentation — local review

Scope: the full-page table product picker, selected table name, centered tablet
dine-in payment, and their fixtures/tests against `aeee5fc`. This is a feature
review; no mobile release, installation, real payment or production write was
performed.

## Independent review and disposition

Three fresh ephemeral Codex CLI sessions used `gpt-6.2-sol`, `xhigh`, read-only
sandbox, `--ignore-user-config` and `--ignore-rules`. Grok and Claude CLIs were
unavailable. No MCP/connectors or inherited builder conversation were supplied.
Repository/global instruction files can still load with these flags. Later
rounds cover only the follow-up changes, with the original change as context.

- Round 1 identified an enabled-looking Back button during save. Replaced the
  fallback-enabled `BackButton` with an explicitly disabled `IconButton`, retaining
  the platform back icon, localized tooltip and existing `PopScope` safeguards.
  The pending-save regression checks the actual button callback is null.
- The Core-only test fixture's Auth path was raised in round 1. The existing
  run had passed, but the tests now use an explicit signed-out Auth platform
  fake as well as Core mocks. Firestore remains fake or callbacks are injected.
  Only the dependency classification changed for already-locked Auth 7.7.3 and
  Core 6.0.3 interfaces; no package version/checksum changed.
- Retaining a payment route across rotation is intentional, preserving typed
  cash. Added tests for both directions across the 600 px breakpoint, with
  keyboard inset, checking entered cash and the resulting dine-in payment.
- Round 2 found no new production-code defect, but correctly noted that a fake
  keyboard does not intercept Flutter test taps. Strengthened both rotation
  cases to check the intended tap point is above the logical keyboard top and
  hit-testable after scrolling/layout. Both strengthened cases pass.
- Round 3 checked only this final assertion block and found no substantiated
  defect. It verified matching logical coordinates, the post-rotation keyboard
  boundary, settled scrolling, and that the checked and tapped points coincide.

## Operator verification

- Four focused suites: **60 tests passed** (`table_product_picker`,
  `payment_journey`, `sale_display`, `table_promotion_ux`). The two rotation cases
  passed again after strengthening the keyboard position assertions.
- Targeted analysis of eight changed Dart files: no issues. The final extra
  test assertions compiled and ran in the subsequent two-case check.
- Actual Flutter widget previews rendered and checked at 1480, 768 and 390
  logical px, with synthetic products and the existing Thai font/theme.
- `git diff --check` passed. Existing draft confirmation, frozen retry request
  handling, cash/transfer calculations and backend write methods are retained.

Real-device interaction, a complete catalog-to-backend-to-payment transaction,
and payment providers were not tested. The connected tablet still runs
1.2.80 (97). Previously captured tablet footage shows the old catalog popup.
