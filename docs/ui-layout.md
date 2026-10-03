# Adaptive app layouts

- Signup starts with Google, Apple or an explicit email choice. Email credentials are validated before shop setup; controllers survive returning to the account step. Social accounts proceed directly to shop setup. Existing consent and shop creation rules still apply.
- Login content is capped at 520 logical pixels; signup at 640. Forms stay centered on tablets and scroll when the keyboard is open.
- Settings have six categories: shop, account/plans, management, payments, notifications and appearance. At 900 logical pixels the category menu sits on the left; smaller screens use horizontally scrollable category chips. Content is capped at 760 pixels. Parent-owned text controllers retain unsaved input while switching categories; saving still uses each section's existing button.
- POS uses the available content width (after the app navigation). At 900 pixels it shows a searchable/filterable product grid beside a 380-pixel cart and checkout panel. Smaller layouts keep the cart below search/category controls, with a horizontal catalog when height permits. All-products selection now shows products, not only search results. Out-of-stock and pending-payment restrictions remain in place.
- Social authentication buttons retain their 360-pixel width cap and 48-pixel minimum touch height.
- Cart items put the product name, unit price and options above a separate subtotal and quantity-control row. Controls wrap on narrow screens instead of squeezing the name beside a trailing toolbar. Regression tests cover 296/356-pixel item widths with 150% text scaling and quantity editing/removal.

Validation includes signup step/back navigation, consent enforcement, settings category navigation and retained input at mobile/tablet sizes, plus the existing transaction/offline/access tests. Physical-device checkout, keyboard and printer acceptance remain separate from widget tests.
