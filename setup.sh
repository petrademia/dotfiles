#!/usr/bin/env bash
# Dispatcher - detects OS and runs the matching setup script in setup/.
set -euo pipefail

SCRIPT_SOURCE="${BASH_SOURCE[0]-}"
if [ -n "$SCRIPT_SOURCE" ] && [ -f "$SCRIPT_SOURCE" ]; then
  SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" && pwd)"
else
  # A script piped into bash has no useful source path. Fall back to the clone.
  SCRIPT_DIR=""
fi

if [ ! -d "$SCRIPT_DIR/setup" ]; then
  DOTFILES="$HOME/dotfiles"
  [ -d "$DOTFILES" ] || git clone https://github.com/petrademia/dotfiles.git "$DOTFILES"
  SCRIPT_DIR="$DOTFILES"
fi

case "$(uname -s)" in
  Darwin)
    PLATFORM_SCRIPT="macos.sh"
    ;;
  Linux)
    if grep -qi microsoft /proc/version 2>/dev/null; then
      PLATFORM_SCRIPT="wsl.sh"
    else
      echo "Native Linux is not supported yet. Adapt setup/wsl.sh (drop the Windows bridges)." >&2
      exit 1
    fi
    ;;
  *)
    echo "Unsupported OS: $(uname -s)" >&2
    echo "For Windows, run setup/windows.ps1 from PowerShell." >&2
    exit 1
    ;;
esac

# A piped setup script can outlive the clone it was originally fetched from.
# Fetch the matching platform script directly so repeat runs do not execute a
# stale local copy. Fall back to the clone if the network is unavailable.
SETUP_SCRIPT="$SCRIPT_DIR/setup/$PLATFORM_SCRIPT"
if [ -z "$SCRIPT_SOURCE" ] && command -v curl >/dev/null 2>&1; then
  REMOTE_SCRIPT="$(mktemp)"
  cleanup_remote_script() {
    if [ -n "${REMOTE_SCRIPT:-}" ]; then rm -f "$REMOTE_SCRIPT"; fi
  }
  trap cleanup_remote_script EXIT
  if curl -fsSL "https://raw.githubusercontent.com/petrademia/dotfiles/main/setup/$PLATFORM_SCRIPT" -o "$REMOTE_SCRIPT"; then
    bash "$REMOTE_SCRIPT" "$@"
    exit $?
  fi
  rm -f "$REMOTE_SCRIPT"
  REMOTE_SCRIPT=""
fi

exec "$SETUP_SCRIPT" "$@"
