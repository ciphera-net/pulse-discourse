/**
 * Pure decision logic for the Pulse Analytics tag.
 *
 * No `discourse/*` imports here, on purpose: this file has no Ember, no
 * `settings` global, no DOM requirement beyond the standard `URL` class
 * (available in every browser Discourse supports and in Node, so it is
 * unit-testable with a plain `node --test`, no Discourse/Ember boot required).
 * The api-initializer imports this module and supplies the live `settings`
 * and `window`/`document` — see `../api-initializers/pulse-analytics.js`.
 *
 * The URLs, the domain grammar and the "drop an invalid domain, never inject
 * it" rule are carried over from the Drupal, Joomla and TYPO3 integrations'
 * TagBuilder-equivalents rather than re-derived. Several Pulse install
 * surfaces disagreeing about what the tag looks like, or about what counts as
 * a valid domain, is a drift bug waiting to happen.
 */

// The Pulse tracker.
export const SCRIPT_URL = "https://js.ciphera.net/script.js";

// The companion script: clicks, copies and form submits.
export const COMPANION_URL = "https://js.ciphera.net/script.interactions.js";

// Where the tracker sends events by default, absent a custom `api` origin.
export const DEFAULT_API_ORIGIN = "https://pulse-api.ciphera.net";

/**
 * A registrable hostname.
 *
 * Labels of letters, digits and hyphens, at least one dot, a letter-only TLD.
 * Identical in shape to the Drupal module's `DOMAIN_PATTERN` (PHP's PCRE and
 * JavaScript's regex engine both support this syntax, including the leading
 * negative lookahead) — ported, not re-derived, so the two integrations do
 * not quietly diverge on what counts as a valid domain.
 */
const DOMAIN_PATTERN =
  /^(?=.{1,253}$)(?!-)[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?(\.[a-z0-9]([a-z0-9-]{0,61}[a-z0-9])?)*\.[a-z]{2,63}$/;

/**
 * Lower-cases a domain and strips a scheme, path, port and trailing dot.
 * Keeps "www." — the Pulse site may be registered either way.
 *
 * @param {string} input Whatever the site admin typed into the setting.
 * @returns {string} The normalised domain.
 */
export function normalizeDomain(input) {
  let value = String(input ?? "")
    .trim()
    .toLowerCase();
  value = value.replace(/^[a-z][a-z0-9+.-]*:\/\//, "");
  value = value.replace(/[/?#].*$/, "");
  value = value.replace(/:\d*$/, "");
  return value.replace(/\.+$/, "");
}

/**
 * Whether a normalised domain is a registrable hostname.
 *
 * @param {string} domain A domain, already through `normalizeDomain`.
 * @returns {boolean} true when it is safe to put in the tag.
 */
export function isValidDomain(domain) {
  return DOMAIN_PATTERN.test(domain);
}

/**
 * Resolves the `domain` setting into either a safe value for `data-domain`
 * or `null` — never a value that could carry a quote, a space or a bracket
 * into an HTML attribute. An invalid non-empty setting is DROPPED here,
 * exactly like the Drupal, Joomla and TYPO3 integrations drop one at render
 * time: the tag still loads and the tracker still falls back to
 * auto-detecting the browser's own hostname, one attribute short of a
 * fully-configured install rather than broken.
 *
 * Discourse's theme settings system has no field-level regex validator for a
 * plain `string` setting (`ThemeSettingsValidator` checks only the setting's
 * type, `enum` choices, numeric/string-length `min`/`max`, and a JSON Schema
 * for the `objects` type — confirmed by reading
 * `lib/theme_settings_validator.rb` in discourse/discourse) — so unlike
 * Drupal, Joomla and TYPO3, a mistyped domain cannot be rejected at save
 * time here. This runtime drop is the honest substitute: the net effect —
 * never a broken tag — is the same, by a different mechanism.
 *
 * @param {string} rawDomain The raw `domain` setting value.
 * @returns {string|null}
 */
export function resolveDomain(rawDomain) {
  const normalized = normalizeDomain(rawDomain);
  if (normalized !== "" && isValidDomain(normalized)) {
    return normalized;
  }
  return null;
}

/**
 * Normalises the `api` setting (a custom API origin) into a bare origin with
 * no trailing slash, or `null` when empty.
 *
 * A value with no scheme is defensively given `https://` — the tracker builds
 * requests as `apiUrl + path`, and a schemeless origin would otherwise be
 * treated as a relative path and silently fail to reach anywhere. This
 * mirrors how the Plausible theme component normalises its own
 * `plausible_host` setting.
 *
 * @param {string} rawApi The raw `api` setting value.
 * @returns {string|null}
 */
export function resolveApiOrigin(rawApi) {
  let value = String(rawApi ?? "").trim();
  value = value.replace(/\/+$/, "");
  if (value === "") {
    return null;
  }
  if (!/^https?:\/\//i.test(value)) {
    value = `https://${value}`;
  }
  return value;
}

/**
 * Whether a path is under Discourse's admin section (`/admin`, `/admin/...`),
 * never a path that merely starts with the same letters
 * (`/administrivia-category` must not match). Same shape as the accepted
 * Plausible theme component's own `exclude_admin_pages` check.
 *
 * @param {string} pathname `window.location.pathname`.
 * @returns {boolean}
 */
export function isAdminPath(pathname) {
  return /^\/admin(\/|$)/.test(String(pathname ?? ""));
}

/**
 * Whether a given absolute or relative URL targets the same origin as
 * `originUrl`. Used to scope the admin-page traffic gate to Pulse's own
 * requests only — every other `fetch`/`sendBeacon` call on the page (Discourse
 * itself makes many) must be left alone.
 *
 * @param {string} url The URL a `fetch`/`sendBeacon` call was made with.
 * @param {string} originUrl An absolute URL whose origin is the one to match.
 * @param {string} [base] Base to resolve a relative `url` against. Pulse's
 *   own calls are always absolute, so this only matters for tests.
 * @returns {boolean}
 */
export function matchesOrigin(
  url,
  originUrl,
  base = typeof location !== "undefined" ? location.href : "http://localhost/",
) {
  try {
    return new URL(url, base).origin === new URL(originUrl).origin;
  } catch {
    return false;
  }
}

/**
 * Whether Pulse's own network traffic should be dropped right now: the
 * "also track administration pages" setting is off and the current path is
 * under `/admin`.
 *
 * @param {object} args
 * @param {boolean} args.trackAdmin The `track_admin` setting.
 * @param {string} args.pathname `window.location.pathname`.
 * @returns {boolean}
 */
export function shouldSuppressAdminTraffic({ trackAdmin, pathname }) {
  return !trackAdmin && isAdminPath(pathname);
}
