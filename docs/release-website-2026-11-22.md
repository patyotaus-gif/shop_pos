# Homepage device showcase — released 2026-11-22

The owner said “ปล่อยเว็บจริง” after the local homepage revisions. Published
the phone, tablet and front-of-store kiosk imagery with native Pokpok launch
branding and direct tap/swipe controls at <https://pok-pok.app>.
The kiosk remains a future concept, disclosed in the hero and accessible name.

## Release identity

- Source: `92914818a0d3c658ba40510acf764057d11c342f`, pushed to `origin/master`.
- Firebase project/site: `shop-pos-89294`; Hosting only.
- Live version: `sites/shop-pos-89294/versions/9703c7514cedaa31`.
- Published: 2026-11-22 02:01 AEDT / 2026-11-21 15:01 UTC; CLI exit 0.
- Deployment message identifies the complete source SHA above.
- Rollback: Hosting version `3e7b45bdbd61440b`; restores the previous homepage
  while retaining the same Android 1.2.81 (98) download.
- Later documentation commits do not change the published website bytes.

## Verification

- Clean reviewed source checkout; local gate rerun by the releasing session:
  home story 13 groups/eight widths; marketing 18 pages/five widths; cache
  regression 48 URLs and real browser revalidation; JS syntax and diff checks.
- The first cache invocation omitted required `MINIMATCH_MODULE` and exited
  before tests; the corrected documented invocation passed. Not a site failure.
- Hosting preflight against the previous release identified exactly 14 changed
  files: the homepage plus 13 new assets. No removed paths or other changed files.
- All 92 post-deploy Hosting file hashes match the checkout. The 14 changed
  public HTTPS responses also match local SHA-256 hashes. Live Hosting headers
  and rewrites are identical to the previous version.
- Live cache smoke passed all 48 marketing URLs: returning visitors receive
  revalidated pages; other cache policies remain unchanged.
- Live Chrome at 1440, 768 and 390 px: all device images load, tap and keyboard
  select correctly, native browser touch swipe selects the kiosk at 390 px,
  business selection works, no horizontal overflow and no page errors.
  Mobile screenshot inspected. This is browser emulation, not a physical-device
  test. No account or transaction was used.
- APK/manifest remain 1.2.81 (98); APK SHA-256:
  `4546aeb0a2612c75bdc21d47d9ca42cbd328a861484a9c3cc2be56f86306aae2`.
  Local full-file checksum and live Hosting hash match the previous verified
  release; the APK was not downloaded again or rebuilt for this website update.
- The initial release wrapper stopped on Git's successful stderr status after
  push, before Hosting ran. Remote SHA was verified; corrected native-command
  error handling retained explicit exit-code checks, and deployment completed.
- Evidence outside Git: `D:/PokpokWork/home-release-20261122/` contains gate
  results, preflight, review, triage, deploy log, config comparison, live asset
  hashes and three live browser captures.

## Independent review and retained Low findings

Fresh Codex CLI `gpt-6.2-sol`, xhigh, ephemeral read-only session reviewed the full
mechanically computed `2fa94e1..9291481` diff plus clean working-tree status in an
isolated source snapshot. Grok and Claude CLIs were unavailable. User config,
rules and MCP connections were disabled; the snapshot had no agent instruction
files. Successful source reads and a substantive report were checked. This was
source review, not browser verification. It found no issue above Low.

All four findings were checked against the actual source; mouse dragging,
short-height caption placement and pricing destination were additionally
observed in local Chrome. They are retained for the next homepage interaction
or story-layout revision, rather than changing the approved release candidate:

| Finding | Impact and reason retained | Revisit trigger |
| --- | --- | --- |
| Vertical mouse drag ending on a device can select it | Visual selection only; no navigation/data change. Native touch scrolling passed separately. | Next device gesture change or user report of unwanted selection |
| Story screenshot link changes before the 300 ms image fade finishes; anchor scrolling can briefly select an intermediate scene | A click during transition can open the next chapter's screenshot; stable scenes and all destinations remain usable. | Next story transition/navigation change |
| Sticky caption falls below a 700 px-high desktop viewport | Caption/version/demo disclosure is less visible in that desktop arrangement; screenshot and chapter text remain available, inline mobile/reduced-motion layouts differ. | Next desktop story sizing change or short-screen complaint |
| Story pricing link opens the generic retail-default pricing page after Restaurant is selected | Visitors can select Restaurant on the clearly labelled pricing page; no price/payment configuration changes. | Next segment navigation or pricing-link revision |

No backend, rules, native app, iOS or payment-provider deployment was included.
