#!/usr/bin/env bash
# Checks scripts/update-throttle.sh: due before the first mark, not due right after, due again once the
# interval has passed, plus the overrides and the odd state files that must never block an update.
set -euo pipefail
repo=${1:-$(cd "$(dirname "$0")/.." && pwd)}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

export SETUP_STATE_DIR="$work/state"
unset SETUP_FORCE SETUP_UPDATE_INTERVAL_HOURS
throttle() { bash "$repo/scripts/update-throttle.sh" "$@"; }
due() { throttle due "$1" >/dev/null 2>&1; }
set_age() { mkdir -p "$SETUP_STATE_DIR"; printf '%s\n' $(( $(date +%s) - $2 )) > "$SETUP_STATE_DIR/last-$1"; }

due plugins || fail "a check that never ran must be due"
[ ! -e "$SETUP_STATE_DIR" ] || fail "due must not create the state directory"

throttle mark plugins
[ -f "$SETUP_STATE_DIR/last-plugins" ] || fail "mark did not write the timestamp file"
due plugins && fail "a check marked just now must not be due"
out=$(throttle due plugins || true)
[ "$out" = "0h 0m ago" ] || fail "age message was '$out'"
due other || fail "marking one check must not affect another"
for leftover in "$SETUP_STATE_DIR"/.last-*; do
  [ -e "$leftover" ] && fail "mark left a temporary file behind: $leftover"
done

# the 12 hour default
set_age plugins $((11 * 3600 + 5 * 60))
due plugins && fail "11h05m old must not be due"
[ "$(throttle due plugins || true)" = "11h 5m ago" ] || fail "age message for 11h05m was wrong"
set_age plugins $((12 * 3600))
due plugins || fail "exactly 12h old must be due"
set_age plugins $((13 * 3600))
due plugins || fail "13h old must be due"

# overrides
set_age plugins 60
SETUP_FORCE=1 due plugins || fail "SETUP_FORCE=1 must make every check due"
SETUP_UPDATE_INTERVAL_HOURS=0 due plugins || fail "interval 0 must disable the throttle"
SETUP_UPDATE_INTERVAL_HOURS=1 due plugins && fail "1 minute old must not be due with a 1 hour interval"
set_age plugins $((2 * 3600))
SETUP_UPDATE_INTERVAL_HOURS=1 due plugins || fail "2h old must be due with a 1 hour interval"
set_age plugins $((13 * 3600))
SETUP_UPDATE_INTERVAL_HOURS=48 due plugins && fail "13h old must not be due with a 48 hour interval"
set_age plugins 60
SETUP_UPDATE_INTERVAL_HOURS=abc due plugins && fail "a bad interval must fall back to 12 hours"

# state that must never block an update
printf '%s\n' $(( $(date +%s) + 7200 )) > "$SETUP_STATE_DIR/last-plugins"
due plugins || fail "a timestamp in the future must be due"
printf 'garbage\n' > "$SETUP_STATE_DIR/last-plugins"
due plugins || fail "a garbage timestamp must be due"
: > "$SETUP_STATE_DIR/last-plugins"
due plugins || fail "an empty timestamp file must be due"

# argument handling
rc=0; throttle due 'bad name' >/dev/null 2>&1 || rc=$?; [ "$rc" = 2 ] || fail "an invalid name must exit 2, got $rc"
rc=0; throttle due '../escape' >/dev/null 2>&1 || rc=$?; [ "$rc" = 2 ] || fail "a path-like name must exit 2, got $rc"
rc=0; throttle bogus plugins >/dev/null 2>&1 || rc=$?; [ "$rc" = 2 ] || fail "an unknown action must exit 2, got $rc"
rc=0; throttle due >/dev/null 2>&1 || rc=$?; [ "$rc" = 2 ] || fail "a missing name must exit 2, got $rc"

echo 'Update throttle checks passed.'
