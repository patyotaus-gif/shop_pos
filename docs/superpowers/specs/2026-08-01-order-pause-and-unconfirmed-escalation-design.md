# Online-Order Pause Switch + Unconfirmed-Order Escalation

**Date:** 2026-08-01 · **Status:** Approved by owner.

## Problem

Two related failure modes with online ordering today:

1. The `/order` web page accepts orders 24/7 — there is no way to pause it when the physical shop is closed. `getShopPublic` only checks `subscriptionStatus`, never "is the shop open right now."
2. Notification for a new/paid order relies entirely on a single FCM token + the in-app badge. If the notification is missed (app killed, permission denied, phone off), nothing else tells the owner an order is sitting unhandled.

Two independent, complementary features close these gaps. Feature A blocks the problem at the source (manual kill-switch). Feature B is a second line of defense for orders that got through but were never acknowledged.

## Feature A — "ปิดรับออเดอร์" pause switch

### Data model

New field on the existing `shops/{id}/settings/shop` doc (same doc that already holds `tableOrderMode`/`tableOrderAutoSend`):

| Field | Values | Meaning |
| --- | --- | --- |
| `ordersClosed` | `false` (default/absent) / `true` | Owner has manually paused online ordering |

No new collection. Read/write through the existing `SettingsService.getSettings`/`saveSettings`/`watchSettings`.

### Server (functions) — enforced at every entry point, not just hidden in the UI

- **`getShopPublic`**: response gains `ordersClosed: true` when set. Still returns `name`/`logoUrl` (so the closed page can show shop identity) but the web client must not render the product grid when this flag is present.
- **`createPromptPayOrder`, `createOrderCheckout`, `createTableOrder`**: re-check `settings/shop.ordersClosed` before creating the order and reject with `{ error: "ร้านปิดรับออเดอร์ชั่วคราว" }` if true. This covers a customer who had the menu open in a stale tab before the owner paused ordering.

### Client — Flutter app

- New quick-toggle card on `DashboardScreen`, placed near the existing "ปิดยอดสิ้นวัน" card: a `StreamBuilder` on `SettingsService.watchSettings()` driving a big switch. Green "เปิดรับออเดอร์อยู่" / red "ปิดรับออเดอร์ชั่วคราว" label swap; tapping writes `ordersClosed` immediately (optimistic, no confirmation dialog — it's a fast-reversible toggle).

### Client — customer web (`public/order/`)

- `main.js`: when `getShopPublic` response has `ordersClosed: true`, skip `renderProducts`/cart wiring entirely and render a fixed closed-state view instead: shop name/logo + "ร้านปิดรับออเดอร์ชั่วคราว กรุณาแวะมาใหม่อีกครั้ง". No product grid, no cart, no checkout button.
- Applies to both takeaway and dine-in QR (same `getShopPublic` response + same submit endpoints), per the earlier decision — a table QR scan while paused shows the same closed state.

### Edge cases

| Case | Behavior |
| --- | --- |
| Cart open in a stale tab when owner pauses | Blocked server-side at submit (`createPromptPayOrder`/`createTableOrder` re-check) |
| Owner un-pauses mid-session on a customer's already-loaded closed page | Customer must reload (no live-push refresh — out of scope, see below) |
| Table QR scanned while paused | Same closed state as takeaway (no separate "table closed" copy) |

### Out of scope (deliberate)

Scheduled auto-open/close by shop hours (manual toggle only, v1). Customizable closed-message text. Live refresh of an already-open customer page when the owner un-pauses.

## Feature B — escalate unconfirmed paid orders

### Scope

Applies only to top-level `shops/{id}/orders` docs sitting at `status == 'paid'` (payment already confirmed — by slip verification or bank-notification auto-match — but staff hasn't tapped "ยืนยัน order" yet). Dine-in table orders (`TableOrder` docs with a `kitchenStatus` per line inside an `items` array) are explicitly **out of scope** for this pass: the data shape makes a simple staleness query much harder (no single per-item timestamp field to query on), and the customer is physically in the shop, so "nobody noticed" is a materially smaller risk there than for a takeaway order placed while the shop might be unattended. Revisit if it turns out to matter in practice.

No auto-cancel: PromptPay-direct payments (QR scan + slip upload) land straight in the shop's own bank account with no `stripePaymentIntentId`, so `createRefund` cannot refund them programmatically. Cancelling an already-paid order would strand the owner with a manual refund and an upset customer. Escalation only raises urgency; the order stays in `paid` until a human acts.

### Mechanism

- New scheduled function `escalateUnconfirmedOrders` (`onSchedule`, every 2 minutes — same `onSchedule` pattern as the existing `sendRenewalReminders`).
- Query: `collectionGroup('orders')` where `status == 'paid'` and `escalatedAt` is absent and `paidAt < now - 5min`. Requires a new composite index (`status` + `paidAt`, collection-group scoped) — added to `firestore.indexes.json`.
- For each match, stamp `escalatedAt: serverTimestamp()` first (dedup — ensures exactly one escalation per order even if the function overlaps/retries), then best-effort fan-out:
  - **LINE** push to the shop's own LINE user id via the existing `_linePush` helper, gated on the same LINE-enabled setting used elsewhere: `"⚠️ ออเดอร์ค้าง 5 นาที: <customerName> ฿<finalAmount> ยังไม่ได้กดยืนยัน"`.
  - **FCM push on a new, more urgent Android channel** (`unconfirmed_order`, distinct louder default sound, `Importance.max`) — deliberately different from the existing `new_orders` channel so it's audibly distinguishable from a routine "new order" ping. `NotificationService` (Dart) registers the new channel alongside the existing one.
- Missing LINE config or missing `fcmToken` → skip that channel silently (same best-effort try/catch pattern already used for LINE sends elsewhere). `escalatedAt` is stamped regardless, so a shop with nothing configured doesn't cause the function to retry the same order every run.

### Edge cases

| Case | Behavior |
| --- | --- |
| Staff confirms at 4:59 | Query cutoff means it never matches; no escalation |
| Staff confirms after escalation already fired | No-op — `escalatedAt` stays, order proceeds normally |
| Function run overlaps/retries | `escalatedAt` write happens before sending, so a re-run of the same tick skips already-stamped docs |
| Shop has LINE off and no fcmToken | Both channels skipped; `escalatedAt` still stamped (no infinite retry) |
| Order cancelled before 5 min | Query only matches `status == 'paid'`; a cancelled order is excluded |

### Out of scope (deliberate)

Dine-in table order escalation (see Scope above). Auto-cancel/refund. Repeated/escalating reminders beyond the single 5-minute alert. Configurable threshold (fixed 5 minutes for v1).

## Testing

- **Node**: pure-function unit test for the escalation-candidate filter (given a list of order-like records + a "now" timestamp, which ones qualify) — same pattern as `functions/plans.js`/`functions/inventory.js` pure-helper tests, extracted so the Firestore query itself doesn't need to be exercised in the test.
- **Flutter**: `flutter analyze` + existing test suite stays green; manual check of the new Dashboard toggle (switch flips, `settings/shop.ordersClosed` updates in Firestore) and the new notification channel appears in Android settings.
- **Manual, post-deploy**:
  - Pause ordering → confirm `/order` shows the closed state for both a takeaway link and a table QR link; confirm a direct API call to `createPromptPayOrder` while paused is rejected.
  - Place a real takeaway PromptPay order, leave it unconfirmed past 5 minutes (or temporarily lower the threshold in a local run), confirm LINE + the new push channel both fire exactly once.

## Rollout

1. Functions + Firestore rules (no rule changes expected — `ordersClosed`/`escalatedAt` are both server/owner-only fields, same access pattern as existing settings fields) + `firestore.indexes.json` update, deployed first.
2. APK release: Dashboard pause toggle + new notification channel registration.
3. Hosting deploy for the `/order` closed-state view — safe for existing shops (`ordersClosed` absent behaves exactly as today).
