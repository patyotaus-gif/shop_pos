# Pricing comparison — 13 November 2026

Status: implemented locally, not pushed or deployed. Owner asked for a narrower
comparison, clearer type and more prominent differences between packages.
The supplied competitor image is a layout reference, not a new brand palette.

## Visitor jobs

| Job | Surface | Question answered | Primary next action |
| --- | --- | --- | --- |
| Find a plan for my shop | Homepage pricing / `/pricing/` | Which features do I need? | Choose retail or restaurant |
| Compare packages and cost | The same three cards | What does each upgrade add, and what will I pay? | Choose monthly/yearly, then start a trial |

## Shared design binding

- `public/brand.css` owns pricing tokens; `public/pricing.css` is the shared
  component stylesheet used by the homepage and the dedicated pricing page.
  Existing `site-base.css` and `brand.css` remain the marketing site's kit.
- Cap comparison width at 1,060px (previously 1,240px). Three separate white cards,
  16px gaps, 24px padding, 16px corners. At 1,000px and below, stack cards with a
  480px cap. Supported minimum viewport remains 320px.
- Body/features: 16px dark `--ink`; benefit heading: 18px/600; plan: 24px/600;
  price: 42px/700. Notes: 14px. Keep IBM Plex Sans Thai and the warm paper palette.
- Full retains the existing recommendation, now with a burgundy border and filled
  trial button. Other trial buttons use outlines. Selection controls have a
  visible border, focus outline and forced-colour selection check.
- Each plan has a short benefit heading, shop-fit sentence, price and trial CTA,
  followed by included features. Lite/Full explicitly say they include the prior
  package and add the listed features. All cards show the existing user allowance
  (1 / 1 / 3), verified against `lib/services/entitlements.dart:maxUsers`.
  Full's feature list still explains owner/staff allocation. Check marks are
  decorative.
- The trial CTA sits above features to make it easier to reach on phones. Trial
  duration and no-card requirement appear above all cards; separate hardware and
  payment-provider costs appear below. The dedicated page has one introduction
  with reduced top/section spacing. All three CTAs say "เริ่มทดลองใช้งานฟรี" to
  match their shared download destination, without implying a saved plan choice.
  The trial note explains that the package is chosen when registering in the app,
  matching `lib/screens/register_screen.dart`'s `TierPicker` and `createShop` call.
- Prices remain 199/399/599 baht monthly and 1,990/3,990/5,990 yearly. Annual mode
  shows the billed yearly amount and the existing monthly average separately.
  Entitlements, payments, trial duration and CTA destinations are unchanged.

## Verification

- Local browser checks: `scripts/test_pricing_layout.cjs` passed 56 states across
  320/360/390/768/1024/1440/1920px, both routes, shop types and billing cycles.
  Checks cover all three prices, switched feature content, keyboard activation,
  200% text at 390px, text contrast, target size, card spacing, reflow, forced
  colours and the trial link destination.
- `scripts/test_brand_site.cjs` passed all 18 pages at five widths, including
  segment-to-pricing links, navigation, assets, FAQ and existing no-JS fallbacks.
- Both harnesses serve current local files, inject the repository's Thai fonts,
  block external requests and do not touch accounts or production data.
- The first existing-suite invocation lacked its required Playwright environment
  variables and stopped before tests. The configured run passed. A draft layout
  probe falsely called visible baseline glyph overhang clipping; it now checks
  actual clipping rather than harmless visible vertical overflow.
- Before/after captures: `.remember/tmp/pricing-20261113/`, 1440/768/390px.
  Fresh source and screenshot-only newcomer reviews found no verified task
  blocker in round 1. Addressed their concrete polish: duplicate homepage card
  spacing, excessive introductory spacing and misleading plan-specific trial
  labels. Corrected centering of the dedicated page's introductory label.
  Round 2 source review was clean. The visual reviewer flagged the missing
  Solo/Lite user allowances as a package-selection risk; added their verified
  limits and clarified trial selection without changing product policy.
  Round 3 source review found no verified blocker; the fresh screenshot-only
  walkthrough found no visible P0/P1 blocker and correctly distinguished prices,
  user limits and upgrade features. Final local browser suites passed again.
  Isolated evidence: `D:/pokpok-pricing-review-20261113/`.
- No physical device test or deployment in this task.

## Component audit

This is a scoped pricing-component assessment, not a full-site accessibility
certification or a measured performance benchmark. No verified P0/P1 finding.

| Dimension | Score / 4 | Evidence and limits |
| --- | --- | --- |
| Accessibility | 3 | Visible labels, pressed state, focus, 48px controls, measured text contrast at least 4.5:1, 200% text and Windows forced colours passed. No screen-reader/device session. |
| Performance | 3 | Small static CSS addition, existing fonts, no additional images, libraries or remote calls. No Lighthouse/network timing claimed. |
| Theming | 4 | New component values use shared brand tokens; existing light marketing palette retained. Forced colours checked; no separate dark website theme claimed. |
| Responsive | 4 | Seven widths from 320 to 1920px, one-column reading on narrow screens, no verified overflow in covered states. Rendered desktop/tablet/phone captures inspected. |
| Implementation integrity | 4 | Same component CSS on both routes, existing toggle logic and destinations preserved, fallback content and broader marketing suite pass. |
| Total | 18 / 20 | Excellent in the scoped checklist; platform limitations above still apply. |

Optional next iteration: a compact mobile overview could reduce scrolling between
all three plans. Keep the readable stacked cards for this change; avoid a second
set of duplicated pricing/features without a concrete usability need. The Full
recommendation is retained from the existing site, with its shop-fit description.
The final visual reviewer also suggested carrying the selected plan through to
signup. Current buttons intentionally retain the shared download destination;
the visible note explicitly says selection happens during app registration.
Plan persistence across website/download/app is separate functional work, not
implied by these styling changes. No additional mobile summary or signup flow
was added in this task.
