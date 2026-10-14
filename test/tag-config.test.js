import assert from "node:assert/strict";
import { test } from "node:test";
import {
  COMPANION_URL,
  DEFAULT_API_ORIGIN,
  SCRIPT_URL,
  isAdminPath,
  isValidDomain,
  matchesOrigin,
  normalizeDomain,
  resolveApiOrigin,
  resolveDomain,
  shouldSuppressAdminTraffic,
} from "../javascripts/discourse/lib/tag-config.js";

test("the published URLs are exactly what they must be", () => {
  assert.equal(SCRIPT_URL, "https://js.ciphera.net/script.js");
  assert.equal(COMPANION_URL, "https://js.ciphera.net/script.interactions.js");
  assert.equal(DEFAULT_API_ORIGIN, "https://pulse-api.ciphera.net");
});

test("normalizeDomain strips scheme, path, port and trailing dot, lower-cases", () => {
  assert.equal(normalizeDomain("Example.com"), "example.com");
  assert.equal(normalizeDomain("https://example.com/"), "example.com");
  assert.equal(normalizeDomain("http://example.com/forum/"), "example.com");
  assert.equal(normalizeDomain("example.com:8080"), "example.com");
  assert.equal(normalizeDomain("example.com."), "example.com");
  assert.equal(normalizeDomain("  example.com  "), "example.com");
  assert.equal(normalizeDomain(""), "");
  assert.equal(normalizeDomain(undefined), "");
  assert.equal(normalizeDomain(null), "");
});

test("normalizeDomain keeps a www. prefix — the site may be registered either way", () => {
  assert.equal(normalizeDomain("WWW.Example.com"), "www.example.com");
});

test("isValidDomain accepts registrable hostnames", () => {
  for (const d of [
    "example.com",
    "www.example.com",
    "forum.example.co.uk",
    "a.io",
    "xn--80ak6aa92e.com",
  ]) {
    assert.equal(isValidDomain(d), true, d);
  }
});

test("isValidDomain rejects anything that is not a plain hostname", () => {
  for (const d of [
    "",
    "not a domain",
    "example",
    "-example.com",
    "example-.com",
    'example.com" onload="x',
    "example.com/path",
    "javascript:alert(1)",
    "exam ple.com",
    "example.c",
    "..example.com",
  ]) {
    assert.equal(isValidDomain(d), false, d);
  }
});

test("resolveDomain returns the normalised domain when valid", () => {
  assert.equal(resolveDomain("Example.com"), "example.com");
  assert.equal(resolveDomain("https://Example.com/"), "example.com");
});

test("resolveDomain drops an empty or invalid domain rather than injecting it", () => {
  assert.equal(resolveDomain(""), null);
  assert.equal(resolveDomain("   "), null);
  assert.equal(resolveDomain(undefined), null);
  assert.equal(resolveDomain('bad" onload="x'), null);
  assert.equal(resolveDomain("not a domain"), null);
});

test("resolveApiOrigin trims, strips trailing slashes, and returns null when empty", () => {
  assert.equal(resolveApiOrigin(""), null);
  assert.equal(resolveApiOrigin("   "), null);
  assert.equal(resolveApiOrigin(undefined), null);
  assert.equal(resolveApiOrigin("https://proxy.example.com"), "https://proxy.example.com");
  assert.equal(resolveApiOrigin("https://proxy.example.com/"), "https://proxy.example.com");
  assert.equal(resolveApiOrigin("https://proxy.example.com///"), "https://proxy.example.com");
  assert.equal(resolveApiOrigin("  https://proxy.example.com  "), "https://proxy.example.com");
});

test("resolveApiOrigin defensively adds a scheme when one is missing", () => {
  assert.equal(resolveApiOrigin("proxy.example.com"), "https://proxy.example.com");
});

test("isAdminPath matches /admin and its subpaths only", () => {
  assert.equal(isAdminPath("/admin"), true);
  assert.equal(isAdminPath("/admin/"), true);
  assert.equal(isAdminPath("/admin/users/list/active"), true);
  assert.equal(isAdminPath("/"), false);
  assert.equal(isAdminPath("/t/some-topic/123"), false);
  // Must not false-positive on a path that merely starts with the same letters.
  assert.equal(isAdminPath("/administrivia-category"), false);
  assert.equal(isAdminPath(""), false);
  assert.equal(isAdminPath(undefined), false);
});

test("matchesOrigin compares the URL's origin, not a string prefix", () => {
  assert.equal(
    matchesOrigin(
      "https://pulse-api.ciphera.net/api/v1/events",
      "https://pulse-api.ciphera.net",
    ),
    true,
  );
  // A relative URL resolves against the explicit base.
  assert.equal(
    matchesOrigin("/api/v1/events", "https://pulse-api.ciphera.net", "https://pulse-api.ciphera.net/x"),
    true,
  );
  assert.equal(
    matchesOrigin(
      "https://evil.example.com/pulse-api.ciphera.net",
      "https://pulse-api.ciphera.net",
    ),
    false,
  );
  assert.equal(
    matchesOrigin("https://pulse-api.ciphera.net.evil.com/", "https://pulse-api.ciphera.net"),
    false,
  );
  assert.equal(matchesOrigin("not a url", "https://pulse-api.ciphera.net"), false);
});

test("shouldSuppressAdminTraffic is true only on /admin with track_admin off", () => {
  assert.equal(
    shouldSuppressAdminTraffic({ trackAdmin: false, pathname: "/admin/users/list" }),
    true,
  );
  assert.equal(
    shouldSuppressAdminTraffic({ trackAdmin: true, pathname: "/admin/users/list" }),
    false,
  );
  assert.equal(shouldSuppressAdminTraffic({ trackAdmin: false, pathname: "/" }), false);
  assert.equal(shouldSuppressAdminTraffic({ trackAdmin: true, pathname: "/" }), false);
});
