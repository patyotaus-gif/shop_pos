# Subscription: Direct PromptPay + Admin-Editable Plans

**Date:** 2026-07-09
**Status:** Approach A approved by owner; remaining sections delegated ("ทำต่อให้เสร็จทุกอย่างแล้วสรุปทีเดียว")
**Trigger:** (1) `createCheckoutSession` is broken in production — Stripe rejects `payment_method_types[2]: "truemoney"` (removed from Stripe's supported list), so every subscription payment fails. (2) Owner wants ~0% fees via PromptPay direct to the company account. (3) Owner wants plans editable without code deploys.

## Goals

1. **Primary payment rail:** PromptPay direct to the company account with automatic slip verification (reuse the proven shop-order slip pipeline) → subscription extends instantly, founder notified on every payment.
2. **Secondary rail:** cards via Stripe Checkout (existing flow + truemoney fix).
3. **Plan catalog in Firestore** (`config/plans`) — single source read by functions and the /subscribe page; editable from the founder console. The app deliberately shows no prices (Apple IAP rules; `subscription_screen.dart` links out), so no app-side plan reads are needed.
4. Customer tier switching by admin already exists (`adminSetSubscription`) — unchanged.

## Data model

### `config/plans` (Firestore)

```json
{
  "tiers": {
    "solo":       { "name": "Solo", "desc": "…", "enabled": true,
                    "monthly": { "amount": 19900, "days": 30 },
                    "yearly":  { "amount": 199000, "days": 365 } },
    "lite":       { "…": "…" },
    "full":       { "…": "…", "featured": true },
    "restaurant": { "…": "…", "perLocation": true }
  },
  "updatedAt": "…", "updatedBy": "<founder uid>"
}
```

- Amounts in **satang** (matches existing `PLANS`). `days` fixed at 30/365 (not editable — entitlement math stays sane). Editable: `amount`, `name`, `desc`, `enabled`, `featured`. Tier keys fixed to the 4 existing tiers.
- Functions: `getPlans()` — Firestore read, 60s in-memory cache, **fallback to the hardcoded defaults when the doc is missing** (zero-migration bootstrap). `resolvePlanConfig(plans, tier, cycle)` becomes pure (plans passed in).
- /subscribe page: reads `config/plans` with the client SDK after login; hardcoded PLANS mirror deleted.

### `config/billing` (Firestore — never client-readable)

```json
{ "promptpayId": "…", "promptpayName": "…", "founderLineUserId": "…" }
```

`promptpayId/Name` are returned to the payer only via the create-payment callable. `founderLineUserId` is used server-side for payment notifications.

### `subscriptionPayments/{paymentId}` (top-level collection, admin-SDK only)

```json
{ "shopId": "…", "shopName": "…", "tier": "solo", "billingCycle": "monthly",
  "locations": 1, "amount": 199.0, "finalAmount": 199.37,
  "status": "pendingPayment | paid | expired", "createdAt": "…", "expiresAt": "…(+2h)",
  "paidAt": "…", "slipUrl": "…", "paymentRef": "slip:<txKey>" }
```

- Unique-cents disambiguator like shop orders: `cents = (hashString(paymentId) % 99) + 1`.
- Replay guard: top-level `usedSubscriptionSlipRefs/{txKey}`.
- Slip audit copy: Storage `billing/slips/{paymentId}.jpg` + signed URL.

### Firestore rules (added)

```text
match /config/plans   { allow read: if request.auth != null; allow write: if false; }
match /config/billing { allow read, write: if false; }
// subscriptionPayments + usedSubscriptionSlipRefs: no rules → client-inaccessible (admin SDK only)
```

## Payment flow (PromptPay direct)

1. /subscribe (logged in) renders enabled tiers from `config/plans`. Primary button **"จ่ายด้วย PromptPay"**, secondary link **"จ่ายด้วยบัตรเครดิต"** (Stripe).
2. PromptPay → callable **`createSubscriptionPayment`** (`{tier, billingCycle}`; auth required; `uid == shopId`; locations from the shop doc for restaurant): validates tier enabled, computes amount from `getPlans()`, writes the pending doc, returns `{ paymentId, amount, finalAmount, promptpayId, promptpayName, planLabel }`. Fails with `failed-precondition` when `config/billing.promptpayId` is unset.
3. Page shows the PromptPay QR (shared EMVCo payload builder), amount incl. satang, receiver name — same UX as the order page.
4. Customer transfers, uploads the slip → HTTP endpoint **`verifySubscriptionSlip`** (App Check enforced like the order endpoints): decode QR (jimp+jsQR) → `parseEmvAmount` → match `finalAmount` (±0.01) → replay guard → store slip → mark `paid` → **`applySubscriptionPayment(shopId, tier, cycle, locations, planConfig)`** (extracted from the `stripeWebhook` subscription branch; webhook now calls the same helper) → LINE push to `founderLineUserId` (best-effort; skip+log when unset) → respond `{ success, newEndsAt }`.
5. Page shows success + new expiry date. Expired pending payments (>2h) are rejected at verify time with a "สร้างรายการใหม่" message.

## Stripe rail (kept)

- `payment_method_types: ["card", "promptpay"]` (truemoney removed — fix already in working tree) in `createCheckoutSession` and `createOrderCheckout`.
- `createCheckoutSession` + `stripeWebhook` + `opsMetrics`' `monthlyRevenueBaht` read plan config via `getPlans()`.

## Admin (founder console app — third tab "แผน & บิล")

- Plan editor: per tier — name, desc, monthly/yearly price (baht in UI → satang stored), enabled, featured. Saves via callable **`adminUpsertPlans`** (assertFounder; validates: 4 known tier keys, positive integer satang, booleans, non-empty name).
- Billing editor: company `promptpayId` (10/13/15 digits), `promptpayName`, `founderLineUserId`. Saves via **`adminSetBilling`** (assertFounder).
- Recent `subscriptionPayments` list (read via existing founder patterns) — nice-to-have; included only as a simple "last 20" list.
- Ships with the next APK; not blocking the web/functions rail.

## Shared web module

- New `public/js/promptpay-qr.js` (ES module): `tlv`, `crc16`, `buildPromptPayPayload` — moved from `public/order/js/payment.js`, which now imports and **re-exports** them (its public interface and Node tests keep working). /subscribe imports the same module; QR rendering uses the existing self-hosted `/order/qrcode.min.js`.
- /subscribe attaches the App Check token to `verifySubscriptionSlip` calls via `getToken` (page already initializes App Check); slip images are downscaled client-side (same `fileToBase64Compressed` approach as the order page).

## Edge cases

| Case | Behavior |
| --- | --- |
| `config/plans` missing | `getPlans()` falls back to hardcoded defaults; page still renders (callable resolves plans server-side too) |
| Tier disabled after page load | `createSubscriptionPayment` re-checks → `failed-precondition` |
| Price changed between create and slip | `finalAmount` was frozen on the pending doc — slip matches the frozen amount |
| Slip amount mismatch / unreadable QR / replayed slip | Same rejection messages as the order pipeline |
| Pending payment older than 2h | Verify rejects with "รายการหมดอายุ — เริ่มใหม่อีกครั้ง" |
| `promptpayId` unset | Callable fails with a clear message; PromptPay button hidden is not possible (client can't read config/billing) → page shows the error toast |
| Restaurant multi-location | `locations` read from the shop doc server-side; amount ×locations, frozen on the doc |
| Fake-slip risk (owner accepted) | Auto-approve + founder LINE alert per payment with slip link; rollback via existing `adminSetSubscription` |

## Testing

- `functions/plans.js` extracted as a pure CJS module (defaults, `resolvePlanConfig`, `validatePlansShape`, `monthlyRevenueBaht`) with a Node assert script `scripts/test_functions_plans.mjs`.
- `scripts/test_order_page.mjs` extended: `promptpay-qr.js` exports intact, payment.js re-exports still pass CRC/payload tests.
- Flutter: `flutter analyze` + `flutter test` for the console tab.
- E2E after deploy (owner): set a temp ฿1 price on solo via the plan editor → pay real PromptPay ฿1.xx → verify auto-extend + LINE alert → restore price.

## Rollout order

1. Deploy functions + rules + hosting (subscribe page + shared module) — **restores payments** (both rails).
2. Seed `config/billing` via founder console (needs next APK) **or** one-off `adminSetBilling` call from the founder account; until then PromptPay rail returns the clear "ยังไม่ตั้งค่า" error and cards work.
3. Android 1.2.15 ships the console tab (+ pending ProductImage fix).

## Out of scope

Receipts/tax invoices, payment history UI for shops, adding/removing tiers, changing `days`, bank-API slip verification (SlipOK) — revisit if fraud appears.
