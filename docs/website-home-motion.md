# Homepage motion — device direction updated 2026-11-22

The owner clarified on 2026-11-22 that the cans in the reference should become
three physical devices: a phone, tablet and front-of-store display. The previous
tablet-only hero misunderstood that emphasis. The revised hero keeps all three
devices visible; selecting one rotates and moves that device to the front,
with its use and availability shown below. Scroll also changes the central
device's angle on desktop. This work changes the local marketing homepage,
not the customer ordering app or kiosk. Publication is a separate step.

The phone and kiosk show branded device illustrations, explicitly labelled as
illustrations rather than native app screenshots. The tablet uses the existing
real demo screenshot without stretching or cropping it into a portrait screen.
The kiosk option and persistent caption identify it as a concept: customer
self-ordering has not been built. Do not remove that distinction to imply that
three fully working client modes are available.

## Jobs and direction

| Visitor's job | Surface | Question answered | Primary action |
| --- | --- | --- | --- |
| Understand whether this POS is for my shop | Hero | What is Pokpok and who is it for? | Download app |
| See which device fits my shop | Hero device selector | What can I use now, and what is a future concept? | Select phone, tablet or front-of-store display |
| See how the app handles a day's work | Three-scene product story | What happens during sales, order/stock management and daily overview? | Move through examples or open a full image |
| Find the relevant business functions | Business picker and existing segment links | What fits a restaurant versus a retail shop? | Open the relevant segment page |

Device silhouettes are the hero's main visual, following the owner's correction.
Native buttons select each form; Left/Right arrows also move selection and focus.
The desktop story below keeps the tablet
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

Latest automated evidence: 2026-11-22 device revision. The following browser
suites are manual local checks, not a deployed-site or native-device test.

Browser checks use the local static files, bundled Thai fonts and an isolated
browser context; all external requests are blocked. They do not access real
accounts or create shop transactions. Set `PLAYWRIGHT_MODULE` to the installed
Playwright module and `BROWSER_EXECUTABLE` to Chrome, then run:

```text
node scripts/test_home_story.cjs
node scripts/test_marketing_pages.cjs
node scripts/preview_marketing.cjs --port 4178
```

The homepage suite covers eight widths (320, 360, 390, 768, 1024, 1280, 1440,
1920), physical-device selection by click/Enter/arrow keys, the selected model's
actual transform, concept disclosure, overflow for each selected device,
business selection, scroll and direct anchors, reduced-motion changes, short
windows, failed optimized images, and a no-JavaScript fallback.
Initial harness runs exposed capture/scroll-settling timing and a cached-image
failure simulation; captures now await transition completion, navigation waits
for scroll settling, and failed-image checks use a fresh isolated context.

Final focused run: **12 groups passed, exit 0**, including the selected hardware
changing with click and its angle changing with actual scroll. Shared marketing
regression: **18 pages at five widths passed, exit 0**. Script syntax and
`git diff --check` passed. Device captures are in
`D:/PokpokWork/home-devices-20261122/`. The first run caught a 1 px horizontal
overflow at 768 px: perspective enlarged the decorative stage ellipse. Insetting
that ellipse fixed it without hiding overflow. The same geometry check passed
after the fix; device selection is checked at all eight widths.

The 2026-11-22 device walkthrough reviewed six captures at 1280, 768 and 390 px.
It found no high-severity problem and correctly distinguished currently supported
phone/tablet formats from the kiosk concept. It was a fresh session, but not a
fully blind review: mandatory HANDOFF was read before screenshots. Two minor
limitations remain: the branded phone illustration cannot demonstrate native
mobile UI, and the existing nav's trial link has a different label from the hero
download link although both reach installation. The hero explains install then
signup; a verified portrait app screenshot is future evidence, not a fabricated
screen in this revision.

The preceding 2026-11-21 tablet implementation had two newcomer visual passes.
The first identified an unclear install/signup sequence; the hero now states it.
Incomplete wordmarks were screenshots taken during the existing 880 ms masthead
animation, not missing artwork; captures now wait for its completion. Retained
minor limitations: small app details require the clearly offered full-image link
on phones, retail/restaurant choices follow the hero on narrow screens, and the
public overview image shows a demo day with zero totals. Replace that image only
with a verified app capture if the screenshot library is refreshed.

Manual design audit, rechecked for the device revision: accessibility **4/4**, payload and
motion **4/4**, theme/token consistency **4/4**, responsive **4/4**, implementation
integrity **3/4** (**19/20**). No P0/P1 finding remained. This is a bounded design
check, not a repository security/performance audit or a native-device test.
Hero text contrast is **5.99:1** for secondary text and **14.07:1** for primary
text; selected Burgundy text is **8.56:1** on its rose ground. Control edges are
**3.74:1** against the hero ground. Existing story surfaces retain at least
**5.28:1** text and **3.30:1** control-edge contrast. Device geometry and small
on-device lettering are decorative illustrations, hidden from assistive tech;
their meaningful descriptions are ordinary page text. New primitive colors use
tokens; both JavaScript progress variables have explicit zero fallbacks.

Preview: <http://127.0.0.1:4178/> (loopback only). Local HTTP readback confirmed
the new homepage marker, JavaScript, CSS and WebP asset MIME types. The server
serves only GET/HEAD from `public/`, with no write endpoint or deployment.

Saved captures: [desktop](previews/pokpok-home-motion-desktop.png),
[phone](previews/pokpok-home-motion-mobile.png),
[kiosk selected](previews/pokpok-home-devices-kiosk.png). The owner can review the motion
and look locally; the public website has not been changed by this task.
