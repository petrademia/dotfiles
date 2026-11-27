#!/bin/bash
# The macOS, WSL and Windows setup summaries must name what failed, not only count it.
set -euo pipefail
repo=${1:-$(cd "$(dirname "$0")/.." && pwd)}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

# Every failure site passes the item name.
for f in setup/macos.sh setup/wsl.sh; do
  bad=$(grep -n 'record_result failed' "$repo/$f" | grep -v 'record_result failed "' || true)
  [ -z "$bad" ] || fail "$f has a failure without an item name: $bad"
  grep -q 'Failed items: ' "$repo/$f" || fail "$f does not print the failed items"
done
bad=$(grep -n 'Add-SetupResult Failed' "$repo/setup/windows.ps1" | grep -v -E 'Add-SetupResult Failed +["$]' || true)
[ -z "$bad" ] || fail "setup/windows.ps1 has a failure without an item name: $bad"
grep -q 'Failed items: ' "$repo/setup/windows.ps1" || fail "setup/windows.ps1 does not print the failed items"

# The recording helpers build the same "a, b" list.
{
  echo 'INSTALLED_COUNT=0 UPDATED_COUNT=0 CURRENT_COUNT=0 SKIPPED_COUNT=0 FAILED_COUNT=0 TARGET_COUNT=0 FAILED_ITEMS=""'
  sed -n '/^record_result() {/,/^}/p; /^record_version_result() {/,/^}/p; /^record_update_result() {/,/^}/p' "$repo/setup/macos.sh"
  cat <<'CHECK'
record_result installed
record_result failed "formula-a"
record_result failed
record_version_result "" "" "Rust stable" || true
record_update_result "1" "" "Hermes Agent" || true
record_version_result "1" "2" "never-listed"
echo "$FAILED_COUNT|$FAILED_ITEMS"
CHECK
} > "$work/mac.zsh"
got=$(zsh "$work/mac.zsh")
[ "$got" = '4|formula-a, Rust stable, Hermes Agent' ] || fail "macOS: expected '4|formula-a, Rust stable, Hermes Agent', got '$got'"

{
  echo 'INSTALLED_COUNT=0 UPDATED_COUNT=0 SKIPPED_COUNT=0 FAILED_COUNT=0 FAILED_ITEMS=""'
  sed -n '/^record_result() {/,/^}/p' "$repo/setup/wsl.sh"
  cat <<'CHECK'
set -euo pipefail
record_result skipped
record_result failed "gopls"
record_result failed
record_result failed "jdtls"
echo "$FAILED_COUNT|$FAILED_ITEMS"
CHECK
} > "$work/wsl.sh"
got=$(bash "$work/wsl.sh")
[ "$got" = '3|gopls, jdtls' ] || fail "WSL: expected '3|gopls, jdtls', got '$got'"
echo 'Failed item reporting checks passed.'
