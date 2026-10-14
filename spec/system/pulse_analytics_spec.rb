# frozen_string_literal: true
#
# Run by scripts/verify.sh inside the discourse/discourse_test:release Docker
# image via `bundle exec rspec`, never directly on this machine — there is no
# Discourse application here to boot against. `upload_theme_or_component` and
# the real-browser system-spec driver come from Discourse's own shared RSpec
# support, loaded automatically in that image; the same one line is all
# `discourse/discourse-matomo-analytics` and the community
# `discourse-plausible` component use to install themselves for their own
# tests.
#
# Every example here is a REAL BROWSER assertion (Capybara, driven by
# Discourse's current Playwright-backed system-spec driver — `stable` as of
# 14-10-2026 runs on `playwright-ruby-client`/`capybara-playwright-driver`,
# not Selenium + plain headless Chrome), not a raw HTTP fetch of the page —
# this component injects its tag
# from client-side JavaScript after Ember boots, so a plain `curl`/`fetch` of
# the page's initial HTML can never see it (see README.md, "How the tag is
# emitted"). `have_css`/`have_no_css` poll until the assertion is true or a
# timeout elapses, which is what lets these specs wait out that async
# injection without a hand-rolled sleep.
#
# ---------------------------------------------------------------------------
# Why settings are baked into the upload, not changed afterward with
# Theme#update_setting (found + proven 14-10-2026)
# ---------------------------------------------------------------------------
# An earlier version of this spec called `upload_theme_or_component` once in
# a `before` hook, then used `Theme#update_setting` + `theme.save!` inside
# each example to configure domain/companion/track_admin/api — the pattern
# Discourse's own helper doc comment recommends ("a spec can reconfigure the
# component between examples without going through the admin UI") and the
# same call the real admin endpoint (`Admin::ThemesController#update_single_setting`)
# makes.
#
# It does not work in a Playwright-driven system spec here. Proven, not
# assumed: Capybara boots the server Playwright's browser talks to on a
# SEPARATE RUBY THREAD inside this same process (confirmed by monkey-patching
# `Theme#cached_settings` to log `Thread.current.object_id` — the spec's own
# thread and the thread serving every `visit` are different ids). Both
# threads share the one open, uncommitted RSpec test transaction (confirmed
# with `pg_stat_activity`: exactly one backend, and an unrelated `psql`
# connection sees zero rows for either `themes` or `theme_settings` while the
# example runs) and the theme ROW a test creates is correctly visible to the
# browser's thread — but a `theme_settings` row written by
# `Theme#update_setting` afterward is not: `theme.cached_settings` on the
# SAME theme object, in the SAME call, immediately reflects the new value;
# the live page's preloaded `activatedThemes` JSON (grepped straight out of
# `page.html`) keeps reporting the OLD value no matter what was tried on the
# writing thread: an immediate `Theme.cache.clear(after_commit: false)`
# (bypassing the `DB.after_commit`-deferred default), `Scheduler::Defer.do_all_work`
# (the flush `rails_helper.rb` only runs in `after(:each)`, i.e. too late for
# the same example), a 0.5s sleep, and a cache-busted URL on the next
# `visit`. None of it closed the gap. Given `Admin::ThemesController#update_single_setting`
# calls the exact same `Theme#update_setting` + `theme.save` this spec did,
# this is a system-spec-thread artifact, not a production bug — but it is
# real here, and it would have made "drops an invalid domain" and "loads the
# companion script…" pass VACUOUSLY (both only ever observed the untouched
# `""` default, which also produces no `data-domain` on its own, proving
# nothing about `resolveDomain`'s actual string-sanitising behaviour).
#
# The fix that does work: write the desired value into `settings.yml` as the
# setting's own SCHEMA DEFAULT before importing, so the first-ever read of it
# — on whichever thread gets there first — already sees the right value, with
# no post-import write to go stale. `theme_settings.yml`'s defaults live in a
# `theme_field` created by the SAME import transaction as the theme row
# itself, which is the thing already proven to cross threads correctly.
# Verified directly before rewriting this spec: baking `default: "example.com"`
# into `settings.yml` and visiting with no `update_setting` call at all
# produced `data-domain="example.com"` on the live page every time.

CIPHERA_SCRIPT_SELECTOR = "script[src='https://js.ciphera.net/script.js']"
CIPHERA_COMPANION_SELECTOR = "script[src='https://js.ciphera.net/script.interactions.js']"
ANY_CIPHERA_SELECTOR = "script[src*='js.ciphera.net']"

# This spec file's own path is `<theme root>/spec/system/pulse_analytics_spec.rb`,
# so its directory's grandparent is the theme root — same directory
# `Helpers#directory_from_caller` (spec/support/helpers.rb) resolves via its
# own caller-backtrace walk when `upload_theme_or_component` is invoked from
# `upload_with_settings!` below (that walk finds THIS file regardless of the
# extra frame, since `upload_with_settings!` is itself defined here).
SETTINGS_YML_PATH = File.expand_path("../../settings.yml", __dir__)

# Rewrites settings.yml's SCHEMA DEFAULTS to the given values, imports the
# component (so this import's theme_field carries those defaults from the
# start), then restores the original file — see the file header comment for
# why this, and not `Theme#update_setting` after the fact, is what reliably
# reaches the live page in this harness. Restoring in `ensure` (not an
# `after` hook) means the next example's own call always starts from the
# real on-disk file regardless of how this example ends.
def upload_with_settings!(domain: "", companion: false, track_admin: false, api: "")
  original = File.read(SETTINGS_YML_PATH)
  File.write(
    SETTINGS_YML_PATH,
    {
      "domain" => {
        "type" => "string",
        "default" => domain,
      },
      "companion" => {
        "type" => "bool",
        "default" => companion,
      },
      "track_admin" => {
        "type" => "bool",
        "default" => track_admin,
      },
      "api" => {
        "type" => "string",
        "default" => api,
      },
    }.to_yaml,
  )
  upload_theme_or_component
ensure
  File.write(SETTINGS_YML_PATH, original)
end

RSpec.describe "Pulse Analytics tag", type: :system do
  # Needed so the `/admin` visits below exercise the real admin Ember route,
  # not Discourse's anonymous-visitor response to it. `ensure_admin`
  # (app/controllers/application_controller.rb) raises `Discourse::InvalidAccess`
  # for anyone who isn't an admin, which `rescue_from` turns into a bare
  # `render html: build_not_found_page(...)` — a "page not found" response
  # rendered OUTSIDE the normal Ember-booting layout. That page never runs a
  # single api-initializer, so without an admin session every `/admin` visit
  # here would show no Pulse tag for a reason that has nothing to do with
  # `track_admin` — confirmed: this is exactly what made these examples pass
  # and fail for the wrong reason before signing in was added (14-10-2026). The
  # pattern (`fab!(:admin)` + `before { sign_in(admin) }`) is Discourse's own,
  # used throughout its admin system specs (e.g. `spec/system/admin_about_config_area_spec.rb`).
  fab!(:admin)
  before { sign_in(admin) }

  it "injects the exact published tag when a domain is configured" do
    upload_with_settings!(domain: "example.com")

    visit "/"

    expect(page).to have_css(CIPHERA_SCRIPT_SELECTOR, visible: :all)
    tag = find(CIPHERA_SCRIPT_SELECTOR, visible: :all)

    # A boolean IDL property. capybara-playwright-driver's `[]` tries the live
    # JS property before falling back to the serialized HTML attribute
    # (`lib/capybara/playwright/node.rb#property`), and `element.defer` is a
    # real JS boolean — so this is the actual driver's return type on
    # Discourse's current `stable`, not a Selenium-style stringified
    # attribute. Confirmed by reading the gem source after a real run
    # returned `true` (Ruby), not `"true"`, here.
    expect(tag[:defer]).to eq(true)
    expect(tag[:"data-domain"]).to eq("example.com")
    expect(tag[:"data-api"]).to be_nil
    expect(page).to have_no_css(CIPHERA_COMPANION_SELECTOR, visible: :all)
  end

  it "omits data-domain when the domain setting is empty, instead of a broken attribute" do
    upload_with_settings!(domain: "")

    visit "/"

    expect(page).to have_css(CIPHERA_SCRIPT_SELECTOR, visible: :all)
    tag = find(CIPHERA_SCRIPT_SELECTOR, visible: :all)
    expect(tag[:"data-domain"]).to be_nil
  end

  it "drops an invalid domain rather than injecting it" do
    upload_with_settings!(domain: %(not a domain" onload="window.pulsePwned=1))

    visit "/"

    expect(page).to have_css(CIPHERA_SCRIPT_SELECTOR, visible: :all)
    tag = find(CIPHERA_SCRIPT_SELECTOR, visible: :all)
    expect(tag[:"data-domain"]).to be_nil
    # The real failure mode a dropped-vs-rejected domain is guarding
    # against: the raw string must never reach THIS TAG as markup — scoped
    # to the tag's own outerHTML, not the whole page. A page-wide substring
    # check over-asserts: Discourse's own preloaded `activatedThemes` JSON
    # (unrelated to this component, baked into a `<script>` elsewhere on
    # every page) legitimately echoes the raw, admin-configured setting
    # value for its own settings-editing UI — confirmed present there,
    # correctly JSON-string-escaped (`\"`, never a bare `"`), so it is inert
    # data a JS parser reads as a string, not markup a browser executes. A
    # whole-page check would fail on Discourse's own safe behavior here,
    # which is not what this example exists to catch.
    tag_outer_html =
      page.evaluate_script("document.querySelector(#{CIPHERA_SCRIPT_SELECTOR.to_json}).outerHTML")
    expect(tag_outer_html).not_to include("onload")
    expect(tag_outer_html).not_to include("pulsePwned")
  end

  it "loads the companion script, carrying no domain or api of its own, only when enabled" do
    upload_with_settings!(domain: "example.com", companion: true, api: "https://proxy.example.com")

    visit "/"

    expect(page).to have_css(CIPHERA_COMPANION_SELECTOR, visible: :all)
    companion = find(CIPHERA_COMPANION_SELECTOR, visible: :all)
    expect(companion[:"data-domain"]).to be_nil
    expect(companion[:"data-api"]).to be_nil

    core = find(CIPHERA_SCRIPT_SELECTOR, visible: :all)
    expect(core[:"data-api"]).to eq("https://proxy.example.com")
  end

  it "sends no Pulse traffic at all on an admin page when track_admin is off (the default)" do
    upload_with_settings!(domain: "example.com", track_admin: false)

    visit "/admin"

    expect(page).to have_no_css(ANY_CIPHERA_SELECTOR, visible: :all)
  end

  it "injects the tag once a tracked (non-admin) page is reached" do
    upload_with_settings!(domain: "example.com", track_admin: false)

    visit "/admin"
    expect(page).to have_no_css(ANY_CIPHERA_SELECTOR, visible: :all)

    visit "/"
    expect(page).to have_css(CIPHERA_SCRIPT_SELECTOR, visible: :all)
  end

  it "does inject on an admin page when track_admin is explicitly on" do
    upload_with_settings!(domain: "example.com", track_admin: true)

    visit "/admin"

    expect(page).to have_css(CIPHERA_SCRIPT_SELECTOR, visible: :all)
  end
end

RSpec.describe "Pulse Analytics tag — negative control", type: :system do
  # No `upload_theme_or_component` here, on purpose: this is the control that
  # proves the assertions above are measuring this component and not some
  # other source of a ciphera.net script tag (a different theme, a site
  # setting, a stray plugin).
  it "the same page carries no Pulse tag at all without the component installed" do
    visit "/"

    expect(page).to have_no_css(ANY_CIPHERA_SELECTOR, visible: :all)
  end
end
