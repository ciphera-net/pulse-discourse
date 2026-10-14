# The Theme-component category topic — Pulse Analytics

Discourse has no separate app store or directory to submit to. The "listing"
is a topic in the
[Theme component](https://meta.discourse.org/c/theme-component/) category on
meta.discourse.org, postable once the `@theme_authors` join request is
approved (see `RELEASING.md`). This file is that topic's copy, kept in
version control the way the Joomla and TYPO3 integrations keep theirs, rather
than living only as a forum post nobody can diff.

**Status:** not yet posted. Blocked on a meta.discourse.org account for
Ciphera and the `@theme_authors` membership request — see `RELEASING.md`
steps 1–2.

## Title

> Pulse Analytics

(Discourse's own convention, followed by every component in this category, is
a plain product-name title — not "Discourse theme component for X".)

## Category and tags

**Category:** Theme component

**Tags:** `analytics` (the tag `discourse-matomo-analytics` and
`discourse-plausible` both carry — the closest thing this ecosystem has to a
"category" beyond the forum category itself)

## Short description (shown in the topic list / link previews)

> Privacy-first web analytics for your forum. No cookies, no personal data, and the script it adds to your pages is under 3 KB.

## Body

Pulse Analytics adds privacy-first web analytics to a Discourse forum with one
theme component. It sets no cookies, stores no personal data, and the script
it adds to your pages is under 3 KB.

**Install**

1. **Admin → Customize → Themes → Components → Install → From a git
   repository**, and paste this repository's URL.
2. Add the component to your theme.
3. Open its settings and set **Domain** to the domain your forum is
   registered under in Pulse — or leave it empty and the tracker uses the
   browser's own hostname, correct for a forum served on one domain.
4. Visit [pulse.ciphera.net](https://pulse.ciphera.net) and watch visitors
   arrive.

**Settings**

| Setting | Default | What it does |
|---|---|---|
| Domain | empty | The domain this forum is registered under in Pulse. Empty means auto-detect. |
| Record clicks, copies and form submits | off | Loads a second, separate script for interaction capture. |
| Also track administration pages | off | Off by default — see the README for exactly how this is enforced on a single-page app. |
| Custom API origin | empty | Route events through your own proxy origin. |

**What it measures**

Pageviews, referrers, countries, devices, time on page and scroll depth, plus
the goals, funnels and campaigns you set up, in one dashboard hosted in
Europe. Visitors whose browser sends Do Not Track or Global Privacy Control
are not counted at all. Administration pages are excluded by default.

**You need**

Discourse 3.3 or later, and a Pulse Analytics account with a site registered
for the same domain. The free plan is enough to start.

**Source**

[`github.com/ciphera-net/pulse-discourse`](https://github.com/ciphera-net/pulse-discourse) ·
docs at [docs.ciphera.net/pulse](https://docs.ciphera.net/pulse)

## Logo

**None.** No policy of Discourse's own (the `DISCOURSE` wordmark/logo
trademark, held by Civilized Discourse Construction Kit, Inc.) was found that
affirmatively grants a third party permission to pair its logo with
Discourse's on a product card — the same silence-is-not-permission finding
that keeps every platform in this integration family at `svg: null` in
`pulse-framer/listing/platforms.mjs`. If an official Discourse brand-asset
policy surfaces that says otherwise, revisit this; until then, the listing
topic carries no Discourse logo, text only ("for Discourse").

## Screenshots

A Discourse "listing" is a forum topic, which conventionally carries one or
two screenshots rather than a fixed, store-mandated set:

1. The component's settings panel (**Admin → Customize → Themes →
   [component] → Settings**), showing the four settings and their
   descriptions.
2. The Pulse Analytics dashboard for a real site, showing a Discourse forum's
   traffic — the same "it actually works" shot the Joomla and TYPO3 listings
   use.

Neither exists yet; both need a real installed instance to capture, which
needs the Docker-based `scripts/verify.sh` harness or a real forum, not this
task's local-toolchain constraints.
