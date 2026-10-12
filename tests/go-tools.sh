#!/bin/bash
# Runs the Go tools step of setup/macos.sh against a stub `go` and checks it tells installed, current,
# updated and failed apart (go install always rebuilds, so the result comes from comparing the binary).
set -euo pipefail
repo=${1:-$(cd "$(dirname "$0")/.." && pwd)}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir -p "$work/bin" "$work/gobin"
cat > "$work/bin/go" <<'STUB'
#!/bin/sh
case "$1 $2" in
  "env GOBIN") echo "$STUB_GOBIN" ;;
  "env GOPATH") echo "$STUB_GOBIN/.." ;;
  install*)
    [ -z "${STUB_FAIL:-}" ] || exit 1
    pkg=${2%@latest}
    printf '%s\n' "$STUB_CONTENT" > "$STUB_GOBIN/${pkg##*/}"
    ;;
  *) exit 99 ;;
esac
STUB
chmod +x "$work/bin/go"

{
  echo 'record_result() { echo "result:$1"; }'
  sed -n '/^echo "==> Installing Go tools"/,/^done$/p' "$repo/setup/macos.sh"
} > "$work/step.zsh"
grep -q 'GO_TOOLS=(' "$work/step.zsh" || fail "could not extract the Go tools step"

export STUB_GOBIN="$work/gobin"
# run <content> <expected results, space separated> [label]
run() {
  export STUB_CONTENT="$1"
  local got
  got=$(PATH="$work/bin:$PATH" zsh "$work/step.zsh" 2>/dev/null | grep '^result:' | sed 's/^result://' | tr '\n' ' ')
  [ "$got" = "$2 " ] || fail "${3:-$1}: expected '$2', got '$got'"
}

run v1 'installed installed' 'first install'
run v1 'current current' 'rerun with the same binary'
run v2 'updated updated' 'a new version'
run v2 'current current' 'rerun after the update'
STUB_FAIL=1 run v3 'failed failed' 'go install failing'

echo 'Go tools checks passed.'
