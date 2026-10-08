#!/usr/bin/env bash
set -euo pipefail
repo=${1:-$(cd "$(dirname "$0")/.." && pwd)}
test_home=$(mktemp -d)
trap 'rm -rf "$test_home"' EXIT
eval "$(sed -n '/^write_structurizr_launcher() {/,/^}/p' "$repo/setup/wsl.sh" | sed 's/\$HOME/\$test_home/g')"
block=$(sed -n '/^echo "==> Structurizr CLI"/,/^if ! smart_check "xmake"/p' "$repo/setup/wsl.sh" | sed '$d; s/\$HOME/\$test_home/g')
latest_structurizr_version() { echo 2026.09.19; }
record_result() { result=$1; }
java() {
    printf '11:35:09.950 [main] INFO VersionCommand -- structurizr: %s\n' "$(cat "$2")"
}
curl() {
    echo download >> "$test_home/downloads"
    if [ "${fail_download:-0}" = 1 ]; then return 1; fi
    printf '%s\n' "${download_version:-2026.09.19}" > "$4"
}
eval "$block"
test "$result" = installed
test -x "$test_home/.local/bin/structurizr"
eval "$block"
test "$result" = skipped
test "$(wc -l < "$test_home/downloads" | tr -d ' ')" = 1
printf '2026.08.01\n' > "$STRUCTURIZR_WAR"
fail_download=1
eval "$block"
test "$result" = failed
test "$(cat "$STRUCTURIZR_WAR")" = 2026.08.01
fail_download=0
download_version=invalid
eval "$block"
test "$result" = failed
test "$(cat "$STRUCTURIZR_WAR")" = 2026.08.01
test ! -e "$STRUCTURIZR_HOME/structurizr.war.tmp"
unset download_version
eval "$block"
test "$result" = updated
test "$(cat "$STRUCTURIZR_WAR")" = 2026.09.19
echo 'Structurizr install, rerun, update, and failure preservation checks passed.'
