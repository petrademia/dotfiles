#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export PROBE_RESULT="$work/result"
dispatcher=$(sed -n '/^run_setup_script() {$/,/^}$/p' "$root/setup.sh")
runner="$dispatcher"$'\n''run_setup_script "$@"'
cat >"$work/probe.sh" <<'EOF'
set -eu
[ "$1" = 'argument with spaces' ]
if [ -t 0 ]; then
  tty >"$PROBE_RESULT"
else
  ! read -r line
  echo headless >"$PROBE_RESULT"
fi
EOF

# Piped dispatch must recover the actual terminal, not /dev/tty.
if terminal=$({ [ -t 1 ] && tty <&1; } || { [ -t 2 ] && tty <&2; }); then
  printf '' | bash -c "$runner" -- "$work/probe.sh" 'argument with spaces'
  [ "$(cat "$PROBE_RESULT")" = "$terminal" ]
else
  echo 'Terminal check skipped; run in a terminal to exercise piped setup.'
fi

# Without a terminal, the platform script receives EOF instead of script input.
printf 'unconsumed script input\n' |
  bash -c "$runner" -- "$work/probe.sh" 'argument with spaces' >/dev/null 2>&1
[ "$(cat "$PROBE_RESULT")" = headless ]
echo 'Setup stdin checks passed.'
