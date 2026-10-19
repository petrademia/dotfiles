#!/bin/bash
# Runs the throttled update blocks of setup/macos.sh (plugins and Hermes) and setup/wsl.sh (Hermes)
# against stub claude, codex and hermes commands: the first run updates, the next run skips, a failed
# check is retried, and SETUP_FORCE=1 runs everything again.
set -euo pipefail
repo=${1:-$(cd "$(dirname "$0")/.." && pwd)}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

# A fake DOTFILES with the real throttle script and a stub Hermes updater.
mkdir -p "$work/dotfiles/scripts" "$work/bin"
cp "$repo/scripts/update-throttle.sh" "$work/dotfiles/scripts/"
cat > "$work/dotfiles/scripts/hermes-update.sh" <<'STUB'
#!/bin/sh
echo "hermes-update" >> "$STUB_LOG"
exit "${STUB_HERMES_RC:-0}"
STUB
chmod +x "$work/dotfiles/scripts/hermes-update.sh"
for tool in claude codex hermes; do
  cat > "$work/bin/$tool" <<'STUB'
#!/bin/sh
echo "$(basename "$0") $*" >> "$STUB_LOG"
case "$*" in *"$STUB_FAIL_ON"*) [ -n "${STUB_FAIL_ON:-}" ] && exit 1 ;; esac
exit 0
STUB
  chmod +x "$work/bin/$tool"
done

# macOS: from the throttle line to the end of the Hermes update branch.
{
  echo 'record_result() { echo "result:$1"; }'
  echo "DOTFILES='$work/dotfiles'"
  sed -n '/^throttle="\$DOTFILES\/scripts\/update-throttle.sh"/,/^else$/p' "$repo/setup/macos.sh" | sed '$d'
  echo 'fi'
} > "$work/macos.zsh"
grep -q 'claude-plugins' "$work/macos.zsh" || fail "could not extract the macOS block"

# WSL: Hermes only.
{
  echo 'record_result() { echo "result:$1"; }'
  echo "DOTFILES='$work/dotfiles'"
  echo "HOME='$work/home'; mkdir -p \"\$HOME/.local/bin\""
  sed -n '/^throttle="\$DOTFILES\/scripts\/update-throttle.sh"/,/^else$/p' "$repo/setup/wsl.sh" | sed '$d'
  echo 'fi'
} > "$work/wsl.sh"
grep -q 'hermes' "$work/wsl.sh" || fail "could not extract the WSL block"

export STUB_LOG="$work/calls.log" SETUP_STATE_DIR="$work/state" HOME="$work/home"
mkdir -p "$HOME"
unset SETUP_FORCE SETUP_UPDATE_INTERVAL_HOURS STUB_FAIL_ON STUB_HERMES_RC

run_macos() { : > "$STUB_LOG"; PATH="$work/bin:$PATH" zsh "$work/macos.zsh" 2>&1 || true; }
run_wsl() { : > "$STUB_LOG"; PATH="$work/bin:$PATH" bash "$work/wsl.sh" 2>&1 || true; }
calls() { grep -c "$1" "$STUB_LOG" || true; }

echo "-- macOS"
out=$(run_macos)
[ "$(calls '^claude plugin update')" = 2 ] || fail "first run: expected 2 claude plugin updates"
[ "$(calls '^codex plugin marketplace upgrade')" = 2 ] || fail "first run: expected 2 codex marketplace upgrades"
[ "$(calls '^hermes-update')" = 1 ] || fail "first run: expected the Hermes update to run"
case "$out" in *'result:current'*) ;; *) fail "first run: Hermes was not counted: $out" ;; esac
for k in claude-plugins codex-plugins hermes; do [ -f "$SETUP_STATE_DIR/last-$k" ] || fail "first run did not mark $k"; done

out=$(run_macos)
[ -s "$STUB_LOG" ] && fail "second run should call nothing, got: $(cat "$STUB_LOG")"
for what in 'Claude plugins were updated' 'Codex plugins were updated' 'Hermes Agent was checked'; do
  case "$out" in *"$what"*) ;; *) fail "second run did not say '$what'" ;; esac
done
case "$out" in *'result:current'*) ;; *) fail "second run did not count Hermes as current: $out" ;; esac
case "$out" in *'result:skipped'*) fail "a throttled Hermes check must not count as skipped" ;; esac

SETUP_FORCE=1 run_macos >/dev/null
[ "$(calls '^claude plugin update')" = 2 ] && [ "$(calls '^hermes-update')" = 1 ] || fail "SETUP_FORCE=1 did not run everything"

# a failing Claude plugin update is not marked, so only that group retries
rm -rf "$SETUP_STATE_DIR"
STUB_FAIL_ON="update ponytail" run_macos >/dev/null
[ ! -f "$SETUP_STATE_DIR/last-claude-plugins" ] || fail "a failed Claude plugin update was marked as done"
[ -f "$SETUP_STATE_DIR/last-codex-plugins" ] || fail "the Codex group should still be marked"
run_macos >/dev/null
[ "$(calls '^claude plugin update')" = 2 ] || fail "the failed Claude group did not retry"
[ "$(calls '^codex plugin')" = 0 ] || fail "the Codex group should have been skipped"

# Hermes marks only on success (0) or an update (10); failure (1) and preserved local changes (20) retry
for rc in 1 20; do
  rm -rf "$SETUP_STATE_DIR"
  STUB_HERMES_RC=$rc run_macos >/dev/null
  [ ! -f "$SETUP_STATE_DIR/last-hermes" ] || fail "Hermes exit $rc was marked as done"
done
rm -rf "$SETUP_STATE_DIR"
out=$(STUB_HERMES_RC=10 run_macos)
[ -f "$SETUP_STATE_DIR/last-hermes" ] || fail "Hermes exit 10 (updated) was not marked"
case "$out" in *'result:updated'*) ;; *) fail "Hermes exit 10 was not counted as updated" ;; esac

echo "-- WSL"
rm -rf "$SETUP_STATE_DIR"
out=$(run_wsl)
[ "$(calls '^hermes-update')" = 1 ] || fail "WSL first run: expected the Hermes update to run"
[ -f "$SETUP_STATE_DIR/last-hermes" ] || fail "WSL first run did not mark Hermes"
out=$(run_wsl)
[ -s "$STUB_LOG" ] && fail "WSL second run should call nothing"
case "$out" in *'Hermes Agent was checked'*'result:skipped'*) ;; *) fail "WSL second run did not skip: $out" ;; esac
SETUP_FORCE=1 run_wsl >/dev/null
[ "$(calls '^hermes-update')" = 1 ] || fail "WSL SETUP_FORCE=1 did not run the update"
rm -rf "$SETUP_STATE_DIR"
STUB_HERMES_RC=1 run_wsl >/dev/null
[ ! -f "$SETUP_STATE_DIR/last-hermes" ] || fail "WSL: a failed Hermes update was marked as done"

echo 'Setup throttle checks passed.'
