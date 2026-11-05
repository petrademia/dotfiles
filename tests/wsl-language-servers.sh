#!/bin/bash
# Runs the gopls/jdtls step of setup/wsl.sh against stub go and curl and checks it installs, updates,
# skips and fails correctly under the script's `set -euo pipefail`.
set -euo pipefail
repo=${1:-$(cd "$(dirname "$0")/.." && pwd)}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir -p "$work/bin" "$work/tar"
cat > "$work/bin/go" <<'STUB'
#!/bin/sh
case "$1 $2" in
  "env GOPATH") echo "$HOME/go" ;;
  install*)
    [ -z "${STUB_GO_FAIL:-}" ] || exit 1
    mkdir -p "$HOME/go/bin"; printf '#!/bin/sh\n# %s\n' "$STUB_GOPLS" > "$HOME/go/bin/gopls"; chmod +x "$HOME/go/bin/gopls" ;;
  *) exit 99 ;;
esac
STUB
cat > "$work/bin/curl" <<'STUB'
#!/bin/sh
url=""; out=""
while [ $# -gt 0 ]; do
  case "$1" in -o) out=$2; shift ;; -*) ;; *) url=$1 ;; esac
  shift
done
[ -z "${STUB_CURL_FAIL:-}" ] || exit 22
emit() { if [ -n "$out" ]; then cat > "$out"; else cat; fi; }
case "$url" in
  *api.github.com*tags*) printf '%s' "$STUB_TAGS" | emit ;;
  */latest.txt) v=$(echo "$url" | sed 's#.*/milestones/\([^/]*\)/latest.txt#\1#'); echo "jdt-language-server-$v-2026.tar.gz" | emit ;;
  *.tar.gz.sha256) v=$(echo "$url" | sed 's#.*/milestones/\([^/]*\)/.*#\1#')
    if [ -n "${STUB_BADSUM:-}" ]; then echo 0000; else sha256sum "$STUB_TARDIR/$v.tar.gz" | awk '{ printf "%s", $1 }'; fi | emit ;;
  *.tar.gz) v=$(echo "$url" | sed 's#.*/milestones/\([^/]*\)/.*#\1#'); emit < "$STUB_TARDIR/$v.tar.gz" ;;
  *) exit 98 ;;
esac
STUB
# GNU sha256sum fails on a missing file, which is what trips pipefail on a real Ubuntu; macOS's does not.
cat > "$work/bin/sha256sum" <<'STUB'
#!/bin/sh
for f in "$@"; do [ -f "$f" ] || { echo "sha256sum: $f: No such file or directory" >&2; exit 1; }; done
exec shasum -a 256 "$@"
STUB
chmod +x "$work/bin/go" "$work/bin/curl" "$work/bin/sha256sum"

export STUB_TARDIR="$work/tar"
for v in 1.63.0 1.64.0 1.65.0; do
  d=$(mktemp -d "$work/pkg.XXXX"); mkdir -p "$d/bin" "$d/plugins"
  printf '#!/usr/bin/env python3\n# jdtls %s\n' "$v" > "$d/bin/jdtls"; chmod +x "$d/bin/jdtls"
  tar -czf "$STUB_TARDIR/$v.tar.gz" -C "$d" .
done

{
  echo 'set -euo pipefail'
  echo 'record_result() { echo "result:$1"; }'
  sed -n '/^version_matches() {/,/^}/p' "$repo/setup/wsl.sh"
  sed -n '/^echo "==> 4b) Language servers/,/^echo "==> 5) fnm & uv"/p' "$repo/setup/wsl.sh" | sed '$d'
} > "$work/step.sh"
grep -q 'JDTLS_HOME=' "$work/step.sh" || fail "could not extract the language servers step"

home="$work/home"
mkdir -p "$home"
# run <expected results, space separated> <label> [PATH override]
run() {
  local got
  got=$(HOME=$home PATH="${3:-$work/bin:/usr/bin:/bin:/sbin}" bash "$work/step.sh" 2>/dev/null | grep '^result:' | sed 's/^result://' | tr '\n' ' ')
  [ "$got" = "$1 " ] || fail "$2: expected '$1', got '$got'"
}

export STUB_TAGS='[{"name":"v1.9.0"},{"name":"v1.63.0"},{"name":"nightly"}]' STUB_GOPLS=v1
run 'installed installed' 'fresh machine'
[ "$(cat "$home/.local/share/jdtls/.version")" = 1.63.0 ] || fail "jdtls version marker not written (numeric max of 1.9.0 and 1.63.0 must win)"
[ -L "$home/.local/bin/jdtls" ] && [ -x "$home/.local/bin/jdtls" ] || fail "jdtls is not linked into ~/.local/bin"
[ -x "$home/go/bin/gopls" ] || fail "gopls was not installed"
run 'skipped skipped' 'rerun with nothing new'

export STUB_TAGS='[{"name":"v1.64.0"},{"name":"v1.63.0"}]' STUB_GOPLS=v2
run 'updated updated' 'new versions'
[ "$(cat "$home/.local/share/jdtls/.version")" = 1.64.0 ] || fail "jdtls was not updated"

export STUB_TAGS='[{"name":"v1.65.0"}]' STUB_BADSUM=1
run 'skipped failed' 'checksum mismatch'
[ "$(cat "$home/.local/share/jdtls/.version")" = 1.64.0 ] || fail "a failed download replaced the working jdtls"
unset STUB_BADSUM

STUB_CURL_FAIL=1 run 'skipped skipped' 'lookup fails but a copy is installed'
STUB_GO_FAIL=1 STUB_GOPLS=v3 run 'failed updated' 'go install fails'

rm -rf "$home"; mkdir -p "$home"
STUB_CURL_FAIL=1 run 'installed failed' 'lookup fails on a fresh machine'
rm -rf "$home"; mkdir -p "$home"; mkdir "$work/nogo"; cp "$work/bin/curl" "$work/nogo/curl"
export STUB_TAGS='[{"name":"v1.63.0"}]'
run 'installed' 'no go available' "$work/nogo:/usr/bin:/bin:/sbin"
echo 'WSL language server checks passed.'
