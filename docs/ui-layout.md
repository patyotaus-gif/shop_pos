# Adaptive app layouts

- Signup starts with Google, Apple or an explicit email choice. Email credentials are validated before shop setup; controllers survive returning to the account step. Social accounts proceed directly to shop setup. Existing consent and shop creation rules still apply.
- Login content is capped at 520 logical pixels; signup at 640. Forms stay centered on tablets and scroll when the keyboard is open.
- Settings have six categories: shop, account/plans, management, payments, notifications and appearance. At 900 logical pixels the category menu sits on the left; smaller screens use horizontally scrollable category chips. Content is capped at 760 pixels. Parent-owned text controllers retain unsaved input while switching categories; saving still uses each section's existing button.
- POS uses the available content width (after the app navigation). At 900 pixels it shows a searchable/filterable product grid beside a 380-pixel cart and checkout panel. Smaller layouts keep the cart below search/category controls, with a horizontal catalog when height permits. All-products selection now shows products, not only search results. Out-of-stock and pending-payment restrictions remain in place.
- Social authentication buttons retain their 360-pixel width cap and 48-pixel minimum touch height.
- Cart items put the product name, unit price and options above a separate subtotal and quantity-control row. Controls wrap on narrow screens instead of squeezing the name beside a trailing toolbar. Regression tests cover 296/356-pixel item widths with 150% text scaling and quantity editing/removal.
- Kitchen display and kitchen-printer mode use the same responsive tickets. Available workspace width excludes navigation and is capped at 1120 logical pixels. At 900 pixels, two tickets sit side by side; narrower workspaces use one centered column with tickets no wider than 600 pixels. The two-column threshold increases with text scaling so enlarged text keeps a readable single column. Each ticket retains its full natural height and notes; ready, future-pickup and history groups use the same layout and retain their existing chronological order.
- Kitchen printer guidance and history switches have width caps, and print controls wrap with gaps instead of stretching across the workspace. A visible hint explains that table-food rows can be tapped when ready. Printing and order-state behavior are unchanged.

## Sales catalog presentation (implemented 2026-11-12)

| Cashier job | Surface | Question answered | Primary action |
| --- | --- | --- | --- |
| Pick familiar products quickly | POS / takeaway / table product picker / offline catalog | Which item am I adding? | Tap a product |
| Choose photos or names | Catalog controls | Which view suits this counter? | Select the display mode |
| Recognize a category by color | Category color dialog | Which color should these buttons use? | Choose a category and color |

- `รูปภาพสินค้า` is the default; `ปุ่มชื่อสินค้า` removes the image area and shows category, full wrapped product name, price, promotion original price and availability. Changing modes preserves the cart/table draft and existing sale logic. The photo mode and inventory-management catalog retain their existing appearance.
- `สีปุ่ม` opens a category picker with five named soft colors and a default/reset option. Categories remain written on the tiles; color alone never identifies an item or availability. Unavailable tiles use a neutral surface, block icon and text label. Selected table items have a check, quantity and stronger border. Additional per-product color overrides are not part of this version.
- Colors are centralized in `lib/theme/sale_button_palette.dart` and use the app theme's readable text and borders in light/dark mode. Mode controls use standard ChoiceChips and wrap; the color dialog is bounded, scrollable and closable.
- Preferences live in SharedPreferences, keyed by shop on this device (`saleDisplay.v1.*`), shared between its owner/staff and local sales surfaces. They do not sync to another device or change product records, online customer menus, prices or permissions. Failed saves keep the previous choice and show a retry message; unreadable saved data has a retry control.
- Name-mode grid heights measure the longest displayed name/category at the current width and text scale. This preserves full names instead of truncating similar menu names. Existing pinned products and search remain available.

Sales display validation: all 34 tests passed across `sale_display_test`, `sale_product_grid_test`, `table_product_picker_test`, `product_catalog_test` and `offline_access_test`; targeted Dart analysis passed. Persistence/isolation, malformed preferences, draft preservation, offline base prices, disabled actions and color contrast are covered. Layout checks cover 320/390/768/1440 widths, light/dark themes and 200% text, including the color dialog. Two fresh visual review rounds ended clean for the rendered fixtures; previews are in `.remember/tmp/sale-display/`. On 2026-11-13, SM-X900 running 1.2.77 (94) passed photo/name switching, category colors, cart retention and saved preferences after restart. Temporary draft cleared and photo/default color restored. A new checkout/payment was not performed. Publication evidence is in `docs/release-1.2.77.md`.

Validation includes signup step/back navigation, consent enforcement, settings category navigation and retained input at mobile/tablet sizes, plus the existing transaction/offline/access tests. Physical-device checkout, keyboard and printer acceptance remain separate from widget tests.

Kitchen validation (2026-11-12): 34 tests passed across `kitchen_layout_test`, `kitchen_output_test`, `kitchen_regression_test` and `kitchen_chef_journey_test`; targeted Dart analysis passed. Real theme/font captures cover 390/768/1440, both output modes and light/dark themes. Geometry checks cover ticket widths, two-column ordering, narrow workspace, enlarged text, history and future groups; callbacks and scrolling are exercised with local fixtures. Existing tests include 320-pixel phones, 200% text and long tickets. On 2026-11-13, the corrected 1.2.77 (94) app was checked on SM-X900: both kitchen modes use bounded two-column tickets with usable history/guidance/print controls. Test-shop output mode restored to display. Physical printing was not performed.

## Sales-screen space review (2026-11-13, original recommendation)

Owner reports that too many controls compete with selling. This is a read-only
assessment of released 1.2.77, not an approved redesign or implementation.
Evidence: `pos_screen.dart`, `restaurant_sales_screen.dart`,
`sale_display_controls.dart`, `pos_checkout_panel.dart`,
`mobile_sales_workspace.dart`, `side_navigation_shell.dart`, and the release's
SM-X900 screenshot/XML in `D:/pokpok-release-1.2.77/`. No device is connected in
this turn. The 390px catalog fixture contains only catalog components, so it is
not evidence of the complete mobile sales screen.

The empty takeaway screenshot has eight stacked levels before product tiles:
channel switch, page title/staff/scanner, offline entry, bundle action, search,
display controls, categories and pinned products. First product starts at y=962
on the 2960x1848 capture. This describes that state, not all shops or carts;
offline entry already disappears once the cart has items.

Recommended first pass (owner subsequently approved; implementation below):

| Current control | Proposed placement | Reason / constraint |
| --- | --- | --- |
| Photo/name/color row | One labelled `จัดหน้าขาย` control beside search, opening display settings | Infrequent configuration should not occupy its own row throughout selling; keep mode/color available |
| Separate bundle action above search | `ชุดสินค้า` tab alongside product categories when available | Keep active selling one tap away without another toolbar |
| Pinned-product strip duplicates products | `รายการโปรด` tab in the category row | Keep fast access; the assumption that one extra tab choice is acceptable needs cashier feedback |
| Separate offline entry in a healthy empty cart | `เพิ่มเติม` menu | Keep offline status, pending-sale recovery and no-double-payment warnings prominent when applicable |
| Channel switch plus duplicate takeaway heading | A single compact contextual header with channel and cashier | Preserve channel clarity and safe user switching; retain readable staff identity |
| Tablet discount/debt/payment button group | Payment primary; discount/debt in a bill-actions menu | Mobile already uses a secondary menu. Any applied discount remains visible in totals |

Keep search with scanner, category navigation, full distinguishable names and
prices, stock-unavailable state, selected quantities, total and next action easy
to reach. Loyalty should be a compact `เพิ่มลูกค้า` action in the bill header,
with selected customer/points visible once attached, rather than hidden deeply.
On tablets retain catalog/cart side by side. Sidebar collapse and device-level
remembering already exist; use those before adding a second navigation setting.
On phones retain product/cart views and a fixed cart count/total; payment remains
fixed in the cart. Do not shrink text or touch targets to solve toolbar clutter.

Optional later refinement: show one total when subtotal equals net; expand the
breakdown when discounts or other adjustments apply. Improve compact name-tile
spacing while preserving full names, prices, availability and large-text support.

The hierarchy follows progressive disclosure: keep frequent selling visible and
defer occasional settings, with clearly labelled access (NN/g, read 2026-11-13):
https://www.nngroup.com/articles/progressive-disclosure/
Relative usage frequency is a design hypothesis; no cashier usage analytics were
examined. A future implementation needs real-component phone/tablet previews,
owner review and cart/checkout/accessibility regression checks. No runtime or
deployment changes in this assessment.

## Sales entry and workspace (2026-11-13, local implementation)

The owner approved the space-review changes and changed the entry requirement:
restaurant sales must start with `ทานที่ร้าน` / `สั่งกลับบ้าน`. Retail continues
directly to its catalog. The staff Sales tab selects the same entry from the
authenticated workspace's shop type/tier, with loading and retry states and
access to previously prepared offline profiles while unavailable. Its
separate Tables tab remains available as a shortcut.

| Cashier job | Screen | Question answered | Primary action |
| --- | --- | --- | --- |
| Start a restaurant sale | Sales entry | Dine-in or takeaway? | Choose one of the two channels |
| Serve a seated customer | Table grid | Which table? | Open its bill |
| Add takeaway/retail products | Product catalog | Which item and quantity? | Tap products / scan a barcode |
| Finish a sale | Basket | What is being charged? | Check total and pay |
| Adjust the sales layout | Display dialog | Photos, names or category colors? | Choose the display preference |

- The entry chooser is bounded to 640 logical pixels, with two choices side by
  side on wide screens and stacked on phones/large text. Workflows mount on first
  use and remain mounted when returning via `เลือกประเภทการขาย`; returning does
  not clear the takeaway cart. The chooser is the initial state of the restaurant
  workspace, not a forced reset after every transaction or main-navigation tap.
- The active catalog has two header rows: search/display settings and a horizontal
  category row. `จัดหน้าขาย` opens the existing mode/color controls. At narrow
  widths with enlarged text, its button wraps instead of shrinking the search.
- `รายการโปรด` replaces the separate duplicate pinned-product strip. The last
  chosen catalog tab is remembered per shop/device, including rapid tab changes.
  Catalog state, search and pending preference writes survive crossing the
  phone/tablet breakpoint. Removed categories fall back to All. Internal tab IDs cannot collide with real
  category names. A real category named `รายการโปรด` remains a separate category.
- `ชุดสินค้า` is an action in the category row and opens the existing validated
  bundle chooser. It remains reachable even if no bundles exist; that chooser
  already provides the empty state, without an additional availability fetch.
- Typed name/barcode search respects the selected category/favorites. Results
  use selectable cards with full names, current/original price, barcode and stock
  quantity. Selecting a result clears the query. The scanner remains available
  while typing and preserves the query when opened. Stock
  and recipe availability still come from the product model; unavailable products
  cannot add to the cart. Empty search returns to the selected category's grid.
- Cashier identity is in the compact header; the account icon changes user.
  `เพิ่มเติม` contains `ขายออฟไลน์ / บิลค้าง`, disabled while the cart has items
  or recovery/payment/loyalty work is pending. Pending-sale recovery and the
  no-double-payment warning remain above the workspace.
- Tablet catalog/cart remain side by side; mobile retains product/cart navigation.
  `เพิ่มลูกค้า` is in the bill header. Attached customer/points remain above items.
  Payment is primary; discount/debt are in the bill menu at all widths with existing
  permission checks. Only net total is shown without a discount; an applied
  discount reveals subtotal/discount underneath. Payment processing is unchanged.

Verification: 70 focused tests passed across 8 test files, followed by an 18-test
rerun after the search-result visual refinement. Targeted Dart analysis passed.
Real Flutter catalog/table/cart/checkout components use injected fixture data at
320/390/768/1440 logical pixels, normal/200% text, and light/dark themes. Coverage
includes chooser/cart retention, quantity edits, search/scanner callbacks,
availability, display/color dialogs, error/retry, staff entry, disabled actions,
and a queued category write across wide-to-narrow rotation. A real drag reaches
lower product prices/stock at 200% text. Captures explicitly repaint retained
layers; the earlier omitted AppBar was a widget-test snapshot artifact.

Fresh isolated read-only Codex CLI reviews were used after Claude's usage limit.
Source review round 3 found no concrete regression after the fixes. Visual round
3 found an understandable search add cue and no hard stop, including the updated
dine-in captures. Search rows are fully tappable; quantity controls retain their
48-pixel targets despite small glyphs. Local evidence: `D:/pokpok-sales-workspace-review/` and
`.remember/tmp/sales-workspace/`. Category-scroll cues and immediate-save wording
in the existing color dialog remain optional polish, not verified functional
failures. These are local widget journeys, not authenticated checkout, real
keyboard/scanner, or physical-device acceptance. No device was connected, and
no push, app build, backend change or deployment was performed during the initial
implementation. Subsequently released in Android 1.2.78 (95): 53 relevant tests
and targeted analysis reran successfully; signed APK and public download verified.
No physical device was connected at publication. A subsequent SM-X900 test of
installed 1.2.78 (95) passed owner-mode chooser/cart retention, photo/name/colour
controls, favourites/search, portrait/landscape, and cash/change entry with the
software keyboard. Checkout was cancelled and its draft cleared; a completed
sale, staff/offline/scanner journey and physical print were not tested. Both
kitchen layouts were inspected and display mode restored. That pass found a
keyboard left open after cancelling checkout. See `release-1.2.78.md`.

Payment keyboard follow-up (2026-11-13, local): the shared payment entry now
unfocuses the active input before opening the sheet, so closing it does not
restore the catalog search's focus and keyboard. Search text and cancelled
cart contents remain intact; reopening cash payment still focuses the amount.
Six new regressions failed before the fix. All 50 focused checkout/cart/workspace
tests and targeted analysis pass; eight exit/focus cases cover cancel, route
back, swipe and confirmation on Android/iOS widget configurations. An isolated
native fixture using the actual payment sheet passed on SM-X900: Samsung's
keyboard closed after cancel/system back, search and the 220-baht mock cart
remained intact, and reopening focused the cash field. The fixture had no
Firebase initialization and was removed after testing; production 1.2.78 (95)
was restored to the foreground unchanged. This fix is not yet in the published
APK. No completed real sale or physical iOS test is claimed. Evidence:
`D:/pokpok-payment-keyboard-20261113/`.
