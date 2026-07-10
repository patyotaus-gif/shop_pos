# Item Add-ons + Notes (staff + customer web)

**Date:** 2026-07-10 · **Status:** Approach A approved; execute fully.

Restaurant tier can already define modifier groups (options with `priceAdjust`, required/multiSelect) and attach them to products; the staff table-order picker applies them. Gaps: (1) the config is hard to find, (2) no free-text note anywhere, (3) customers ordering via QR web get no add-on UI. This spec closes all three. Data model (`ModifierGroup`, `ModifierOption`, `OrderModifier`, `TableOrderItem.notes`) is unchanged.

## Phase 1 — Staff app (ships in APK 1.2.18)

**Discoverability**
- `products_screen.dart`: the modifier entry is a tiny icon with English tooltip "Modifier groups". Replace with a labelled action ("ตัวเลือกเสริม") so restaurant owners find it.
- `modifier_groups_screen.dart`: add a one-line explainer ("สร้างกลุ่ม เช่น ระดับความเผ็ด แล้วผูกกับเมนูในหน้าแก้สินค้า").
- `product_form_screen.dart`: in the modifier-group checklist section, add lead text + a "＋ สร้างกลุ่มใหม่" shortcut to `ModifierGroupsScreen`.

**Notes**
- `modifier_picker_sheet.dart`: add a "หมายเหตุถึงครัว" `TextField` (maxLength 200) at the bottom; `showModifierPicker` returns `({List<OrderModifier> modifiers, String? notes})`.
- Any item can carry a note: in `table_detail_screen.dart`, always open the picker sheet (even when the product has no modifier groups — the sheet then shows only the note field + add button), and pass `notes` into `TableService.itemFromProduct(notes:)` (param already exists).
- Show the note under the line item and on the kitchen ticket (kitchen_screen / table_detail line rendering).

## Phase 2 — Customer web + server (functions + hosting deploy)

**`getShopPublic`**: for each product with `modifierGroupIds`, resolve and return `modifierGroups: [{ id, name, required, multiSelect, options: [{id, name, priceAdjust}] }]` (one batched read of the shop's `modifierGroups`). Products without groups omit the field.

**Web product sheet** (`catalog.js` + `order.css`): below the quantity strip, render each group — radio (`multiSelect:false`) or checkbox (`multiSelect:true`) — with `+฿N` labels; a "หมายเหตุ" textarea. A `required` group with nothing chosen blocks the add button. The sheet returns the chosen option ids + note.

**Cart line identity** (`cart.js`): a cart line is now keyed by `productId + sorted(optionIds)` so the same dish with different add-ons stays on separate lines (mirrors Dart `modifiersEqual`). Each line stores its `optionIds`, resolved `modifiers` (name+price snapshot for display), `notes`, and the per-unit price incl. adjustments. Qty-badge/“in cart” logic sums across a product's lines.

**Server pricing** (`functions/tableorder.js` helper `priceItemsWithModifiers(items, productDocs, groupsById)` + used by both endpoints):
- `createTableOrder`: for each item, validate every `selectedOptionId` belongs to one of the product's groups, enforce `required` groups, compute unit price = base effective price + Σ chosen `priceAdjust`, store `OrderModifier` snapshots + `notes` on the `TableOrderItem`.
- `createPromptPayOrder`: switch to the same server-side pricing (base + modifiers) instead of trusting client prices — closes the existing trust gap and makes takeaway/prepaid add-ons correct. `total`/`finalAmount` computed from server prices.

## Edge cases
| Case | Behavior |
| --- | --- |
| option id not in the product's groups | server rejects: "ตัวเลือกไม่ถูกต้อง — รีเฟรชแล้วลองใหม่" |
| required group unmet | add blocked client-side; server re-checks and rejects |
| negative `priceAdjust` (e.g. ไม่เอาข้าว −5) | supported; unit price floored at 0 |
| group deleted after page load | server skips/rejects unknown options |
| note > 200 chars | trimmed to 200 (same as existing table-order note) |
| product without groups (web) | sheet shows quantity + note only |
| same dish, different add-ons | separate cart lines (web) / separate TableOrderItems (already) |

## Testing
- Node: `scripts/test_functions_tableorder.mjs` extended — `priceItemsWithModifiers` (correct sum, negative adjust floored, invalid option throws, required unmet throws); `scripts/test_order_page.mjs` — cart line identity with option ids.
- Flutter: `flutter analyze` + `flutter test`; manual picker-notes check.
- Manual post-deploy: staff order w/ add-on + note → kitchen shows it; web customer picks add-ons → price correct + snapshot on the tab.

## Rollout
1. APK **1.2.18+33** — Phase 1 (discoverability + notes).
2. functions + hosting — Phase 2 (web add-ons + server pricing).

## Out of scope
Min/max option constraints, per-option images, nested modifiers.
