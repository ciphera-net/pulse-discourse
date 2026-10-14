# Releasing pulse-discourse

## This repository is the whole distribution — there is no build or package step

Unlike an npm package or a Composer module, a Discourse theme component is
installed directly from its git repository: Discourse's own "Install → From a
git repository" flow clones the repo and reads `about.json`/`settings.yml`/
`javascripts/` straight out of it. There is nothing to publish to a registry
and nothing to tag for an install to work — pushing to `main` (or whatever
branch an install points at) is the release.

## What each step needs, and what it is for

1. **Push this repository to a real, reachable git host.** The sibling public
   Pulse repos live at `github.com/ciphera-net/<name>`; this one would be
   `github.com/ciphera-net/pulse-discourse`, public, under the same GitHub
   account that already publishes every other public Pulse repo — no separate
   credential needed. Nothing in this repository needs a secret: there is no
   API token, no OAuth client, no build pipeline.
2. **Join the `@theme_authors` group on meta.discourse.org**, needed only to
   *post about* the component in the Theme-component category, never to
   install it. On a topic in that category, mention `@theme_authors` and
   request to join; an existing member of the group approves the request.
   This needs a meta.discourse.org account for Ciphera — there is no separate
   "publisher" identity for this ecosystem the way drupal.org or the JED have
   one.
3. **Post the install topic** in the
   [Theme component](https://meta.discourse.org/c/theme-component/) category:
   the name, what it does, the settings table, and the repository URL. This
   topic *is* the listing — Discourse has no separate directory/marketplace
   page to submit to, and no review gate sits between posting and the
   component being installable (it already was, from step 1 onward). See
   `LISTING.md` for the copy.
4. **Optional, for discoverability beyond the forum search:** a PR adding the
   repository URL to
   [`DiscourseForum/DiscourseThemes`](https://github.com/DiscourseForum/DiscourseThemes),
   a community-run (not Discourse-operated) directory of themes and theme
   components. Reviewed by that repository's own maintainers on their own
   schedule — not Discourse Inc., and not a gate on anything in steps 1–3.

## No version tags, no changelog format to match

Nothing here reads a tag or a version string — not `about.json` (no
`theme_version` field is set; it is optional and purely informational when
present) and not Discourse's installer. An update is a new commit on the
branch the install points at; site admins pull it with the "Check for
updates"/"Update" action in **Admin → Customize → Themes**, or it updates
itself on Discourse's periodic theme-update job. There is no equivalent of
`npm publish`, `composer.json`'s `version`, or a drupal.org/JED/TER release
step to get wrong.

## Verifying a change before it reaches a real forum

`scripts/verify.sh` is the real-install harness (see that file's own header
for what it builds and asserts) — it stands up a throwaway Discourse in
Docker, installs this component from the local working tree, and reads the
tag back out of a served page. Run it before pushing a change that touches
`javascripts/` or `settings.yml`; `npm test` (pure-logic unit tests, no
Discourse required) is fast enough to run on every change.

## Licence

Apache-2.0 — see `README.md`'s "Licence" section for why this is a reasonable
choice for Discourse specifically (unlike Drupal, Joomla and TYPO3, nothing
here forces GPL).
