#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export HERMES_TEST_LOG="$work/update.log"
export PATH="$work:$PATH"
cat >"$work/hermes" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  --version)
    if [ -f "$HERMES_TEST_LOG" ]; then echo 'Hermes v2'; else echo 'Hermes v1'; fi
    ;;
  'update --check') printf '%s\n' "$HERMES_TEST_VERDICT"; exit "$HERMES_TEST_CHECK_EXIT" ;;
  update) touch "$HERMES_TEST_LOG"; exit "$HERMES_TEST_UPDATE_EXIT" ;;
  *) exit 99 ;;
esac
EOF
chmod +x "$work/hermes"
{
  echo 'set -e -o pipefail'
  echo 'TARGET_COUNT=0 INSTALLED_COUNT=0 UPDATED_COUNT=0 CURRENT_COUNT=0 FAILED_COUNT=0'
  sed -n '/^record_result() {/,/^brew_package_state() {/p' "$root/setup/macos.sh" | sed '$d'
  sed -n '/^if command -v hermes /,/^if command -v omp /p' "$root/setup/macos.sh" | sed '$d'
  echo 'printf "%s %s %s\n" "$CURRENT_COUNT" "$UPDATED_COUNT" "$FAILED_COUNT"'
} >"$work/run.zsh"

check() {
  export HERMES_TEST_VERDICT="$1" HERMES_TEST_CHECK_EXIT="$2" HERMES_TEST_UPDATE_EXIT="$3"
  rm -f "$HERMES_TEST_LOG"
  result=$(zsh "$work/run.zsh" | tail -n 1)
  [ "$result" = "$4" ]
  if [ "$5" = update ]; then
    [ -f "$HERMES_TEST_LOG" ]
  else
    [ ! -f "$HERMES_TEST_LOG" ]
  fi
}

check '✓ Already up to date.' 0 0 '1 0 0' skip
check '✓ Up to date with the latest release (v1).' 0 0 '1 0 0' skip
check '⚕ Update available: 1 commit behind origin/main.' 0 0 '0 1 0' update
check '→ Selected release available: v2' 0 0 '0 1 0' update
check '✗ Failed to fetch updates from origin.' 1 0 '0 0 1' skip
check '⚕ Update available: 1 commit behind origin/main.' 0 1 '0 0 1' update
check 'Unrecognized verdict' 0 0 '0 1 0' update
echo 'Hermes update checks passed.'
