# Pulse Analytics for Discourse

Privacy-first analytics for a Discourse forum, in one theme component. No
cookies, no personal data, and the script it adds to your pages is under
3 KB.

[Pulse Analytics](https://pulse.ciphera.net) is built by
[Ciphera](https://ciphera.net), a company in Belgium, and hosted in Europe.

## Requirements

Discourse **3.3 or later** — the version that made `strict-dynamic` the
default `script-src` policy, which this component relies on (see
"Content Security Policy" below). Targeted and verified against Discourse's
current **`stable`** branch (an alias of its Extended Support Release, `esr`),
which `lib/version.rb` reports as **`2026.7.3`** as of 13-10-2026 — the
version self-hosted sites are recommended to track in production, as opposed
to the faster-moving `tests-passed`/`release` channel. You need a Pulse
Analytics account with a site registered for the same domain; the free plan
is enough to start.

## Install

**Admin → Customize → Themes → Components → Install → From a git
repository**, paste this repository's URL, then add the component to your
active theme (or to each theme you want it on).

Open the component's settings and set **Domain** to the domain your forum is
registered under in Pulse. You can leave it empty: the tracker then uses the
browser's own hostname, which is correct for a forum served on one domain.

## Settings

| Setting | Default | What it does |
|---|---|---|
| `domain` | empty | The domain this forum is registered under in Pulse. Empty means auto-detect. |
| `companion` | off | Record clicks, copies and form submits. Loads a second, separate script — see below. |
| `track_admin` | off | Also send tracking from the `/admin` section. |
| `api` | empty | Route events through your own proxy origin. A bare origin, not a full URL. |

## How the tag is emitted, and why it is not a static `head_tag.html`

Nothing here is a literal `<script defer data-domain="..." src="...">`
sitting in a theme file. The component ships one JavaScript file —
`javascripts/discourse/api-initializers/pulse-analytics.js` — that builds the
same element with `document.createElement` and appends it to `document.head`
once Ember has booted.

That is not a shortcut; it is the only way to get a per-site **`domain`**
value into the tag at all. A theme component's `common/head_tag.html` is
static HTML with no access to `settings`, so there is no way to interpolate a
configured domain into one. Both of the ecosystem's own accepted precedents
for exactly this kind of integration agree: Discourse's first-party
[`discourse-matomo-analytics`](https://github.com/discourse/discourse-matomo-analytics)
and the community
[`discourse-plausible`](https://github.com/OpenHomeFoundation/discourse-plausible)
component both inject their tracker from an api-initializer, and neither ships
a `head_tag.html` at all.

**Consequence worth stating plainly: the tag is not in the server's HTML
response.** `curl`/view-source of a Discourse page shows none of it — it is
appended to `document.head` only after the page's own JavaScript has booted.
Every visitor who can see the forum at all already has JavaScript (Discourse
itself renders nothing without it), so this costs no real visitor anything,
but it is a genuine difference from a server-rendered tag and from what
Pulse's own docs show as "the install", worth knowing rather than assuming.

## Content Security Policy

**No CSP configuration is needed.** Two things make that true, both verified
by reading Discourse's own source rather than assumed:

1. Discourse's default `script-src` carries `'strict-dynamic'` (since 3.3).
   Under that policy, a `<script>` element created by already-trusted
   JavaScript is trusted too, whatever origin it loads from — so a script
   element built by this component's own (theme-origin, already-trusted)
   code needs no entry on an allow-list.
2. A theme component's `extend_content_security_policy` setting could not
   add one for the tracker's `fetch`/`sendBeacon` calls even if it were
   needed: reading `lib/content_security_policy/builder.rb`, only
   `script_src`, `worker_src`, `base_uri`, `frame_ancestors`, `manifest_src`
   and `object_src` are in `EXTENDABLE_DIRECTIVES` today — `connect_src` sits
   in a separate `TO_BE_EXTENDABLE` list with the comment "no-op, until core
   includes them in default CSP". It would silently do nothing. It is also
   moot: Discourse's default policy (`lib/content_security_policy/default.rb`)
   sets no `connect-src` and no `default-src` at all, and per the CSP spec a
   fetch destination with neither present is not restricted in the first
   place.

## SPA navigation (one tracker instance, not one per page)

Discourse is a single-page app: moving between topics or categories is an
Ember route transition, not a new document load. The Pulse tracker already
handles this itself — it wraps `history.pushState`/`replaceState` and listens
for `popstate` the moment it loads, and treats a **path** change (not a
query-string or hash change) as a new pageview (see
`rememberPageview`/`onUrlChange` in the tracker's own source). Discourse's
router uses the real History API for navigation, so this component does not
call anything extra on route change to produce a pageview — doing so would
double-count every navigation. The one thing this component's own
`api.onPageChange` hook is used for is deciding, on every transition, whether
the current path is under `/admin` (see below) and lazily injecting the
script the first time a tracked path is seen.

## "Also track administration pages" — how it actually works here

On every other Pulse platform this integration family ships for, "admin
pages" are a separate server-rendered section, so excluding them is a
server-side `if`. Discourse's `/admin` is not that: it is one more Ember route
inside the same single document the tracker's script is already running in.
Once that script has executed, it owns its own `history.pushState` hook and
decides for itself when to fire a pageview — there is no exposed "pause" it
checks before each one, so this component cannot reach in and stop an
individual admin pageview after the fact.

So the gate sits one level down, at the network call. Every request the Pulse
tracker and its companion script make — pageviews, engagement beacons,
interaction events — goes through `fetch` or `navigator.sendBeacon` to one
API origin. With `track_admin` off, this component wraps both, scoped to that
origin only, and drops the request whenever the current path is under
`/admin`; every other call on the page (Discourse itself makes plenty) passes
through untouched. The check runs again on every route change, so the gate
opens the moment a visitor navigates back out of `/admin` — in the same page
load, no reload needed. With `track_admin` on, neither function is ever
wrapped: nothing is suppressed, so there is nothing to gate.

## A mistyped domain is dropped, never injected — but not rejected at save time

If the Domain setting holds something that cannot be a hostname, the
component omits `data-domain` and lets the tracker auto-detect, rather than
injecting rubbish into your pages — the same defensive behaviour as every
other Pulse integration.

Unlike the Drupal, Joomla and TYPO3 integrations, it cannot be rejected **at
save time** here: Discourse's theme-settings validator
(`lib/theme_settings_validator.rb`) checks only a setting's type, `enum`
choices, numeric/string-length `min`/`max`, and a JSON Schema for the
`objects` type — there is no field-level regex for a plain `string` setting.
So this is a platform limitation, not an oversight: the net effect (never a
broken tag) is the same, reached by a runtime drop instead of a save-time
error.

## The interaction capture is a second request on purpose

`companion` loads `script.interactions.js`, a second, separate script. The
core script's size is a published claim, and nothing is folded into it to
make this feature look free.

## What Pulse Analytics measures

Pageviews, referrers, countries, devices, time on page and scroll depth, plus
goals, funnels and campaigns. It sets no cookies and stores no personal data.
Visitors whose browser sends Do Not Track or Global Privacy Control are not
counted at all — so if you test in Brave or Firefox and see nothing, that is
the tracker behaving correctly. Safari is the easiest browser to verify an
install in.

## Licence

Copyright 2026 Ciphera BV. Licensed under the Apache License, Version 2.0 —
the `LICENSE` file is the licence text verbatim, so the copyright line lives
here rather than inside it.

Discourse's own first-party analytics component
([`discourse-matomo-analytics`](https://github.com/discourse/discourse-matomo-analytics))
ships MIT, and the community Plausible component ships Apache-2.0 — unlike
Drupal, Joomla and TYPO3, nothing about Discourse or its theme-component
category forces a particular licence, so this stays Apache-2.0 like the rest
of the public Pulse integrations (Astro, Docusaurus, Framer, Google Tag
Manager).

Discourse is a trademark of Civilized Discourse Construction Kit, Inc. This
is an independent theme component and is not affiliated with or endorsed by
Discourse or Civilized Discourse Construction Kit, Inc.
