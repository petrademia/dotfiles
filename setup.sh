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
    exec "$SCRIPT_DIR/setup/macos.sh" "$@"
    ;;
  Linux)
    if grep -qi microsoft /proc/version 2>/dev/null; then
      exec "$SCRIPT_DIR/setup/wsl.sh" "$@"
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
