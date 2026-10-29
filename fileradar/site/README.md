# FileRadar sales website (static, no build step)

A self-contained static site: `index.html` + `styles.css` + `script.js` +
`config.js`. No external dependencies — no CDNs, fonts, trackers, or
analytics. System fonts only; visuals are original CSS/SVG built for this
page. No Homy text, images, or assets were used, and no stock photos.

## Preview locally

```sh
cd ~/workspace/goals/fileradar/site
python3 -m http.server 8000
# open http://localhost:8000/ in a browser
```

Or open `index.html` directly in a browser (the theme toggles and pricing
logic work from `file://` too, since everything is relative). The "Try the
demo" button links to `../demo/` (the FileRadar web demo directory, relative
to this folder).

## Design

The layout follows the 10 principles from the verified design-awards
research (`../files/design-awards-research.md`): native Mac feel, one job
per section, content-forward visuals, plain-language copy, a two-look
theme (colourful / minimal) plus a light/dark toggle, micro-delight in
small details (hover lift on feature cards, animated-by-CSS chips),
accessibility (semantic HTML, skip link, visible focus states, alt/aria
labels, `prefers-reduced-motion` support), and trust through restraint
(no hype numbers anywhere). No award winners are named on the public
site, by design — the research file is internal only.

## Muse chat (feature cards only, no live connection)

- The feature grid now has 30 cards (was 27). The three new cards are
  Muse chat in FileRadar, extremely secure login, and voice.
- The Muse chat card and the note under the grid state plainly: chat is
  powered by Muse Spark through Meta's Model API and requires a Meta
  developer configuration; the user's personal Muse app history and
  memory do not carry over into FileRadar; and FileRadar is not
  affiliated with or endorsed by Meta.
- The login card describes only a secure authorisation flow with
  credentials kept in the Mac Keychain — no endpoints, keys, or
  credentials are named or invented. The voice card says voice is part
  of the Muse chat experience in the app and that the web demo has no
  live voice session.
- No live Muse connection is claimed anywhere on the site. Pricing,
  the Buy button's "purchases are not open yet" notice, and the refund
  FAQ (support@metaphasic.net only) are unchanged.

## What is placeholder (honest status)

- **Domain:** none registered/claimed. `config.js` carries a
  `DOMAIN_PLACEHOLDER` TODO; the page uses relative links only and sets
  no canonical URL to a made-up live address.
- **Launch date:** `config.js` `LAUNCH_DATE` is `null`. The pricing
  section therefore states the launch window has not started, and shows
  $8-at-launch / $19-after. Set a real `YYYY-MM-DD` date there at launch
  and the page computes the window (first 60 days) and the current price
  itself. The date is a config value, never hardcoded to today.
- **Stripe wiring:** NOT wired. The Buy button reveals an honest
  "purchases are not open yet" notice. At launch it must be wired to the
  licensing backend's Stripe Checkout session endpoint (test mode during
  development; live keys only at launch, handled by the backend, never by
  this static page). No payment is taken from this page and no card
  details are collected here.
- **Download binary:** does not exist yet. The hero offers the demo link
  (`../demo/`) instead of a download, and the footer states this plainly.
- **Testimonials section:** intentionally omitted. No fabricated
  testimonials, sales/revenue numbers, trust badges, review stars, or
  "as seen in" claims appear anywhere on the site.
- **Refund terms:** intentionally NOT invented. The FAQ refund answer
  only points to support@metaphasic.net.
- **Personal info:** none anywhere. The only contact shown is the
  company address support@metaphasic.net.

## Verified

- All files exist in `~/workspace/goals/fileradar/site/` and reference
  each other by relative path only (checked by reading the files and by
  `grep` for external URLs — none except none at all; see UNTESTED).
- Pricing copy and the JS pricing logic agree: $8 launch / $19 regular /
  60-day window / 1 Mac / USD / one-time, all driven by `config.js`.
- The FAQ refund answer contains no invented terms or time windows.
- The Finder comparison table is worded as "not a built-in Finder view"
  rather than claiming tasks are impossible in Finder, and carries an
  explanatory caption.
- No personal names, emails, phones, or addresses appear; only
  support@metaphasic.net.

## UNTESTED

- The site has NOT been rendered in a browser in this run (no live
  browser is available to this agent). Visual layout, the theme toggles
  (colourful/minimal, light/dark), the Buy notice reveal, and the pricing
  computation have been written and reviewed but not click-tested.
  Before publishing, open it in a browser (see Preview above), toggle
  both theme controls, click Buy, and check the pricing section with
  `LAUNCH_DATE` set and unset.
- The `../demo/` link target exists as a directory in the goal workspace
  but the demo's own contents were not verified by this agent.
- Nothing here is published, and no payment flow exists to test.

## Security posture (hardening pass, 27 Oct 2026)

- **No data collection:** no `<form>`, no analytics, no trackers, no
  third-party embeds, no network requests (`fetch`/XHR/beacon: none).
  The only scripts are local `config.js` and `script.js`; the only
  stylesheet is local `styles.css`. No external URLs appear in the
  page code; the only cross-page link is the relative `../demo/`.
- **localStorage inventory (only storage used):** `fileradar-look`
  (`colourful` | `minimal`) and `fileradar-mode` (`light` | `dark`) —
  theme preferences only, set from the page's own toggle buttons.
  Stored values are validated against those allowlists before use;
  anything else falls back to the defaults. No serials, emails, paths,
  or secrets are stored anywhere on this site.
- **No inline event handlers, no `javascript:` URLs** in `index.html`;
  the site script uses `textContent`/`setAttribute` only, never
  `innerHTML`.
- **Buy button unchanged:** it still only reveals the honest
  "purchases are not open yet" notice; no payment is taken and no card
  details are collected. Pricing is untouched (`config.js`: $8 launch,
  60 days, $19 regular, 1 Mac, USD).
- **No testimonials, sales numbers, trust badges, competitor names or
  prices, or personal info** anywhere on the site; the only contact is
  support@metaphasic.net. (The comparison table names Finder, the Mac's
  built-in file browser, with no price claim — pre-existing copy.)
- **Not verified in a browser:** this pass was static only (see
  UNTESTED above); theme toggles, the Buy notice, and pricing still
  need the browser pass described there.
