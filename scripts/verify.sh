#!/usr/bin/env bash
# Install this theme component into a REAL Discourse and read the tag out of
# a REAL headless browser.
#
# A raw `curl`/`fetch` of a page can never see this component's tag: it is
# injected by client-side JavaScript after Ember boots (see README.md, "How
# the tag is emitted"), so there is nothing in the server's initial HTML
# response to grep. Every assertion that matters has to run inside an actual
# browser, which is what `spec/system/pulse_analytics_spec.rb` does via
# Capybara + Discourse's Playwright-backed system-spec driver, RSpec-style,
# against a real Discourse instance (corrected 14-10-2026: current `stable`
# drives its system specs through `playwright-ruby-client`/
# `capybara-playwright-driver`, not plain Selenium + headless Chrome — see the
# `pnpm playwright-install` step below, needed for exactly this).
#
# This script is the orchestration around that spec file: it reproduces —
# with every resource explicitly named `pulse-verify-discourse-*`, never the
# default names the `discourse_theme` gem's own `rspec` subcommand would pick
# — the same Docker recipe that gem uses, and that
# `discourse/discourse-matomo-analytics` and the community
# `discourse-plausible` theme component both actually run in CI (confirmed by
# reading `discourse/discourse_theme`'s own
# `lib/discourse_theme/cli_commands/rspec.rb`, which is also where the exact
# docker/rake/rspec invocations below are taken from): a single
# `discourse/discourse_test:release` container — Postgres, Redis, a built
# Discourse checkout and Chrome, all inside one image, made for exactly this —
# booted with `--entrypoint=/sbin/boot`, with this repository bind-mounted in.
#
#   ./scripts/verify.sh              # build (if needed), run, tear down
#   ./scripts/verify.sh --keep       # leave the container running afterwards,
#                                     # for a fast repeat run while iterating
#   ./scripts/verify.sh --rebuild    # force a fresh Discourse checkout/build
#                                     # even if a named container is already up
#   ./scripts/verify.sh --mutate     # prove the guards are real: break one
#                                     # (see MUTATION below) and confirm the
#                                     # spec that guards it goes RED
#
# MUST NOT be run as part of this task — it needs Docker, which this task's
# environment deliberately does not run. It is written for the later,
# one-platform-at-a-time Docker harness run named in that task.
#
# Needs: docker. Nothing else — the image carries its own Ruby, Postgres,
# Redis, Chrome and Discourse checkout.
#
# Exits non-zero if any example fails (or, under --mutate, if the mutated
# example does NOT fail — see MUTATION below).

set -uo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_NAME="$(basename "$REPO_DIR")"

# --- Every Docker resource this script creates, named so a later teardown
# --- (here or anywhere else) can find them by prefix and nothing else gets
# --- near them. No network and no named volume are created — the upstream
# --- recipe this is built from needs neither (Postgres/Redis/the Discourse
# --- checkout all live inside the one container's own filesystem) — but if
# --- that ever changes, anything added MUST carry this same prefix.
NAME_PREFIX="pulse-verify-discourse"
CONTAINER="${NAME_PREFIX}-app"
IMAGE="discourse/discourse_test:release"

# The Discourse ref to check out and test against. Defaults to `stable` — the
# version this component's README and about.json actually target (see
# README.md, "Requirements") — not upstream's own `tests-passed`, which is
# what `discourse-matomo-analytics`/`discourse-plausible`'s CI uses and what
# you get by overriding this to match them exactly (pass the fully-qualified
# `origin/tests-passed` — see the note on the checkout invocation below).
#
# Passed to `script/docker_test.rb --checkout-ref` VERBATIM, with no prefix
# added — that script hands it straight to `git checkout <ref>`. `stable` and
# its alias `esr` are TAGS in discourse/discourse, not branches: there is no
# `origin/stable`, only a bare `stable` ref. `tests-passed`, by contrast,
# exists only as the remote branch `origin/tests-passed` (no local or
# tag-named `tests-passed`), so overriding to it needs that full
# `origin/`-qualified form. A single hard-coded prefix cannot be right for
# both shapes, so this script does not add one.
DISCOURSE_CHECKOUT_REF="${DISCOURSE_CHECKOUT_REF:-stable}"

# Host-side scratch space. Not a Docker resource, but prefixed anyway so it
# is obvious at a glance which temp directory belongs to this harness.
HOST_TMP="${TMPDIR:-/tmp}/${NAME_PREFIX}-workdir"

KEEP=0
REBUILD=0
MUTATE=0
for arg in "$@"; do
  case "$arg" in
    --keep) KEEP=1 ;;
    --rebuild) REBUILD=1 ;;
    --mutate) MUTATE=1 ;;
    *)
      echo "REFUSING: unknown argument '$arg'"
      exit 1
      ;;
  esac
done

command -v docker >/dev/null || { echo "REFUSING: docker is not on PATH"; exit 1; }

teardown() {
  # By name ONLY, never a prune — this must not touch anything this harness
  # did not itself create, docker-wide or otherwise.
  docker stop "$CONTAINER" >/dev/null 2>&1 || true
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
  rm -rf "$HOST_TMP"
}

if [ "$KEEP" -eq 0 ]; then
  trap teardown EXIT
fi

# --- Bring the container up, if it is not already --------------------------
mkdir -p "$HOST_TMP"

IS_RUNNING=0
STATE_JSON="$(docker ps -a --filter "name=^/${CONTAINER}\$" --format '{{json .}}' 2>/dev/null || true)"
if [ -n "$STATE_JSON" ]; then
  case "$(echo "$STATE_JSON" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("State",""))' 2>/dev/null)" in
    running) IS_RUNNING=1 ;;
  esac
fi

if [ "$IS_RUNNING" -eq 0 ] || [ "$REBUILD" -eq 1 ]; then
  echo "==> (re)creating ${CONTAINER} from ${IMAGE}"
  docker stop "$CONTAINER" >/dev/null 2>&1 || true
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true

  docker run -d \
    --add-host host.docker.internal:host-gateway \
    --entrypoint=/sbin/boot \
    --name="$CONTAINER" \
    -v "$HOST_TMP:/tmp" \
    "$IMAGE"

  echo "==> checking out Discourse ($DISCOURSE_CHECKOUT_REF)"
  docker exec -u discourse:discourse "$CONTAINER" \
    ruby script/docker_test.rb --no-tests --checkout-ref "${DISCOURSE_CHECKOUT_REF}" \
    || { echo "REFUSING: checkout failed"; exit 1; }

  # JS dependencies MUST be installed before `docker:test:setup` below, not
  # after — `docker:test:setup` is NOT just Postgres/Redis/migrations. Its
  # `db:migrate` depends on the rake task `assets:precompile:asset_processor`
  # (see the `task "db:migrate" => %w[... assets:precompile:asset_processor]`
  # line in `lib/tasks/db.rake`), which bundles `asset-processor.js` using
  # whatever node_modules are on disk RIGHT NOW. `db:migrate`'s own
  # `execute_db_migration` then runs `db:seed`, whose
  # `SystemThemesManager.sync!` compiles the system themes (Foundation,
  # Horizon) through that same asset-processor.js (MiniRacer/V8) — so a stale
  # asset-processor.js doesn't just fail to build, it makes theme seeding
  # throw `ember_this_fallback is not defined` deep inside `Theme.compiler_version`.
  # `execute_db_migration` SWALLOWS that error (`db:seed`'s own rescue, unless
  # `RAISE_SEED_ERRORS=1`) and still exits 0 — so the setup step reports
  # success while leaving ZERO rows in `themes` and `SiteSetting.default_theme_id`
  # pointing at nothing. Every example then fails at `upload_theme_or_component`
  # with `ActiveRecord::RecordNotFound: Couldn't find Theme with 'id'=-1`,
  # which reads like a missing fixture, not a stale-asset problem — confirmed
  # by reproducing with `RAISE_SEED_ERRORS=1` and by showing seeding succeeds
  # the moment node_modules match the checked-out ref (14-10-2026). The image
  # ships node_modules for whatever ref IT was built against, not
  # $DISCOURSE_CHECKOUT_REF, so this reinstall is required on every ref that
  # differs from the image's own default.
  echo "==> installing JS dependencies for this ref (pnpm install)"
  docker exec -u discourse:discourse "$CONTAINER" pnpm install \
    || { echo "REFUSING: pnpm install failed"; exit 1; }

  # `docker:test:setup` doesn't fetch the Playwright browser binary either,
  # only the full `docker:test` task does (`run_or_fail("pnpm
  # playwright-install")`). The image's pinned Chromium revision under
  # ~/.cache/ms-playwright corresponds to whatever ref it was built against,
  # not necessarily $DISCOURSE_CHECKOUT_REF's pinned `playwright` version —
  # confirmed: the system spec's Playwright-backed driver (spec/support's
  # `BrowserTime`/discourse_event_helper, not plain Capybara + headless Chrome
  # as this script's header once assumed) fails every example with
  # "Executable doesn't exist at .../chromium-1217/chrome-linux/chrome"
  # without this. Ordering relative to `docker:test:setup` doesn't matter for
  # this one (only `pnpm install` above has to come first), but it is grouped
  # here with the other JS-dependency step.
  echo "==> installing the Playwright browser binary for this ref"
  docker exec -u discourse:discourse "$CONTAINER" pnpm playwright-install \
    || { echo "REFUSING: pnpm playwright-install failed"; exit 1; }

  # `RAISE_SEED_ERRORS=1`: `db:seed` (invoked by `db:migrate`, invoked by this
  # task) otherwise RESCUES any exception from a seed file, prints it, and
  # still exits 0 — the exact swallow that hid the asset-processor bug above
  # behind a misleading "Theme not found" failure three steps later. Forcing
  # it to raise turns a seeding defect back into a loud, attributable
  # `REFUSING` here instead of a confusing spec failure downstream.
  echo "==> setting up the Discourse test environment (Postgres, Redis, migrations)"
  docker exec -e SKIP_MULTISITE=1 -e RAISE_SEED_ERRORS=1 -u discourse:discourse "$CONTAINER" \
    bundle exec rake docker:test:setup \
    || { echo "REFUSING: test-environment setup failed"; exit 1; }

  echo "==> building Ember CLI assets (first run only; a few minutes)"
  docker exec -u discourse:discourse "$CONTAINER" bin/ember-cli --build \
    || { echo "REFUSING: asset build failed"; exit 1; }
else
  echo "==> reusing already-running ${CONTAINER}"
fi

# --- Copy this repo in (bind-mounted /tmp puts it at /tmp/$REPO_NAME) ------
rm -rf "${HOST_TMP:?}/${REPO_NAME}"
# .git is pointless inside the container and would only waste the copy; node
# ignores itself via package.json's "private" field either way.
rsync -a --exclude='.git' --exclude='node_modules' "$REPO_DIR/" "$HOST_TMP/$REPO_NAME/"

# --- MUTATION: break exactly one guarded behaviour ---------------------------
# Neuters domain validation so an invalid domain WOULD be injected — the
# thing "drops an invalid domain rather than injecting it" exists to prevent.
# If this run does not turn that one example red, the guard was never real
# and this script has been lying about what it checks.
if [ "$MUTATE" -eq 1 ]; then
  echo "==> --mutate: disabling domain validation in the copied working tree"
  TAG_CONFIG="$HOST_TMP/$REPO_NAME/javascripts/discourse/lib/tag-config.js"
  # Replace the guarded return with the unchecked normalised value, so
  # resolveDomain() can no longer refuse anything.
  python3 - "$TAG_CONFIG" <<'PY'
import re, sys
path = sys.argv[1]
src = open(path).read()
needle = """export function resolveDomain(rawDomain) {
  const normalized = normalizeDomain(rawDomain);
  if (normalized !== "" && isValidDomain(normalized)) {
    return normalized;
  }
  return null;
}"""
replacement = """export function resolveDomain(rawDomain) {
  const normalized = normalizeDomain(rawDomain);
  return normalized !== "" ? normalized : null; // MUTATED: validation removed
}"""
if needle not in src:
    print("REFUSING: mutation target text not found — tag-config.js changed shape", file=sys.stderr)
    sys.exit(1)
open(path, "w").write(src.replace(needle, replacement))
PY
  [ $? -eq 0 ] || exit 1
fi

# --- Run the spec ------------------------------------------------------------
echo "==> running spec/system/pulse_analytics_spec.rb"
docker exec -t -u discourse:discourse "$CONTAINER" \
  bundle exec rspec "/tmp/${REPO_NAME}/spec/system/pulse_analytics_spec.rb" \
  --format documentation
RSPEC_STATUS=$?

echo
if [ "$MUTATE" -eq 1 ]; then
  if [ "$RSPEC_STATUS" -ne 0 ]; then
    echo "MUTATION CONFIRMED: the guard is real — the spec went red without it."
    exit 0
  else
    echo "MUTATION FAILED TO BITE: the spec passed with validation disabled."
    echo "The 'drops an invalid domain' guard is not actually tested. Fix the"
    echo "spec or the mutation before trusting a green run of this script."
    exit 1
  fi
else
  if [ "$RSPEC_STATUS" -eq 0 ]; then
    echo "Discourse (${DISCOURSE_CHECKOUT_REF}): ALL CHECKS PASSED"
  else
    echo "Discourse (${DISCOURSE_CHECKOUT_REF}): CHECKS FAILED"
  fi
  exit "$RSPEC_STATUS"
fi
