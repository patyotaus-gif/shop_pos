# Accountant workflow audit — 2026-10-30

Initial audit scope: simulated accounting workflows against local source, with no production transactions or customer-data changes. Subsequent fixes shipped in **1.2.64+81 on 2026-10-30**, together with supplier and LINE contrast fixes; release evidence is in `android-user-feedback.md`. The app installed successfully on the connected tablet, but its secure lock screen prevented in-app acceptance testing. No physical printing or real Excel/Sheets import was tested. This is software verification, not a tax-compliance certification.

## Result

The initial audit findings below have now been addressed in source for **1.2.64+81**. Release verification is recorded separately in `android-user-feedback.md`.

- Sales and money-movement CSVs use one encoder that quotes/escapes all text and prefixes formula-like text while retaining typed numeric money cells. Thai UTF-8 BOM remains in the shared files.
- Sales CSV includes original amount, returned amount, net revenue, original/reversed/net cost, net profit, bill reference and refund timestamp. Net detail columns reconcile with the summary; unknown cost stays explicit. UI/PDF totals share per-bill cent rounding with CSV.
- Sales UI provides a compact explanation of the original-sale-date basis; PDF/CSV state it explicitly. Existing sale-cohort behavior and closed cash snapshots are preserved.
- Existing money-movement screen now exports the selected recorded-date period, with occurrence date, original sale reference/date, payment method, signed cash/sales/debt movements and reconciliation status. Missing legacy sale data is labelled; read failures abort export instead of fabricating zero. Export retains the advanced-report entitlement and existing owner access rules. This is a daily movement bridge, not a reconstructed closing snapshot.
- Regression verification: seven new production-builder tests, including a strict CSV reader, all pass. Whole Flutter suite: 323 pass; whole backend command: 174 Node tests plus escalation assertions pass. Supplier browser regression and four local emulator suites (security hardening, catalog rules, accounting, rollover) pass. Full Dart analysis is clean. Physical export/share/Excel import and iOS remain unverified.

| Priority | Finding | Evidence and consequence | Recommended change |
| --- | --- | --- | --- |
| High | CSV text escaping is incomplete | The executed CSV method emits customer `ACME "Branch", East` as `"ACME "Branch", East"`, rather than doubling embedded quotes. Shop `Audit, East` creates three header fields instead of two. Importers can reject or misinterpret these cells. | Centralize CSV encoding for every text field; escape quotes, commas and line breaks; verify round-trip import. |
| High | Spreadsheet formula-like text is exported unchanged | Simulated customer `=1+1` becomes `"=1+1"`. CSV quoting alone does not mark a cell as spreadsheet text. Workbook execution was not tested; this is a confirmed missing export safeguard, not a demonstrated exploit. | Neutralize formula-leading untrusted text or provide a typed spreadsheet export; preserve legitimate numeric columns. |
| Medium | Sales-date reports and refund-date cash closing have different bases | Sale 100 on October 29, refunded October 30: the October 29 CSV net changes from 100 to 0; October 30 CSV has zero refunds and zero bills. Analytics behaves the same. A simulated October 30 cash refund movement correctly reduces a 500 drawer to 400. | Label the sales-cohort basis clearly. Add a movement-date reconciliation view with original bill/date, refund date, method and amount. Preserve immutable closed-session snapshots. |
| Medium | Refunded CSV detail does not sum directly to net summary | For the fully refunded 100 sale with cost 40, summary net revenue and COGS are both 0. Its detail row still has revenue 100 and cost 40, profit 0 and status refunded. Summing detail amounts without filtering produces different totals. | Label original gross amounts explicitly and add refund/net-revenue/net-cost columns or separate signed reversal rows, so totals can be reconciled without guessing. |

The cross-date refund behavior is intentional in the analytics implementation: `functions/analytics.test.js` already asserts that refunds belong to the original sale cohort. It is **not evidence that the cash ledger lost money or that closed snapshots were rewritten**. The missing piece for an accountant is a clearly labelled bridge between the two report bases.

## Passed checks

- **79 Node tests** across accounting, cash report, reconciliation, rollover, close-work checks, refund, analytics/backend and receipt profile.
- **21 Flutter tests** across accounting models, Z-report generation, reconciliation UI, close checks and receipt/session calculations.
- **Two Firestore emulator suites**: accounting transaction races/next-day debt refund/immutable snapshots/device rules, and atomic cash closing/opening/concurrent operations/history. Permission-denied messages are expected negative authorization cases; both runners exited successfully.
- **Four additional diagnostic observations** executed the current `_exportCsv` method verbatim, replacing only settings/sales input and file-sharing boundaries. They reproduce the findings above; their passing assertions confirm current defects/behavior, not export correctness.

Selected scenarios cover discount allocation to cents, known versus unknown cost, cash refunds, credit sales, collection without a second sale, cancellation of remaining debt, concurrent confirmation without duplicate financial movement, closing safeguards and stored receipt settings. Receipt-profile tests verify that online checkout does not add VAT again and retains the original issuer settings on retry. Z-report generation tests verify local PDF generation, not a printed-paper review or regulatory completeness.

## Reproduce

```powershell
node --test functions/accounting.test.js functions/cash_report.test.js functions/cash_reconciliation.test.js functions/cash_rollover.test.js functions/cash_close_work.test.js functions/refund.test.js functions/analytics.test.js functions/analytics_backend.test.js functions/receipt_profile.test.js
.\flutter\bin\flutter.bat test --no-pub test/accounting_test.dart test/zreport_generator_test.dart test/cash_reconciliation_test.dart test/cash_close_check_test.dart test/receipt_and_session_test.dart
node scripts/audit_accountant_exports.cjs
```

With local Java configured:

```powershell
firebase emulators:exec --only firestore --project demo-pokpok-admin --config firebase.rules-test.json "node functions/accounting.integration.cjs && node functions/cash_rollover.integration.cjs"
```

Private run evidence: `.remember/tmp/accountant-audit-node.log`, `accountant-audit-flutter.log`, `accountant-audit-emulator.log`, `accountant-export-audit.log`.

Original audit source anchors: `lib/screens/report_screen.dart` export and report/PDF totals; `lib/services/sale_service.dart` date query; `functions/analytics.js` sale-cohort aggregation; `functions/money_ledger.js` movement-based drawer summary. The exploratory generated harness used an in-memory date filter matching the query. The maintained regression entry point now runs `test/accounting_exports_test.dart` directly against production export builders. Neither test exercises a live Firestore report subscription or native share sheet.

## Remaining verification

After fixes: import exported files in Excel/Sheets; reconcile a real-device end-to-end test-shop sale, next-day refund and closing export; visually review PDF and narrow-paper output. Full VAT purchase/sales registers, general ledger, statutory forms, partial returns and real bank/slip matching were not certified by this run.
