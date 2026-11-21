# Homepage motion — 2026-11-21

The owner asked to implement the tablet-led direction after supplying the
12.83-second beverage website recording. This work changes the local marketing
homepage, not the customer ordering app or kiosk. Publication is a separate step.

## Jobs and direction

| Visitor's job | Surface | Question answered | Primary action |
| --- | --- | --- | --- |
| Understand whether this POS is for my shop | Hero | What is Pokpok and who is it for? | Download app |
| See how the app handles a day's work | Three-scene product story | What happens during sales, order/stock management and daily overview? | Move through examples or open a full image |
| Find the relevant business functions | Business picker and existing segment links | What fits a restaurant versus a retail shop? | Open the relevant segment page |

The actual app screen is the main visual. A restrained perspective tilt on the
hero tablet straightens while scrolling; the desktop story keeps the device
visible while each chapter changes its screen. There is no continuous autoplay,
scroll interception or forced scrolling. The mobile, short-window, reduced-motion
and JavaScript-disabled versions show three ordinary text/image chapters.

White/warm gray surfaces, Burgundy actions, IBM Plex Sans Thai and the existing
navigation/brand artwork remain the design base. The reference's neon palette
and beverage artwork were not copied. The business selector changes the middle
chapter to inventory for retail or order management for restaurants. It also
updates the full-image link, accessible labels and segment destination.

## Kit binding

- Existing brand palette/primitives: `public/brand.css`, `public/site-pages.css`.
- Homepage tokens: `public/home-tokens.css`; homepage primitives:
  `public/home-story.css`; enhancement: `public/js/home-story.js`.
- New colors, type scale, spacing, radii, device elevation, motion timing,
  control sizes, focus and sticky placement live in the homepage token file.
  The existing brand styles remain shared with other marketing pages.
- One light palette, minimum viewport 320 CSS px, controls at least 44 px high.
  Display headings wrap, and controlled chapter line breaks use `pre-line`.
  No new icon collection, customer forms, backend calls or payment controls.
- Desktop enhancement starts at 1000 px width and 700 px height, with motion
  allowed by the device. Scene links are normal anchors; text remains in document
  order. A failed optimized screen retains its link to the original PNG.

## Image provenance

`public/screens/story/*.webp` are 1480x924 optimized derivatives of already
published `public/screens/{pos,orders,inventory,overview}-1.2.78.png`. They retain
the actual UI and demo data without repainting or changing numbers. The four
images total 198,596 bytes. Labels disclose version 1.2.78 (95) and test-shop data;
the overview's zero sales are not presented as a customer's results or a current
build screenshot. Original PNG links remain available for inspection.

No private connected-tablet capture, competitor asset or invented current app
screen is used. Screenshot refresh to a later released build is a separate task.

## Verification and preview

Browser checks use the local static files, bundled Thai fonts and an isolated
browser context; all external requests are blocked. They do not access real
accounts or create shop transactions. Set `PLAYWRIGHT_MODULE` to the installed
Playwright module and `BROWSER_EXECUTABLE` to Chrome, then run:

```text
node scripts/test_home_story.cjs
node scripts/test_marketing_pages.cjs
node scripts/preview_marketing.cjs --port 4178
```

The homepage suite covers seven widths (320, 360, 390, 768, 1024, 1440, 1920),
business selection by mouse/keyboard, scroll and direct anchors, reduced-motion
changes, short windows, failed optimized images, and a no-JavaScript fallback.
Initial harness runs exposed capture/scroll-settling timing and a cached-image
failure simulation; captures now await transition completion, navigation waits
for scroll settling, and failed-image checks use a fresh isolated context.

Final focused run: **11 groups passed, exit 0**, including the hero transform
changing with actual scroll. Shared marketing regression: **18 pages at five
widths passed**. Script syntax and `git diff --check` passed. Browser images and
logs are in `D:/PokpokWork/home-story-20261121/`.

Two fresh newcomer visual passes examined desktop, tablet and mobile captures.
The first identified an unclear install/signup sequence; the hero now states it.
Incomplete wordmarks were screenshots taken during the existing 880 ms masthead
animation, not missing artwork; captures now wait for its completion. Retained
minor limitations: small app details require the clearly offered full-image link
on phones, retail/restaurant choices follow the hero on narrow screens, and the
public overview image shows a demo day with zero totals. Replace that image only
with a verified app capture if the screenshot library is refreshed.

Manual design audit of the changed surfaces: accessibility **4/4**, payload and
motion **4/4**, theme/token consistency **4/4**, responsive **4/4**, implementation
integrity **3/4** (**19/20**). No P0/P1 finding remained. This is a bounded design
check, not a repository security/performance audit or a native-device test.
Text contrast is at least **5.28:1** on the new surfaces; control edges are at
least **3.30:1** on their checked backgrounds. New primitive colors use tokens;
the two JavaScript progress variables have explicit zero fallbacks.

Preview: <http://127.0.0.1:4178/> (loopback only). Local HTTP readback confirmed
the new homepage marker, JavaScript, CSS and WebP asset MIME types. The server
serves only GET/HEAD from `public/`, with no write endpoint or deployment.

Saved captures: [desktop](previews/pokpok-home-motion-desktop.png),
[phone](previews/pokpok-home-motion-mobile.png). The owner can review the motion
and look locally; the public website has not been changed by this task.
