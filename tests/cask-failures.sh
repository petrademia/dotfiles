#!/bin/bash
# Runs the cask loop of setup/macos.sh against stub brew helpers: every failure path (install, upgrade,
# repair, and the github-copilot-app install) prints the App Management hint once, and nothing else does.
set -euo pipefail
repo=${1:-$(cd "$(dirname "$0")/.." && pwd)}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

{
  cat <<'STUBS'
record_result() { echo "result:$1"; }
brew_package_state() { echo "$STUB_STATE"; }
load_brew_snapshot() { :; }
brew() { echo "brew $*" >> "$STUB_LOG"; return "$STUB_BREW_RC"; }
CURRENT_COUNT=0
STUBS
  sed -n '/^# macOS blocks changes inside/,/^echo "\[-\] Homebrew casks:/p' "$repo/setup/macos.sh" | sed 's/^CASKS=.*//'
} > "$work/loop.zsh"
grep -q 'cask_failure_hint()' "$work/loop.zsh" || fail "could not extract the cask loop"

# scenario <state> <brew exit code> <cask>
scenario() {
  export STUB_STATE=$1 STUB_BREW_RC=$2 STUB_LOG="$work/brew.log"
  : > "$STUB_LOG"
  CASK=$3 zsh -c 'CASKS=("$CASK"); source "$1"' _ "$work/loop.zsh" 2>&1
}
hints() { grep -c "App Management" <<< "$1" || true; }
expect_hint() {
  out=$(scenario "$1" 1 "$2")
  [ "$(hints "$out")" = 2 ] || fail "$3: expected the two-line hint once, got: $out"   # two lines mention it
  case "$out" in *"result:failed"*) ;; *) fail "$3: failure was not counted" ;; esac
}
expect_quiet() {
  out=$(scenario "$1" 0 "$2")
  [ "$(hints "$out")" = 0 ] || fail "$3: a successful run printed the hint: $out"
  case "$out" in *"result:$4"*) ;; *) fail "$3: expected result:$4, got: $out" ;; esac
}

expect_hint missing demo "failed install"
expect_hint outdated demo "failed upgrade"
expect_hint broken demo "failed repair"
expect_hint missing github-copilot-app "failed github-copilot-app install"
expect_quiet missing demo "install" installed
expect_quiet outdated demo "upgrade" updated
expect_quiet broken demo "repair" installed

out=$(scenario current demo 99)
[ ! -s "$work/brew.log" ] || fail "a current cask must not call brew"
[ "$(hints "$out")" = 0 ] || fail "a current cask printed the hint"
case "$out" in *"result:current"*) ;; *) fail "a current cask was not counted as current" ;; esac

echo 'Cask failure checks passed.'
