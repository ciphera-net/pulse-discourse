import { apiInitializer } from "discourse/lib/api";
import {
  COMPANION_URL,
  DEFAULT_API_ORIGIN,
  SCRIPT_URL,
  matchesOrigin,
  resolveApiOrigin,
  resolveDomain,
  shouldSuppressAdminTraffic,
} from "../lib/tag-config";

export default apiInitializer((api) => {
  const domain = resolveDomain(settings.domain);
  const customApi = resolveApiOrigin(settings.api);
  const apiOrigin = customApi || DEFAULT_API_ORIGIN;

  // Whether the CURRENT page's traffic should be dropped, re-evaluated on
  // every navigation in onPageChange below — never decided once at boot.
  // Discourse is a single-page app: a visitor who starts on the forum and
  // clicks into /admin never reloads the document, so a one-time check made
  // when this initializer runs would miss every later admin page.
  let suppressed = shouldSuppressAdminTraffic({
    trackAdmin: settings.track_admin,
    pathname: window.location.pathname,
  });
  let injected = false;

  // ---- The admin-page traffic gate ----------------------------------------
  // "Also track administration pages" (off by default) cannot be implemented
  // the way the Drupal/Joomla/TYPO3 integrations do it — rendering nothing
  // server-side for an admin request — because Discourse's admin section is
  // just another Ember route inside the one document the tracker's script is
  // already loaded into. Once that script has run, it owns its own
  // `history.pushState` hook and fires its own pageviews; there is no
  // exposed "pause" it reads before each one.
  //
  // So the gate sits one level down, at the network call: every outbound
  // request the Pulse tracker makes — pageviews, engagement beacons, the
  // companion script's interaction events — goes through `fetch` or
  // `navigator.sendBeacon` to this one API origin. Wrapping those two,
  // scoped to that origin only, drops Pulse's traffic on an admin page and
  // resumes it the moment the visitor navigates back out — in the same
  // document, no reload needed — without touching any other code on the
  // page that also calls `fetch`.
  //
  // Skipped entirely when `track_admin` is on: nothing is ever suppressed,
  // so there is nothing to gate, and the rest of the page keeps its own
  // `fetch`/`sendBeacon`.
  if (!settings.track_admin) {
    const realFetch = window.fetch.bind(window);
    window.fetch = (input, init) => {
      const url = typeof input === "string" ? input : input?.url;
      if (suppressed && url && matchesOrigin(url, apiOrigin)) {
        // A resolved empty response, not a rejection: the tracker's own
        // error handling already treats a failed send as "nothing to do",
        // and a response object (vs. a thrown error) is what its
        // `res.json()` call expects to see, even though parsing an empty
        // body then rejects into that same catch.
        return Promise.resolve(new Response(null, { status: 204 }));
      }
      return realFetch(input, init);
    };

    if (navigator.sendBeacon) {
      const realSendBeacon = navigator.sendBeacon.bind(navigator);
      navigator.sendBeacon = (url, data) => {
        if (suppressed && matchesOrigin(url, apiOrigin)) {
          return true;
        }
        return realSendBeacon(url, data);
      };
    }
  }

  // ---- Script injection ----------------------------------------------------
  // There is no static alternative: `common/head_tag.html` cannot read a
  // theme setting, and neither of the two accepted analytics theme
  // components in this ecosystem (Discourse's own `discourse-matomo-analytics`
  // and the community `discourse-plausible`) ships one — both inject from an
  // api-initializer instead, for the same reason. So the tag is built here,
  // not pasted as static HTML.
  //
  // This also means the tag is NOT present in the server's HTML response —
  // `curl`/view-source shows none of it. Discourse's initial response is
  // rendered server-side, but a theme component's JavaScript only runs once
  // Ember has booted client-side, so the <script> element is appended to
  // `document.head` after that, not before. Every visitor who can see the
  // forum at all has JavaScript (Discourse itself does not render without
  // it), so this costs nothing a visitor would notice — but it is a real
  // difference from a server-rendered tag, worth stating plainly rather than
  // leaving someone to assume `view-source` would show it.
  //
  // Injecting a script element from theme JavaScript needs no Content
  // Security Policy configuration on Discourse's current default CSP:
  // `script-src` carries `'strict-dynamic'`, under which a script created by
  // already-trusted code is trusted too, whatever origin it loads from. (A
  // theme component's `extend_content_security_policy` setting also could
  // not do this job: it can only extend `script_src`, `worker_src`,
  // `base_uri`, `frame_ancestors`, `manifest_src` and `object_src` today —
  // confirmed by reading `lib/content_security_policy/builder.rb`'s
  // `EXTENDABLE_DIRECTIVES`; `connect_src`, the directive that would
  // otherwise matter for the tracker's own `fetch`/`sendBeacon` calls, sits
  // in that file's `TO_BE_EXTENDABLE` list and is a documented no-op until
  // core adds a default `connect-src` to extend. It is moot either way,
  // because Discourse's default policy — `lib/content_security_policy/
  // default.rb` — sets no `connect-src` and no `default-src` at all, and per
  // the CSP spec a fetch destination with neither directive present is not
  // restricted.)
  function buildScript(src) {
    const el = document.createElement("script");
    el.src = src;
    el.defer = true;
    return el;
  }

  function inject() {
    if (injected) {
      return;
    }
    injected = true;

    const tracker = buildScript(SCRIPT_URL);
    if (domain) {
      tracker.dataset.domain = domain;
    }
    if (customApi) {
      tracker.dataset.api = customApi;
    }
    document.head.appendChild(tracker);

    // No data-domain and no data-api on the companion: the tracker resolves
    // both once, from the core script, and a second copy of either is a
    // second thing to keep in step. A second, separate request on purpose —
    // the core script's size is a published claim, and nothing is folded
    // into it to make this feature look free.
    if (settings.companion) {
      document.head.appendChild(buildScript(COMPANION_URL));
    }
  }

  // `onPageChange` fires on the initial page load and again on every in-app
  // (Ember) route transition — the same hook the accepted Plausible
  // component uses for its own pageviews. Re-deriving `suppressed` here,
  // rather than only once at the top of this initializer, is what lets the
  // gate open and close as a visitor moves between the forum and /admin
  // inside one page load. Injection itself only ever happens once
  // (`injected` above) — the first time this fires on a page the setting
  // allows.
  api.onPageChange(() => {
    suppressed = shouldSuppressAdminTraffic({
      trackAdmin: settings.track_admin,
      pathname: window.location.pathname,
    });
    if (!suppressed) {
      inject();
    }
  });
});
