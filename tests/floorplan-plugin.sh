#!/bin/bash
# Runs the Floorplan plugin install step of setup/macos.sh and setup/wsl.sh against stub claude and codex
# commands: it installs from the haydenschmitty/floorplan marketplace when the plugin is absent and
# does nothing when it is already there.
set -euo pipefail
repo=${1:-$(cd "$(dirname "$0")/.." && pwd)}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir -p "$work/bin"
for tool in claude codex; do
  printf '#!/bin/sh\necho "$(basename "$0") $*" >> "$STUB_LOG"\n' > "$work/bin/$tool"
  chmod +x "$work/bin/$tool"
done

# The presence helpers are defined earlier in each script; copy them with the install step, which
# runs from the "# Floorplan" comment up to the line that follows it.
extract() { # <script> <line that ends the step> <output file>
  {
    sed -n '/^claude_plugin_present() {/,/^}/p;/^codex_plugin_present() {/,/^}/p' "$1"
    sed -n "/^# Floorplan/,\\#$2#p" "$1" | sed '$d'
  } > "$3"
}
extract "$repo/setup/macos.sh" '^DOTFILES=' "$work/macos.zsh"
extract "$repo/setup/wsl.sh" '^if command -v claude >/dev/null 2>&1; then$' "$work/wsl.sh"
for f in macos.zsh wsl.sh; do grep -q 'codex plugin add floorplan@floorplan' "$work/$f" || fail "could not extract the Floorplan step from $f"; done

export STUB_LOG="$work/calls.log" HOME="$work/home"
check() { # <shell> <file> <label>
  rm -rf "$HOME"; mkdir -p "$HOME"; : > "$STUB_LOG"
  PATH="$work/bin:$PATH" "$1" "$2" >/dev/null 2>&1 || true
  for want in "claude plugin marketplace add haydenschmitty/floorplan" "claude plugin install floorplan@floorplan" \
              "codex plugin marketplace add haydenschmitty/floorplan" "codex plugin add floorplan@floorplan"; do
    grep -qxF "$want" "$STUB_LOG" || fail "$3: missing '$want'"
  done
  mkdir -p "$HOME/.claude/plugins/cache/floorplan" "$HOME/.codex/plugins/cache/floorplan/x"; : > "$STUB_LOG"
  PATH="$work/bin:$PATH" "$1" "$2" >/dev/null 2>&1 || true
  [ ! -s "$STUB_LOG" ] || fail "$3: reinstalled although Floorplan is present: $(cat "$STUB_LOG")"
}
check zsh "$work/macos.zsh" macOS
check bash "$work/wsl.sh" WSL
# Plugins belong to the personal profile: a terminal opened from the work profile exports
# CLAUDE_CONFIG_DIR=~/.claude-work, which would redirect every `claude plugin` command there.
grep -q '^unset CLAUDE_CONFIG_DIR$' "$repo/setup/macos.sh" || fail "macOS setup must unset CLAUDE_CONFIG_DIR"
echo 'Floorplan plugin checks passed.'
