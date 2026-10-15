#!/bin/bash
# Runs the npm global step of setup/macos.sh against a stub npm: the batched snapshot answers every
# package with two npm calls, and the per-package path is only used when the snapshot is unusable.
set -euo pipefail
repo=${1:-$(cd "$(dirname "$0")/.." && pwd)}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "[-] jq not installed; skipped"; exit 0; }

mkdir -p "$work/bin"
cat > "$work/bin/npm" <<'STUB'
#!/bin/sh
echo "$*" >> "$STUB_LOG"
case "$*" in
  "ls --global --depth=0 --json") printf '%s\n' "$STUB_LS" ;;
  "outdated --global --json")
    printf '%s\n' "$STUB_OUTDATED"
    case "$STUB_OUTDATED" in ''|'{}') exit 0 ;; *) exit 1 ;; esac ;;
  "list --global --depth=0 "*) for p in $STUB_INSTALLED; do [ "$p" = "$4" ] && exit 0; done; exit 1 ;;
  "outdated --global --depth=0 "*) for p in $STUB_OUTDATED_LIST; do [ "$p" = "$4" ] && { echo "$4 1 2"; exit 1; }; done; exit 0 ;;
  install*) exit 0 ;;
  *) exit 99 ;;
esac
STUB
chmod +x "$work/bin/npm"

{
  echo 'record_result() { echo "result:$1"; }'
  sed -n '/^# npm global state/,/^run_npm_global @earendil-works/p' "$repo/setup/macos.sh" | sed '$d'
  echo 'for p in "$@"; do run_npm_global "$p"; done'
} > "$work/step.zsh"
grep -q 'run_npm_global()' "$work/step.zsh" || fail "could not extract the npm step"

# scenario <label> <packages...>: env STUB_* is set by the caller; prints "pkg:result" pairs
scenario() {
  : > "$work/calls.log"
  PATH="$work/bin:$PATH" STUB_LOG="$work/calls.log" zsh "$work/step.zsh" "$@" 2>&1 \
    | grep -E '^result:|Installing|Updating|Skipping' | tr '\n' '|'
}
expect() { [ "$1" = "$2" ] || fail "$3: expected '$2', got '$1'"; }

LS='{"dependencies":{"alpha":{"version":"1"},"beta":{"version":"1"},"@s/gamma":{"version":"1"}}}'

# snapshot path: current, outdated, missing, scoped and @latest names
out=$(STUB_LS="$LS" STUB_OUTDATED='{"beta":{"current":"1","latest":"2"}}' scenario alpha beta delta @s/gamma alpha@latest)
expect "$out" '[-] alpha is current. Skipping...|result:current|==> Updating npm package: beta|result:updated|==> Installing npm package: delta|result:installed|[-] @s/gamma is current. Skipping...|result:current|[-] alpha is current. Skipping...|result:current|' "snapshot results"
grep -qE '^(list|outdated) --global --depth=0 ' "$work/calls.log" && fail "per-package npm calls were made although the snapshot was usable"
[ "$(grep -c '^ls --global' "$work/calls.log")" = 1 ] || fail "npm ls was not called exactly once"
[ "$(grep -c '^outdated --global --json' "$work/calls.log")" = 1 ] || fail "npm outdated was not called exactly once"

# npm printing nothing for outdated means nothing is outdated
out=$(STUB_LS="$LS" STUB_OUTDATED='' scenario alpha)
expect "$out" '[-] alpha is current. Skipping...|result:current|' "empty outdated output"

# unusable snapshots fall back to per-package checks
for bad in 'not json' ''; do
  out=$(STUB_LS="$bad" STUB_OUTDATED='{}' STUB_INSTALLED='alpha beta' STUB_OUTDATED_LIST='beta' scenario alpha beta delta)
  expect "$out" '[-] alpha is current. Skipping...|result:current|==> Updating npm package: beta|result:updated|==> Installing npm package: delta|result:installed|' "fallback for ls output '$bad'"
  grep -q '^list --global --depth=0 alpha' "$work/calls.log" || fail "fallback did not check per package"
done
out=$(STUB_LS="$LS" STUB_OUTDATED='{"error":{"code":"ENOTFOUND"}}' STUB_INSTALLED='alpha' STUB_OUTDATED_LIST='' scenario alpha)
expect "$out" '[-] alpha is current. Skipping...|result:current|' "fallback when npm outdated reports an error"
grep -q '^list --global --depth=0 alpha' "$work/calls.log" || fail "an npm error object did not trigger the fallback"

echo 'npm globals checks passed.'
