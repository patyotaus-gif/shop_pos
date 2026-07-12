# Recipe / Ingredient Inventory (Restaurant tier)

**Date:** 2026-07-12 · **Status:** Approach B approved (server-side deduction trigger); execute fully.

Sell a dish → deduct its ingredients per recipe (incl. add-on usage) → real cost in the existing profit reports. Closes the "menu stock = 9999" workaround and the biggest feature gap vs Loyverse for Thai restaurants.

**Decisions:** simple purchases + weighted-average cost; add-on options deduct too; deduction runs in ONE Cloud Function trigger on Sale creation (covers POS, table close, online orders, old app versions, offline sync).

## Data (per shop)

- `ingredients/{id}`: `{ name, unit, stock (double), avgCost, lowStockThreshold, createdAt }`
- `ingredientPurchases/{id}`: `{ ingredientId, ingredientName, qty, totalPrice, type: "purchase"|"adjust", note?, at }`
  - Receive: `newAvg = (stock*avgCost + totalPrice) / (stock + qty)`; `stock += qty` (stock≤0 before → avg = totalPrice/qty).
- `products`: `stockMode: "count" (default) | "recipe"`, `recipe: [{ingredientId, qty}]` (per dish), `recipeIngredientIds: [..]` (derived, for array-contains queries when recomputing cost).
- `ModifierOption`: optional `ingredientUsage: [{ingredientId, qty}]`.
- Rules: `ingredients` + `ingredientPurchases` owner read/write (managed in-app).

## Deduction — `onDocumentCreated(shops/{shopId}/sales/{saleId})`

1. Outside txn: read the sale's products + modifier groups; `computeUsage(items, productsById, groupsById)` (pure, Node-tested) → `{ingredientId: totalQty}` — recipe×qty for `stockMode=recipe` items + `ingredientUsage`×qty for every modifier on any item. Pre-read ingredient docs; drop missing ids (warn).
2. Transaction: re-read sale → skip if `ingredientsDeducted` (idempotency, at-least-once trigger) → `update` each ingredient `stock: increment(-qty)` → set `ingredientsDeducted: true` + snapshot `ingredientUsage` on the sale.
3. After txn: FCM to the shop for each ingredient that CROSSED its threshold (pre>threshold && post≤threshold) — no spam on every sale.
4. **Ingredient stock may go negative** — never blocks a sale; negative = recount signal. Count-mode products keep today's blocking behavior.

## Refund — `onDocumentUpdated(sales/{saleId})`

`isRefunded` false→true && has `ingredientUsage` && not `ingredientsRestored` → txn: restore increments + flag. Exact even if the recipe changed later (uses the snapshot).

## Cost auto-update (client-side, owner is online in both flows)

- Saving a recipe → `costPrice = Σ qty×avgCost` for that product.
- Receiving goods / adjusting → recompute `costPrice` of all products whose `recipeIngredientIds` contains the ingredient.
- Profit reports need zero changes (they already snapshot `costPrice` per sale item).

## App UI (Restaurant tier, ships in 1.2.20)

- **หน้า "วัตถุดิบ"** (entry: products screen action next to ตัวเลือกเสริม): list (stock+unit, avgCost, orange low / red negative), add/edit, **รับของเข้า** (qty + total price), **ปรับสต็อก** (set new count + note → adjust record, avgCost unchanged).
- **Product form**: switch นับสต็อกเอง/ใช้สูตรวัตถุดิบ; recipe rows (ingredient dropdown + qty); live cost; recipe mode hides stock fields; save writes recipe + recipeIngredientIds + computed costPrice.
- **Modifier group form**: per option, optional ingredient usage rows (same row widget).
- Recipe-mode products don't show "หมด" from stock this phase ("ทำได้อีกกี่จาน" = future).

## Edge cases

| Case | Behavior |
| --- | --- |
| ingredient deleted but still in a recipe | deduction skips it (warn log); recipe editor shows "(ถูกลบ)" row to remove |
| trigger retry / duplicate fire | `ingredientsDeducted` flag inside the txn |
| refund | restore from the sale's usage snapshot, `ingredientsRestored` flag |
| mixed count+recipe items in one sale | count items deduct product stock (existing paths), recipe items deduct ingredients (trigger) |
| fractional units | stock/qty are doubles (0.25 กก.) |
| sale created offline | deducts when it syncs |
| old sales pre-feature | trigger fires on create only — no backfill |

## Testing

- Node `scripts/test_functions_inventory.mjs`: `applyPurchase` (weighted avg incl. zero/negative start), `computeUsage` (recipe×qty, modifier usage, count-mode ignored, missing product tolerated).
- Flutter analyze/test.
- Manual E2E: create ingredients → recipe → sell (POS + table + web) → stock deducted + cost right → refund restores → receive goods updates avgCost + product cost.

## Rollout

1. functions + rules deploy — trigger is inert until a shop has recipes (no effect on existing shops).
2. APK **1.2.20+35** — all UI.

## Out of scope

FIFO/lots, "ทำได้อีกกี่จาน", sub-recipes (น้ำซุป), POs/suppliers, ingredient reports beyond the list screen.
