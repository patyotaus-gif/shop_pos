# Receipt Numbers + Professional Receipt + Daily Close (Z-report)

**Date:** 2026-07-26 · **Status:** Approved (all missing receipt fields + daily close); execute fully.

Three related pieces shipping together (all touch the till/receipt): per-day receipt numbers, a fuller receipt layout, and an end-of-day cash-count + Z-report. All client-side (Flutter); no server changes except Firestore rules for the two new subcollections.

## 1. Receipt numbers (per-day reset)

Format `YYMMDD-NNN` — Buddhist year 2-digit + month + day + 3-digit sequence, e.g. **690726-001** (2569-07-26 #1). New day → back to 001.

- Counter doc `shops/{id}/counters/receipt` = `{ day: "690726", seq: N }`.
- **`SaleService.checkout` converts its `batch` to a `runTransaction`**: read the counter (only read) → compute `{day, seq}` via pure `nextReceiptSeq(counterDay, today, seq)` → within the txn write the sale (with `receiptNo`), the stock decrements, the debt doc, and the counter. All other behavior (loyalty accrual, low-stock notify) stays outside as best-effort, unchanged. Concurrent tills serialize → distinct numbers.
- **`TableService.closeOrder`** gets the same counter transaction (its Sale prints a till receipt too).
- Online-order sales (Stripe webhook / PromptPay verify, server-side) leave `receiptNo` null — they're digital, not printed at a till.
- `Sale` gains `receiptNo: String?` and `tableName: String?` (the latter set by `closeOrder`).
- Pure helpers (Dart-unit-tested): `formatReceiptNo(dayBE, seq)`, `nextReceiptSeq(counterDay, todayBE, seq) → {day, seq}`, `todayReceiptDay(DateTime) → "690726"`.

## 2. Professional receipt layout

`ReceiptGenerator.printReceipt(sale)` now fetches shop info + logo itself (callers drop the `shopName:` arg — update the 2 call sites in `pos_screen` + `report_screen`). Adds, when present:

- **Logo** (settings `logoUrl`, fetched as bytes; skip on failure) centered at top above the name.
- **Address + Tax ID** (from `SettingsService.getShopInfo`) under the shop name, small.
- **Receipt number** line: `เลขที่: 690726-001`.
- **Table** line for restaurant sales: `โต๊ะ: <name>` (from `sale.tableName`).
- **Staff**: `พนักงาน: <name>` (from `sale.staffName`) near the footer.
- PDF filename uses `receiptNo` when set, else `sale.id`.

Everything already printed (items, modifiers, service charge, discount, total, paid/change, split, debt line, thank-you) stays. PromptPay-QR-on-receipt is **out of scope** (a receipt is proof of payment, printed after paying).

## 3. Daily close + cash count + Z-report

Data `shops/{id}/cashSessions/{id}`:
`{ openedAt, openedBy, openingFloat, status: "open"|"closed", closedAt?, closedBy?, countedCash?, snapshot? }`. Only one `open` session at a time (UI enforces).

- **เปิดรอบ**: enter opening float (drawer cash at start) → creates an `open` session. Sales are NEVER gated by a session — it's a reporting wrapper only.
- **ปิดรอบ**: query sales in `[openedAt, now]` → pure `summarizeSession(sales, openingFloat, countedCash)`:
  - gross sales total, count of bills
  - breakdown by `paymentMethod` (cash/transfer/qr/online) + debt total
  - refunds total (informational)
  - `expectedCash = openingFloat + cashSales − cashRefunds`
  - staff enters `countedCash` → `overShort = countedCash − expectedCash`
  - write the snapshot on the session, `status: "closed"`.
- **Z-report**: printable/shareable PDF (via `printing`) — shop header, period, the summary above, over/short highlighted.
- Entry: a "ปิดยอดสิ้นวัน" card on the Dashboard (opens the session screen) + a sessions history list. Available to all tiers.

## Edge cases

| Case | Behavior |
| --- | --- |
| checkout txn contention (2 tills) | transaction retries → sequential distinct numbers |
| counter doc missing (first ever sale) | treated as new day → seq 1 |
| close with no open session | button opens "เปิดรอบ" instead |
| sale with `paymentMethod=online`/debt | excluded from expected-cash; shown in its own line |
| refund inside the window | subtracted from expected cash; shown as a line |
| logo/shop-info fetch fails at print | receipt still prints without them |
| old sales (no receiptNo) | reprint shows filename by `sale.id`, no number line |

## Testing

- Dart unit tests: `nextReceiptSeq` (same-day increment, day rollover, missing counter), `formatReceiptNo`, `summarizeSession` (payment breakdown, expected cash incl. opening float + refunds, over/short sign).
- `flutter analyze` + `flutter test`.
- Manual: sell → receipt shows number/logo/address/staff; sell next day → number resets; open session → sell → close → count → Z-report over/short correct; table close → number + โต๊ะ line.

## Rollout

1. firestore.rules (counters + cashSessions owner-managed) deploy.
2. APK **1.2.21+36** — all of the above.

## Out of scope

Multiple shifts/day, per-sale sessionId tagging (time-window is enough for single till), locking sales after close, tax-invoice numbering compliance, PromptPay QR on receipts.
