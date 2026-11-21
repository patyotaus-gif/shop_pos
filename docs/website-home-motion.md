# Homepage motion — device direction updated 2026-11-22

The owner clarified on 2026-11-22 that the cans in the reference should become
three physical devices: a phone, tablet and front-of-store display. The previous
tablet-only hero misunderstood that emphasis. The revised hero keeps all three
devices visible; selecting one rotates and moves that device to the front.
The owner's next revision replaces all three screens with app launch branding
and replaces the separate selector with direct tap and horizontal drag/swipe.
Scroll also changes the central
device's angle on desktop. This work changes the local marketing homepage,
not the customer ordering app or kiosk. Publication is a separate step.

All three screens use the native app's Burgundy launch ground and white mortar
plus Pokpok wordmark. No added screen copy or below-device description is shown.
The existing hero text still identifies the front-of-store display as a future
concept; its accessible name also says it is unavailable. Self-ordering has not
been built. Actual app feature screenshots remain in the story below the hero.

The owner then requested real-device imagery. The hero now uses licensed,
realistic image frames for Galaxy S24 Ultra, Galaxy Tab S7 (landscape) and a
self-service kiosk in place of the CSS-drawn hardware. Source files, usage terms,
dimensions and hashes are recorded in [device image sources](website-device-image-sources.md).
The app launch screens are still ordinary HTML/CSS behind the frame apertures;
source image pixels are unchanged. No added device descriptions or selector row.

## Jobs and direction

| Visitor's job | Surface | Question answered | Primary action |
| --- | --- | --- | --- |
| Understand whether this POS is for my shop | Hero | What is Pokpok and who is it for? | Download app |
| See which device fits my shop | Hero device imagery | Which device formats are shown? | Tap a device or drag/swipe horizontally |
| See how the app handles a day's work | Three-scene product story | What happens during sales, order/stock management and daily overview? | Move through examples or open a full image |
| Find the relevant business functions | Business picker and existing segment links | What fits a restaurant versus a retail shop? | Open the relevant segment page |

Device imagery is the hero's main visual, following the owner's correction.
The device images themselves are native buttons; no separate selector is
shown. Tap/click chooses a device, horizontal touch or mouse drag advances one
position and wraps, and Left/Right arrows also move selection and focus. A short
drag snaps back; pointer cancellation does not select. Vertical gestures retain
native page scrolling, and the touch surface allows pinch zoom. Reduced motion
removes drag feedback and transitions while keeping selection functional.
Without JavaScript the three splash screens remain visible as disabled controls.

Owner preference (2026-11-22): no explanatory copy inside the devices or separate
labelled device controls. This overrides the earlier labelled selector; the
visible instructions and changing captions were removed to keep the imagery
clean. Accessible names, pressed state, focus outline and a screen-reader status
remain. The cursor signals drag on desktop; there is no autoplay gesture hint.
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

`public/brand/launch/white-{bowl,pestle}.png` are byte-identical copies of
`assets/icon/splash/white-{bowl,pestle}.png`; `wordmark.png` is a byte-identical
copy of `assets/brand/pokpok-wordmark.png`. The wordmark's CSS white tint matches
the native widget's white `srcIn` tint. The launch color is `--wine` (#7a1f2b),
matching `lib/widgets/pokpok_launch_motion.dart`. Mark/letter proportions follow
the settled native launch composition (146:125, mark height .84). The owner's
no-description request omits the native `POINT OF SALE` line. No raster edits,
generated logos, sound, or ongoing launch animation are introduced.

`public/screens/story/*.webp` are 1480x924 optimized derivatives of already
published `public/screens/{pos,orders,inventory,overview}-1.2.78.png`. They retain
the actual UI and demo data without repainting or changing numbers. The four
images total 198,596 bytes. Labels disclose version 1.2.78 (95) and test-shop data;
the overview's zero sales are not presented as a customer's results or a current
build screenshot. Original PNG links remain available for inspection.

No private connected-tablet capture, competitor asset or invented current app
screen is used. Screenshot refresh to a later released build is a separate task.

## Verification and preview

Latest automated evidence: 2026-11-22 realistic hardware-image revision. The following browser
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
1920), the three loaded image frames at their original proportions, the official
logos without on-screen prose, direct device click/Enter/arrow
keys and mouse dragging, the selected model's actual transform, overflow for each
selected device, business selection, scroll/direct anchors, reduced motion,
short windows, failed story images, and a no-JavaScript fallback. A dedicated
touch context uses Chromium's native touch dispatch to test left/right swipes,
wrap-around, direct tap, short-drag snapback, cancellation, vertical page scrolling
without a selection change, and reduced-motion swiping. These are browser touch
events, not an Android/iOS hardware test.

Final focused hardware/touch run: **13 groups passed, exit 0**. Shared marketing
regression for this revision: **18 pages at five widths passed, exit 0**. Script syntax and
`git diff --check` passed. Current captures are in
`D:/PokpokWork/home-hardware-20261122/`. Earlier launch/swipe findings were
reproduced and fixed before that revision's passing run:

- At 1280 px the initial transform transition could briefly put devices outside
  the viewport. Transitions now start with interaction, avoiding an entrance
  animation from an unpositioned state; geometry remains checked without clipping.
- Native touch implicitly captured the device button; transferring capture to
  the stage bubbled a child `lostpointercapture` event that cancelled the swipe.
  Only loss from the stage itself now cancels. The same native touch test that
  failed before the fix passed after it; mouse-only checks had not caught this.
- Visual review found that a native button vertically centered the kiosk shell
  in its tall target, leaving a 40.65 px gap above it at 390 px. Anchored the shell
  at the top; the regression checks its rendered top against the button bounds.
  A second visual pass confirmed that the gap is gone at 390 and 1280 px.

A fresh screenshot walkthrough of the preceding launch/swipe build reviewed five desktop/phone/tablet captures and
found no high/medium comprehension issue. It noticed the kiosk focus gap (fixed)
and two minor tradeoffs: without visible controls swiping is less discoverable,
and the foreground tablet partly covers the phone on narrow screens. The owner
explicitly requested direct manipulation without labelled controls; no helper
copy was added. Review was not fully blind because mandatory project docs were
read first. The subsequent hardware-image review checked five captures and found
no material issue: devices retain their proportions, image bounds and logo
alignment. Minor side-device occlusion remains on narrow screens. Actual feature
UI remains available in the lower story, with full-image
links. Captures wait for device transitions and the existing masthead animation.

Manual design audit, rechecked for the device revision: accessibility **4/4**, payload and
motion **4/4**, theme/token consistency **4/4**, responsive **4/4**, implementation
integrity **3/4** (**19/20**). No P0/P1 finding remained. This is a bounded design
check, not a repository security/performance audit or a native-device test.
Hero text retains **5.99:1** secondary and **14.07:1** primary contrast. Existing
story surfaces retain at least **5.28:1** text and **3.30:1** control-edge contrast.
The entire device silhouette is the action target, with a keyboard focus outline;
the decorative logo layers are excluded from assistive tech while native buttons
provide names and pressed state. All launch artwork matches the app source bytes.

Preview: <http://127.0.0.1:4178/> (loopback only). Local HTTP readback confirmed
the new homepage marker, JavaScript, CSS and WebP asset MIME types. The server
serves only GET/HEAD from `public/`, with no write endpoint or deployment.

Saved captures: [desktop](previews/pokpok-home-motion-desktop.png),
[phone](previews/pokpok-home-motion-mobile.png),
[kiosk selected](previews/pokpok-home-devices-kiosk.png). The owner can review the motion
and look locally; the public website has not been changed by this task.
