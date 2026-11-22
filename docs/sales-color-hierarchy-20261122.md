# Sales color hierarchy — 2026-11-22

The owner approved implementation after the website/app color discussion.
The existing wine and warm-neutral palette remains the source of colors.
Routine information and secondary actions now use neutral theme tokens so
totals and the primary sales action have clearer emphasis.

## Jobs and color roles

| Cashier's job | Existing screen | Question answered | Primary action |
| --- | --- | --- | --- |
| Choose products | Takeaway/table catalog | Which product and price do I need? | Select a product, then open the compact basket when shown |
| Check or adjust the basket | Shared sales workspace | Are quantities and total correct? | Proceed to payment, or save the table draft when checkout is unavailable |

| Element | Previous role | Implemented role |
| --- | --- | --- |
| Photo-card price | `primary` | `onSurface`, matching normal name-card text |
| Product options/notes, grid and search | Default accented text button | `onSurface`; strengthened during release review for focused tinted name cards |
| Editable basket quantity | Default accented text button | `onSurface` |
| Display-settings button and mobile continue-shopping | Default accented secondary controls | `onSurfaceVariant` |
| Secondary Add to table beside checkout | Default accented outlined button | `onSurface` |
| Total, checkout, compact basket continuation | Brand accent | Retained |

All changes are foreground styling in existing widgets. Material disabled,
hover/focus behavior and hit targets remain inherited. No new color constants,
price calculation, callback, navigation, stock rule or persistence change.
Operational error/delete colors and selection cues retain their existing roles.
Dark theme uses its existing light neutral text and pale brand accent.

## Reviewable previews

These are actual Flutter widgets rendered with bundled Thai fonts and synthetic
products/table data, not screenshots from a live shop or a newly installed APK.

- [Before, desktop light](previews/sales-colors-before-20261122.png)
- [After, desktop light](previews/sales-colors-light-20261122.png)
- [After, desktop dark](previews/sales-colors-dark-20261122.png)
- [After, phone catalog](previews/sales-colors-phone-20261122.png)
- [After, phone dark basket](previews/sales-colors-phone-cart-20261122.png)

## Verification and delivery status

- Final existing test gate: **62 cases passed** across `sale_product_grid`,
  `sale_display`, `sales_workspace`, `table_product_picker`,
  `pos_basket_checkout`, `pos_checkout_panel` and `compact_catalog` suites.
  This includes availability, search/categories, quantities, drafts, checkout
  controls, narrow layouts and enlarged text. No real payment was performed.
- Targeted Dart analysis passed for all six changed widgets; diff check passed.
- A temporary capture fixture produced 20 before/after images at 1440, 768 and
  390 px, both light and dark, including compact baskets. Its initial untyped
  empty modifier list caused a fixture compilation error; using the model's
  `OrderModifier` type resolved it. No production fix was needed for that error.
- Parent inspected captures and the diff. A fresh visual reviewer inspected six
  final views, correctly identified the next actions and found no blocker.
  Mandatory project instructions exposed the previous color assessment first;
  this was not a fully blind walkthrough or a release code review.
- Remaining visual observations: generic synthetic product icons share labels
  such as “ข้าว”; the phone category strip shows part of the next scrollable
  chip. Neither behavior was introduced by this change.
- Isolated evidence directory: `D:/PokpokWork/sales-colors-20261122/`.
  All six tested source files match this checkout after baseline capture.
- **Released as Android 1.2.82 (99) on 2026-11-22.** Final release review
  strengthened the options/notes foreground to `onSurface` for focused tinted
  cards; all 62 tests and analysis passed again, and after-captures were refreshed.
  The signed APK was installed and checked on the connected SM-X900, then
  published and fully downloaded for digest verification. The website and
  backend were preserved. See `release-1.2.82.md` for evidence and limits.
