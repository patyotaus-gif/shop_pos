# Online-Order Pause Switch + Unconfirmed-Order Escalation — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the owner pause the `/order` customer web page with one tap (Feature A), and get a second-line-of-defense LINE + push alert when a paid takeaway order sits unconfirmed for 5+ minutes (Feature B).

**Architecture:** Feature A adds one boolean field (`ordersClosed`) to the existing `shops/{id}/settings/shop` doc, enforced at every order-creation entry point server-side and reflected in a Dashboard toggle + a customer-web closed-state view. Feature B adds a new 2-minute `onSchedule` Cloud Function that queries `collectionGroup('orders')` for stale `paid` orders, using a pure extracted filter function (unit-tested) to decide which orders qualify, then fans out LINE + a new, louder Android FCM channel.

**Tech Stack:** Firebase Cloud Functions v2 (Node, CommonJS), Firestore, Flutter/Dart (`flutter_local_notifications`, `cloud_firestore`), vanilla JS customer web app (`public/order/js`).

**Source spec:** `docs/superpowers/specs/2026-08-01-order-pause-and-unconfirmed-escalation-design.md` — approved by owner 2026-08-01.

## Global Constraints

- No new Firestore collection for Feature A — reuse `shops/{id}/settings/shop` via the existing `SettingsService`/`saveSettings`/`watchSettings` (Flutter) and the existing `settings/shop` doc read in Functions.
- No Firestore rules changes — `ordersClosed` and `escalatedAt` are both server/owner-only fields using access patterns that already exist (`settings/{settingId}` and `orders/{orderId}` are owner read/write; `escalatedAt` is written by the Admin SDK from a scheduled function, which bypasses rules entirely).
- Feature B applies **only** to top-level `shops/{id}/orders` docs with `status == 'paid'`. Dine-in `tableOrders` are explicitly out of scope for this pass.
- Fixed 5-minute threshold, fixed 2-minute schedule interval — no configurable threshold in v1.
- No auto-cancel/refund of unconfirmed orders — escalation only raises urgency.
- `escalatedAt` must be stamped exactly once per order, even if the scheduled function overlaps or retries (stamp-before-send ordering).
- Missing LINE config or missing `fcmToken` → skip that channel silently; never block the other channel or the `escalatedAt` stamp.
- This repo has no JS test runner (no `jest`/`mocha`, no root `package.json`). Feature B's pure filter gets a plain `node:assert`-based test file, runnable via `node functions/escalation.test.js` — matching the only "test" pattern this repo can actually run. Functions-file edits are verified with `node --check <file>` (syntax only); the customer-web JS has no verification tooling at all, so those edits are verified by careful reading, consistent with the spec's own "Manual, post-deploy" testing section.
- `suppliers/{supplierId}/orders/{orderId}` is a **second** `orders` subcollection in this schema (B2B marketplace dual-write copy, written from `lib/services/marketplace_service.dart`). `MarketplaceOrderStatus` has no `paid` value today, but the escalation scheduled function must still guard against ever matching non-shop `orders` docs via `collectionGroup('orders')` — see Task 5.

---

## Task 1: Server — Feature A gating at every order-creation entry point

**Files:**
- Modify: `functions/index.js` (`getShopPublic` ~L197-303, `createOrderCheckout` ~L308-371, `createPromptPayOrder` ~L541-660, `createTableOrder` ~L2346-2525)

**Interfaces:**
- Produces: `getShopPublic` response gains an optional `ordersClosed: true` field, consumed by Task 3's `public/order/js/main.js`.
- Produces: `createOrderCheckout`/`createPromptPayOrder`/`createTableOrder` reject with HTTP 400 `{ error: "ร้านปิดรับออเดอร์ชั่วคราว" }` when the shop is paused.

- [ ] **Step 1: Add `ordersClosed` to the `getShopPublic` response**

In `functions/index.js`, find this block (around line 279-282):

```js
  const settings = settingsSnap.data() || {};

  const out = { name: shop.name || "ร้านค้า", products };
  if (settings.logoUrl) out.logoUrl = settings.logoUrl;
```

Replace with:

```js
  const settings = settingsSnap.data() || {};

  const out = { name: shop.name || "ร้านค้า", products };
  if (settings.logoUrl) out.logoUrl = settings.logoUrl;
  // Owner-paused ordering — client still gets name/logo so the closed
  // page can show shop identity, just no products/cart wiring.
  if (settings.ordersClosed === true) out.ordersClosed = true;
```

- [ ] **Step 2: Reject `createOrderCheckout` while paused**

Find this block (around line 317-326):

```js
    const { shopId, customerName, customerPhone, items } = req.body;

    if (!shopId || !customerName || !customerPhone || !Array.isArray(items) || items.length === 0) {
      res.status(400).json({ error: "ข้อมูลไม่ครบ" });
      return;
    }

    const total = items.reduce((s, item) => s + item.price * item.quantity, 0);
```

Replace with:

```js
    const { shopId, customerName, customerPhone, items } = req.body;

    if (!shopId || !customerName || !customerPhone || !Array.isArray(items) || items.length === 0) {
      res.status(400).json({ error: "ข้อมูลไม่ครบ" });
      return;
    }

    // Re-check pause state server-side — covers a customer with the menu
    // open in a stale tab before the owner paused ordering.
    const shopRef = admin.firestore().collection("shops").doc(shopId);
    const settingsSnap = await shopRef.collection("settings").doc("shop").get();
    if (settingsSnap.data()?.ordersClosed === true) {
      res.status(400).json({ error: "ร้านปิดรับออเดอร์ชั่วคราว" });
      return;
    }

    const total = items.reduce((s, item) => s + item.price * item.quantity, 0);
```

Then further down in the same function (around line 331-337), reuse `shopRef` instead of rebuilding it:

```js
    // สร้าง order doc ก่อน (status: pendingPayment)
    const orderRef = admin
      .firestore()
      .collection("shops")
      .doc(shopId)
      .collection("orders")
      .doc();
```

Replace with:

```js
    // สร้าง order doc ก่อน (status: pendingPayment)
    const orderRef = shopRef.collection("orders").doc();
```

- [ ] **Step 3: Reject `createPromptPayOrder` while paused**

Find this block (around line 576-589):

```js
    // Look up the shop's PromptPay settings
    const shopRef = admin.firestore().collection("shops").doc(shopId);
    const settingsSnap = await shopRef
      .collection("settings").doc("shop").get();
    const settings = settingsSnap.data() || {};
    const promptpayId = settings.promptpayId;
    const promptpayName = settings.promptpayName || "";

    if (!promptpayId) {
```

Replace with:

```js
    // Look up the shop's PromptPay settings
    const shopRef = admin.firestore().collection("shops").doc(shopId);
    const settingsSnap = await shopRef
      .collection("settings").doc("shop").get();
    const settings = settingsSnap.data() || {};

    // Re-check pause state server-side — covers a customer with the menu
    // open in a stale tab before the owner paused ordering.
    if (settings.ordersClosed === true) {
      res.status(400).json({ error: "ร้านปิดรับออเดอร์ชั่วคราว" });
      return;
    }

    const promptpayId = settings.promptpayId;
    const promptpayName = settings.promptpayName || "";

    if (!promptpayId) {
```

- [ ] **Step 4: Reject `createTableOrder` while paused**

Find this block (around line 2392-2394):

```js
      const settingsSnap = await shopRef
        .collection("settings").doc("shop").get();
      const autoSend = settingsSnap.data()?.tableOrderAutoSend === true;
```

Replace with:

```js
      const settingsSnap = await shopRef
        .collection("settings").doc("shop").get();
      if (settingsSnap.data()?.ordersClosed === true) {
        res.status(400).json({ error: "ร้านปิดรับออเดอร์ชั่วคราว" });
        return;
      }
      const autoSend = settingsSnap.data()?.tableOrderAutoSend === true;
```

- [ ] **Step 5: Verify syntax**

Run: `node --check functions/index.js`
Expected: no output, exit code 0.

- [ ] **Step 6: Commit**

```bash
git add functions/index.js
git commit -m "feat: enforce ordersClosed pause at every order-creation entry point"
```

---

## Task 2: Flutter — Dashboard pause toggle

**Files:**
- Modify: `lib/screens/dashboard_screen.dart`

**Interfaces:**
- Consumes: `SettingsService.watchSettings() → Stream<Map<String, dynamic>>`, `SettingsService.saveSettings(Map<String, dynamic>) → Future<void>` (both already exist in `lib/services/settings_service.dart`).

- [ ] **Step 1: Add the import**

In `lib/screens/dashboard_screen.dart`, the import block currently reads:

```dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/product.dart';
import '../models/sale.dart';
import '../models/shop.dart';
import '../services/entitlements.dart';
import '../services/product_service.dart';
import '../services/sale_service.dart';
import '../services/shop_service.dart';
import 'cash_session_screen.dart';
import 'marketplace_home_screen.dart';
```

Add `SettingsService` to it:

```dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/product.dart';
import '../models/sale.dart';
import '../models/shop.dart';
import '../services/entitlements.dart';
import '../services/product_service.dart';
import '../services/sale_service.dart';
import '../services/settings_service.dart';
import '../services/shop_service.dart';
import 'cash_session_screen.dart';
import 'marketplace_home_screen.dart';
```

- [ ] **Step 2: Add the toggle card after "ปิดยอดสิ้นวัน"**

Find this block (around line 87-101):

```dart
            // ปิดยอดสิ้นวัน — cash session + Z-report.
            Card(
              child: ListTile(
                leading: const Icon(Icons.point_of_sale_outlined),
                title: const Text('ปิดยอดสิ้นวัน'),
                subtitle: const Text('เปิด/ปิดรอบ · นับเงินลิ้นชัก · Z-report'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const CashSessionScreen()),
                ),
              ),
            ),
            const SizedBox(height: 16),
```

Replace with:

```dart
            // ปิดยอดสิ้นวัน — cash session + Z-report.
            Card(
              child: ListTile(
                leading: const Icon(Icons.point_of_sale_outlined),
                title: const Text('ปิดยอดสิ้นวัน'),
                subtitle: const Text('เปิด/ปิดรอบ · นับเงินลิ้นชัก · Z-report'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const CashSessionScreen()),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // ปิดรับออเดอร์ — quick toggle for the /order customer web page.
            // Optimistic write, no confirmation dialog: it's fast-reversible.
            StreamBuilder<Map<String, dynamic>>(
              stream: SettingsService.watchSettings(),
              builder: (context, snap) {
                final closed = snap.data?['ordersClosed'] == true;
                return Card(
                  child: SwitchListTile(
                    secondary: Icon(
                      closed ? Icons.storefront_outlined : Icons.storefront,
                      color: closed ? Colors.red : Colors.green,
                    ),
                    title: Text(
                      closed ? 'ปิดรับออเดอร์ชั่วคราว' : 'เปิดรับออเดอร์อยู่',
                      style: TextStyle(
                        color: closed ? Colors.red : Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: const Text('เปิด/ปิดรับออเดอร์จากหน้าเว็บลูกค้า (/order)'),
                    value: !closed,
                    activeColor: Colors.green,
                    onChanged: (open) =>
                        SettingsService.saveSettings({'ordersClosed': !open}),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
```

- [ ] **Step 3: Verify**

Run: `flutter analyze`
Expected: `No issues found!`

- [ ] **Step 4: Commit**

```bash
git add lib/screens/dashboard_screen.dart
git commit -m "feat: add ปิดรับออเดอร์ pause toggle to Dashboard"
```

---

## Task 3: Customer web — closed-state view

**Files:**
- Modify: `public/order/index.html`
- Modify: `public/order/order.css`
- Modify: `public/order/js/main.js`

**Interfaces:**
- Consumes: `data.ordersClosed` from the `getShopPublic` response (Task 1).

- [ ] **Step 1: Add the closed-state container to `index.html`**

Find this line (around line 42):

```html
<div id="error" style="display:none"></div>
```

Replace with:

```html
<div id="error" style="display:none"></div>
<div id="closedState" style="display:none">ร้านปิดรับออเดอร์ชั่วคราว กรุณาแวะมาใหม่อีกครั้ง</div>
```

- [ ] **Step 2: Style it in `order.css`**

Find this line (around line 80):

```css
#loading, #error { text-align: center; padding: 80px 20px; color: var(--text-muted); font-size: 15px; font-weight: 500; }
```

Replace with:

```css
#loading, #error, #closedState { text-align: center; padding: 80px 20px; color: var(--text-muted); font-size: 15px; font-weight: 500; }
```

- [ ] **Step 3: Branch on `ordersClosed` in `main.js` before rendering products**

In `public/order/js/main.js`, the current body of `start()` (after the `res.json()` call) reads:

```js
    const data = await res.json();

    // Resolve the ordering mode from the QR link + shop settings.
    if (data.table) {
      orderContext.table = data.table;
      orderContext.mode =
        data.tableOrderMode === 'prepaid' ? 'prepaidTable' : 'dineIn';
    } else if (takeawayParam) {
      orderContext.mode = 'takeaway';
    }
    const dineIn = orderContext.mode === 'dineIn';

    initCatalog();
    initCartUI({
      onCheckout: () =>
        maybeShowUpsell(dineIn ? openTableOrderSheet : openOrderModal),
    });
    initPayment();
    initTableOrder();

    const shopName = data.name || 'ร้านค้า';
    document.getElementById('shopName').textContent = shopName;
    document.title = `สั่งสินค้า — ${shopName}`;

    // Shop logo → sits in the sticky header (replaces the Pokpok mark),
    // so the whole top bar stays fixed while the list scrolls.
    if (data.logoUrl) {
      const logo = document.getElementById('shopLogoImg');
      const mark = document.querySelector('.brand-mark');
      logo.alt = shopName;
      logo.onerror = () => { logo.hidden = true; if (mark) mark.hidden = false; };
      logo.src = data.logoUrl;
      logo.hidden = false;
      if (mark) mark.hidden = true;
    }

    // Context badge + checkout label per mode.
    const badge = document.getElementById('modeBadge');
    if (orderContext.table) {
      badge.hidden = false;
      badge.innerHTML = `🍽️ โต๊ะ ${escHtml(orderContext.table.name)}`;
    } else if (orderContext.mode === 'takeaway') {
      badge.hidden = false;
      badge.textContent = '🛍️ รับกลับบ้าน';
    }
    if (dineIn) {
      document.getElementById('checkoutBtn').textContent = 'ส่งออเดอร์เข้าครัว';
    }

    renderProducts(data.products || []);
    initUpsell({
      products: data.products || [],
      label: dineIn ? 'ส่งออเดอร์ต่อ' : 'ไปชำระเงินต่อ',
    });
    document.getElementById('loading').style.display = 'none';
    document.getElementById('products').style.display = 'grid';
```

Replace the whole block with (shop identity now set up-front, before the pause check, so the closed page still shows the shop's name/logo; product/cart/mode setup moves after the check and returns early when paused):

```js
    const data = await res.json();

    const shopName = data.name || 'ร้านค้า';
    document.getElementById('shopName').textContent = shopName;
    document.title = `สั่งสินค้า — ${shopName}`;

    // Shop logo → sits in the sticky header (replaces the Pokpok mark),
    // so the whole top bar stays fixed while the list scrolls.
    if (data.logoUrl) {
      const logo = document.getElementById('shopLogoImg');
      const mark = document.querySelector('.brand-mark');
      logo.alt = shopName;
      logo.onerror = () => { logo.hidden = true; if (mark) mark.hidden = false; };
      logo.src = data.logoUrl;
      logo.hidden = false;
      if (mark) mark.hidden = true;
    }

    // Owner paused ordering — show identity + closed message only. No
    // product grid, cart, or checkout wiring (also enforced server-side
    // at submit, in case this tab was already open when the owner paused).
    if (data.ordersClosed) {
      document.getElementById('loading').style.display = 'none';
      document.getElementById('closedState').style.display = 'block';
      return;
    }

    // Resolve the ordering mode from the QR link + shop settings.
    if (data.table) {
      orderContext.table = data.table;
      orderContext.mode =
        data.tableOrderMode === 'prepaid' ? 'prepaidTable' : 'dineIn';
    } else if (takeawayParam) {
      orderContext.mode = 'takeaway';
    }
    const dineIn = orderContext.mode === 'dineIn';

    initCatalog();
    initCartUI({
      onCheckout: () =>
        maybeShowUpsell(dineIn ? openTableOrderSheet : openOrderModal),
    });
    initPayment();
    initTableOrder();

    // Context badge + checkout label per mode.
    const badge = document.getElementById('modeBadge');
    if (orderContext.table) {
      badge.hidden = false;
      badge.innerHTML = `🍽️ โต๊ะ ${escHtml(orderContext.table.name)}`;
    } else if (orderContext.mode === 'takeaway') {
      badge.hidden = false;
      badge.textContent = '🛍️ รับกลับบ้าน';
    }
    if (dineIn) {
      document.getElementById('checkoutBtn').textContent = 'ส่งออเดอร์เข้าครัว';
    }

    renderProducts(data.products || []);
    initUpsell({
      products: data.products || [],
      label: dineIn ? 'ส่งออเดอร์ต่อ' : 'ไปชำระเงินต่อ',
    });
    document.getElementById('loading').style.display = 'none';
    document.getElementById('products').style.display = 'grid';
```

- [ ] **Step 4: Verify by reading**

There is no JS test runner for this file. Re-read the edited `start()` function top to bottom and confirm: (a) `shopName`/logo are set exactly once, before any early return; (b) the `ordersClosed` branch returns before `initCatalog`/`initCartUI`/`renderProducts` run; (c) the non-paused path is otherwise identical to before (same badge/mode/render logic, just reordered). Full end-to-end verification happens post-deploy per the spec's "Manual, post-deploy" section (pause ordering → load `/order?shop=<id>` and confirm the closed view appears for both a takeaway link and a table QR link).

- [ ] **Step 5: Commit**

```bash
git add public/order/index.html public/order/order.css public/order/js/main.js
git commit -m "feat: show closed-state view on /order when the shop pauses ordering"
```

---

## Task 4: Server — pure escalation-candidate filter (TDD)

**Files:**
- Create: `functions/escalation.js`
- Create: `functions/escalation.test.js`

**Interfaces:**
- Produces: `ESCALATION_THRESHOLD_MS: number`, `needsEscalation(order, nowMs, thresholdMs?) → boolean`, `selectEscalationCandidates(orders, nowMs, thresholdMs?) → array` — where `order` is `{ status, paidAtMs, escalatedAt }`. Consumed by Task 5's `escalateUnconfirmedOrders`.

- [ ] **Step 1: Write the failing test**

Create `functions/escalation.test.js`:

```js
// Plain node:assert test — this repo has no jest/mocha. Run directly:
//   node functions/escalation.test.js
const assert = require("node:assert/strict");
const {
  ESCALATION_THRESHOLD_MS,
  needsEscalation,
  selectEscalationCandidates,
} = require("./escalation");

const NOW = Date.parse("2026-08-01T12:00:00Z");

function order(overrides) {
  return {
    status: "paid",
    paidAtMs: NOW - ESCALATION_THRESHOLD_MS,
    escalatedAt: null,
    ...overrides,
  };
}

// Paid exactly at the threshold, never escalated → escalate.
assert.equal(
  needsEscalation(order({}), NOW),
  true,
  "order paid exactly 5 min ago should escalate"
);

// Staff confirms at 4:59 — still under threshold, no escalation yet.
assert.equal(
  needsEscalation(order({ paidAtMs: NOW - ESCALATION_THRESHOLD_MS + 1000 }), NOW),
  false,
  "order paid 4:59 ago should not escalate yet"
);

// Already escalated — no-op regardless of elapsed time.
assert.equal(
  needsEscalation(order({ escalatedAt: NOW - 1000 }), NOW),
  false,
  "already-escalated order should be skipped"
);

// Any non-paid status (e.g. cancelled before hitting the threshold) is excluded.
assert.equal(
  needsEscalation(order({ status: "cancelled" }), NOW),
  false,
  "non-paid status should never escalate"
);

// Defensive: an order with no paidAt should never escalate.
assert.equal(
  needsEscalation(order({ paidAtMs: undefined }), NOW),
  false,
  "order with no paidAt should not escalate"
);

// selectEscalationCandidates filters a mixed batch down to just the due one.
const dueOrder = order({});
const notDueOrder = order({ paidAtMs: NOW - 60000 });
const alreadyDone = order({ escalatedAt: NOW - 1000 });
assert.deepEqual(
  selectEscalationCandidates([dueOrder, notDueOrder, alreadyDone], NOW),
  [dueOrder],
  "selectEscalationCandidates should return only the due order"
);

console.log("escalation.test.js: all assertions passed");
```

- [ ] **Step 2: Run it to verify it fails**

Run: `node functions/escalation.test.js`
Expected: throws `Error: Cannot find module './escalation'`.

- [ ] **Step 3: Implement `functions/escalation.js`**

```js
// Pure staleness filter for Feature B (escalate unconfirmed paid orders).
// Kept dependency-free from Firestore so it's directly unit-testable —
// see escalation.test.js. Callers convert Firestore Timestamps to plain
// millisecond numbers before calling in.
const ESCALATION_THRESHOLD_MS = 5 * 60 * 1000;

/**
 * @param {{status: string, paidAtMs: number|null|undefined, escalatedAt: any}} order
 * @param {number} nowMs
 * @param {number} [thresholdMs]
 * @returns {boolean}
 */
function needsEscalation(order, nowMs, thresholdMs = ESCALATION_THRESHOLD_MS) {
  if (order.status !== "paid") return false;
  if (order.escalatedAt) return false;
  if (typeof order.paidAtMs !== "number") return false;
  return nowMs - order.paidAtMs >= thresholdMs;
}

/**
 * @param {Array<{status: string, paidAtMs: number|null|undefined, escalatedAt: any}>} orders
 * @param {number} nowMs
 * @param {number} [thresholdMs]
 */
function selectEscalationCandidates(orders, nowMs, thresholdMs = ESCALATION_THRESHOLD_MS) {
  return orders.filter((o) => needsEscalation(o, nowMs, thresholdMs));
}

module.exports = { ESCALATION_THRESHOLD_MS, needsEscalation, selectEscalationCandidates };
```

- [ ] **Step 4: Run it to verify it passes**

Run: `node functions/escalation.test.js`
Expected: prints `escalation.test.js: all assertions passed`, exit code 0.

- [ ] **Step 5: Commit**

```bash
git add functions/escalation.js functions/escalation.test.js
git commit -m "feat: add pure staleness filter for unconfirmed-order escalation"
```

---

## Task 5: Server — `escalateUnconfirmedOrders` scheduled function + composite index

**Files:**
- Modify: `functions/index.js`
- Create: `firestore.indexes.json`
- Modify: `firebase.json`

**Interfaces:**
- Consumes: `ESCALATION_THRESHOLD_MS`, `selectEscalationCandidates` from `functions/escalation.js` (Task 4); `_linePush(token, to, messages)` already defined in `functions/index.js`.

- [ ] **Step 1: Require the escalation module**

In `functions/index.js`, find the `plans.js` require block (around line 21-29):

```js
const {
  DEFAULT_TIERS,
  resolvePlanConfig,
  monthlyRevenueBaht,
  validateTiers,
} = require("./plans");
```

Add directly below it:

```js

// Pure escalation-candidate filter — extracted so escalateUnconfirmedOrders'
// staleness logic can be unit-tested without touching Firestore. See
// functions/escalation.test.js.
const {
  ESCALATION_THRESHOLD_MS,
  selectEscalationCandidates,
} = require("./escalation");
```

- [ ] **Step 2: Add the scheduled function**

In `functions/index.js`, find the end of `renewalMessage` (around line 2012-2014):

```js
}

// ────────────────────────────────────────────────
// Subscription payment — direct PromptPay (0% fees)
// ────────────────────────────────────────────────
```

Insert the new function between them:

```js
}

// ────────────────────────────────────────────────
// Escalate unconfirmed paid orders (takeaway/online only — see design spec;
// dine-in tableOrders are explicitly out of scope for this pass)
// ────────────────────────────────────────────────
// A "paid" order sitting unconfirmed for 5+ minutes gets one best-effort
// LINE + FCM nudge on a louder channel than the routine new-order ping.
// escalatedAt is stamped before sending so overlapping/retried runs never
// double-fire (see functions/escalation.js for the pure staleness filter).
exports.escalateUnconfirmedOrders = onSchedule(
  {
    schedule: "every 2 minutes",
    timeZone: "Asia/Bangkok",
    secrets: [lineChannelAccessToken],
  },
  async () => {
    const db = admin.firestore();
    const now = Date.now();
    const cutoff = admin.firestore.Timestamp.fromMillis(now - ESCALATION_THRESHOLD_MS);

    // escalatedAt-absence isn't part of the composite index (Firestore can't
    // index "field missing"), so that half of the filter runs in memory via
    // selectEscalationCandidates below.
    const snap = await db
      .collectionGroup("orders")
      .where("status", "==", "paid")
      .where("paidAt", "<", cutoff)
      .get();

    // `orders` also exists at suppliers/{supplierId}/orders (B2B marketplace
    // dual-write copy) — collectionGroup matches both. MarketplaceOrderStatus
    // has no "paid" value today, but guard the path shape anyway so this
    // never touches a non-shop order doc.
    const pool = snap.docs
      .filter((doc) => {
        const parts = doc.ref.path.split("/");
        return parts.length === 4 && parts[0] === "shops" && parts[2] === "orders";
      })
      .map((doc) => {
        const data = doc.data();
        return {
          ref: doc.ref,
          customerName: data.customerName,
          finalAmount: data.finalAmount ?? data.total,
          status: data.status,
          paidAtMs: data.paidAt?.toMillis?.() ?? null,
          escalatedAt: data.escalatedAt ?? null,
        };
      });

    const candidates = selectEscalationCandidates(pool, now);

    let escalated = 0;
    for (const order of candidates) {
      // Stamp first — dedups against overlapping/retried runs.
      await order.ref.update({ escalatedAt: admin.firestore.FieldValue.serverTimestamp() });

      const shopRef = order.ref.parent.parent;
      const text =
        `⚠️ ออเดอร์ค้าง 5 นาที: ${order.customerName || "-"} ` +
        `฿${Number(order.finalAmount || 0).toFixed(2)} ยังไม่ได้กดยืนยัน`;

      try {
        const [shopSnap, settingsSnap] = await Promise.all([
          shopRef.get(),
          shopRef.collection("settings").doc("shop").get(),
        ]);

        const fcmToken = shopSnap.data()?.fcmToken;
        if (fcmToken) {
          await admin.messaging().send({
            token: fcmToken,
            notification: { title: "⚠️ ออเดอร์ค้างนาน", body: text },
            android: {
              notification: { channelId: "unconfirmed_order", priority: "high" },
            },
          });
        }

        const lineUserId = settingsSnap.data()?.lineUserId;
        const lineEnabled = settingsSnap.data()?.lineNotifyEnabled !== false;
        if (lineUserId && lineEnabled) {
          await _linePush(lineChannelAccessToken.value(), lineUserId, [
            { type: "text", text },
          ]);
        }
      } catch (e) {
        console.error(`escalation notify failed for ${order.ref.path}:`, e);
      }
      escalated++;
    }
    console.log(`Unconfirmed-order escalations sent: ${escalated}`);
  }
);
```

- [ ] **Step 3: Add the composite index**

Create `firestore.indexes.json`:

```json
{
  "indexes": [
    {
      "collectionGroup": "orders",
      "queryScope": "COLLECTION_GROUP",
      "fields": [
        { "fieldPath": "status", "order": "ASCENDING" },
        { "fieldPath": "paidAt", "order": "ASCENDING" }
      ]
    }
  ],
  "fieldOverrides": []
}
```

- [ ] **Step 4: Wire the index file into `firebase.json`**

Find this block in `firebase.json` (around line 15-17):

```json
  "firestore": {
    "rules": "firestore.rules"
  },
```

Replace with:

```json
  "firestore": {
    "rules": "firestore.rules",
    "indexes": "firestore.indexes.json"
  },
```

- [ ] **Step 5: Verify**

Run: `node --check functions/index.js`
Expected: no output, exit code 0.

Run: `node -e "JSON.parse(require('fs').readFileSync('firestore.indexes.json', 'utf8')); JSON.parse(require('fs').readFileSync('firebase.json', 'utf8')); console.log('ok')"`
Expected: prints `ok`.

- [ ] **Step 6: Commit**

```bash
git add functions/index.js firestore.indexes.json firebase.json
git commit -m "feat: escalate unconfirmed paid orders every 2 minutes"
```

---

## Task 6: Flutter — register the `unconfirmed_order` Android notification channel

**Files:**
- Modify: `lib/services/notification_service.dart`

**Interfaces:**
- Consumes: `AndroidNotificationChannel`, `AndroidFlutterLocalNotificationsPlugin` (already imported via `flutter_local_notifications`).
- Produces: Android channel id `unconfirmed_order`, matching the `channelId` the FCM payload in Task 5 sends.

- [ ] **Step 1: Add the import for vibration patterns**

Find the import block at the top of `lib/services/notification_service.dart`:

```dart
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
```

Replace with:

```dart
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
```

- [ ] **Step 2: Register the second channel in `init()`**

Find this block (around line 21-33):

```dart
    // สร้าง channel สำหรับออเดอร์ใหม่ (Android-only — iOS ใช้ APNs ตรงๆ)
    const channel = AndroidNotificationChannel(
      'new_orders',
      'ออเดอร์ใหม่',
      description: 'แจ้งเตือนเมื่อมีออเดอร์ออนไลน์ใหม่',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    _initialized = true;
```

Replace with:

```dart
    // สร้าง channel สำหรับออเดอร์ใหม่ (Android-only — iOS ใช้ APNs ตรงๆ)
    const channel = AndroidNotificationChannel(
      'new_orders',
      'ออเดอร์ใหม่',
      description: 'แจ้งเตือนเมื่อมีออเดอร์ออนไลน์ใหม่',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);

    // ออเดอร์ค้างยืนยันเกิน 5 นาที — channel แยกจาก new_orders ด้วย
    // vibration pattern ที่ต่างชัดเจน จะได้สังเกตว่าด่วนกว่าปกติ
    const unconfirmedChannel = AndroidNotificationChannel(
      'unconfirmed_order',
      'ออเดอร์ค้างยืนยัน',
      description:
          'แจ้งเตือนเมื่อออเดอร์ที่จ่ายเงินแล้วยังไม่ได้กดยืนยันเกิน 5 นาที',
      importance: Importance.max,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList([0, 400, 200, 400, 200, 400]),
    );
    await _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(unconfirmedChannel);

    _initialized = true;
```

- [ ] **Step 3: Verify**

Run: `flutter analyze`
Expected: `No issues found!`

Run: `flutter test`
Expected: existing suite (`product_image_test.dart`, `product_test.dart`, `receipt_and_session_test.dart`, `widget_test.dart`) stays green — this task doesn't touch any code they exercise, so this is a regression check per the spec's Testing section, not new coverage.

- [ ] **Step 4: Commit**

```bash
git add lib/services/notification_service.dart
git commit -m "feat: register louder unconfirmed_order Android notification channel"
```

---

## Rollout (manual, after all tasks land — not part of this plan's automated steps)

**Order matters here — APK before `escalateUnconfirmedOrders`.** The escalation
push sends on a brand-new `unconfirmed_order` Android channel, and this app
has no `com.google.firebase.messaging.default_notification_channel_id`
fallback in `AndroidManifest.xml`. Compare the existing note at
`functions/index.js:1956` on `sendRenewalReminders`, which deliberately
reuses the old `new_orders` channel for exactly this reason: a brand-new
channel is missing on older installs and gets silently dropped by Android 8+.
Android APKs here are self-hosted (see `distribution_self_hosted.md`) —
adoption lags days-to-weeks and users can decline updates — so deploying
`escalateUnconfirmedOrders` before the APK means every not-yet-updated
device silently drops the escalation push, which is exactly the failure
Feature B exists to prevent. The Feature A pause-gating functions
(`getShopPublic`, `createOrderCheckout`, `createPromptPayOrder`,
`createTableOrder`) have no such constraint and can deploy any time.

1. Deploy the Feature A functions first (safe any time, no channel dependency):
   `firebase deploy --only functions:getShopPublic,functions:createOrderCheckout,functions:createPromptPayOrder,functions:createTableOrder`
2. Deploy hosting for the `/order` closed-state view: `firebase deploy --only hosting`
3. Cut a new Android release (APK) so the Dashboard toggle + new
   `unconfirmed_order` notification channel registration ship — follow the
   existing self-hosted-APK release workflow. Let adoption settle before
   the next step.
4. **Index deployment — verified safe as-is (checked 2026-08-03).**
   `firebase firestore:indexes` against the live project (`shop-pos-89294`)
   returns `{"indexes": [], "fieldOverrides": []}` — the project has **no**
   composite indexes deployed at all. So `firestore.indexes.json` declaring
   only the escalation index (`orders` collection group: `status` ASC +
   `paidAt` ASC) deletes nothing, and `firebase deploy --only
   firestore:indexes` is safe to run directly. Re-verify with that same
   command if significant time has passed before deploying.

   **Separate pre-existing gap found during that check** (not caused by this
   work, not blocking this rollout): two shipped queries need composite
   indexes that do not exist in the live project, so they fail at runtime
   whenever they first execute —
   - `lib/services/table_service.dart:87-88` — `tableOrders`:
     `where('status' ==) + orderBy('openedAt')` needs `status` ASC +
     `openedAt` ASC (equality plus an order-by on a different field).
   - `lib/services/bank_notification_service.dart:108-109` — `orders`:
     `where('status' ==) + where('createdAt' >)` needs `status` ASC +
     `createdAt` ASC (equality plus a range on a different field).

   (`table_service.dart:98-99` — `tableId ==` plus `status ==` — is
   equality-only and needs no composite index; Firestore serves it by
   merging single-field indexes.) These two likely mean restaurant-tier KDS
   and Android bank auto-match have never run against production, or are
   failing silently. Worth fixing in its own change: add both indexes to
   `firestore.indexes.json` and deploy.
5. Only once the APK has had time to reach most devices, deploy the
   escalation function and the (regenerated) indexes:
   `firebase deploy --only functions:escalateUnconfirmedOrders,firestore:indexes`
6. Manual checks (from the spec's Testing section):
   - Pause ordering → confirm `/order` shows the closed state for a takeaway link and a table QR link; confirm a direct `createPromptPayOrder` call while paused is rejected.
   - Place a real takeaway PromptPay order, leave it unconfirmed past 5 minutes, confirm LINE + the new push channel both fire exactly once.
