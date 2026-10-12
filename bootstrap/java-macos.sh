#!/bin/bash
# macOS Java matrix - Temurin/Zulu/Corretto/Liberica 8-25 + Microsoft 11-25
# Prefer: curl -fsSL .../java-macos.sh -o /tmp/java-macos.sh && bash /tmp/java-macos.sh
# (Needs a real TTY for sudo .pkg password prompts. curl|bash blocks password entry.)
set -uo pipefail

if [ ! -t 0 ]; then
  echo "Don't pipe this script into bash (curl | bash)."
  echo "JDK casks use .pkg installers and need your macOS password via sudo."
  echo "When stdin is the script pipe, sudo can't prompt and it looks stuck."
  echo
  echo "Run instead:"
  echo "  curl -fsSL https://raw.githubusercontent.com/petrademia/dotfiles/main/bootstrap/java-macos.sh -o /tmp/java-macos.sh"
  echo "  bash /tmp/java-macos.sh"
  exit 1
fi

eval "$(/opt/homebrew/bin/brew shellenv)"
export HOMEBREW_NO_AUTO_UPDATE=1
export HOMEBREW_NO_ENV_HINTS=1

# JDK 8 Intel-only casks need Rosetta on Apple Silicon. Check translation
# support directly; oahd is not always running when Rosetta is installed.
if [ "$(uname -m)" = "arm64" ] && ! /usr/bin/arch -x86_64 /usr/bin/true >/dev/null 2>&1; then
  softwareupdate --install-rosetta --agree-to-license || true
fi

# Liberica lives in a third-party tap (uses git clone; with insteadOf this is SSH/1Password).
ensure_liberica_tap() {
  local tap_dir
  tap_dir="$(brew --repository)/Library/Taps/bell-sw/homebrew-liberica"
  if [ -d "$tap_dir/.git" ]; then
    echo "==> skip Liberica tap (already present)"
  else
    echo "==> Tapping bell-sw/liberica (SSH via git insteadOf - approve 1Password if prompted)"
    # Drop a broken partial clone so brew tap can recreate it
    rm -rf "$tap_dir"
    brew tap bell-sw/liberica
  fi
  brew trust bell-sw/liberica
}

ensure_liberica_tap

# Fully qualified - Liberica is NOT in homebrew/cask core (short name fails if tap missing)
JAVA_CASKS=(
  temurin@8 temurin@11 temurin@17 temurin@21 temurin@25
  zulu@8 zulu@11 zulu@17 zulu@21 zulu@25
  corretto@8 corretto@11 corretto@17 corretto@21 corretto@25
  bell-sw/liberica/liberica-jdk8
  bell-sw/liberica/liberica-jdk11
  bell-sw/liberica/liberica-jdk17
  bell-sw/liberica/liberica-jdk21
  bell-sw/liberica/liberica-jdk25
  microsoft-openjdk@11 microsoft-openjdk@17 microsoft-openjdk@21 microsoft-openjdk@25
)

ok=0 skip=0 fail=0
echo "Note: Microsoft JDKs use .pkg installers and may prompt for your macOS password."
echo

for cask in "${JAVA_CASKS[@]}"; do
  if brew list --cask "$cask" >/dev/null 2>&1; then
    echo "==> skip $cask (already installed)"
    skip=$((skip + 1))
    continue
  fi
  echo "==> Installing Java cask: $cask"
  if brew install --cask "$cask"; then
    ok=$((ok + 1))
  else
    echo "==> FAILED $cask (continuing)"
    fail=$((fail + 1))
  fi
done

echo
echo "Done. installed=$ok skipped=$skip failed=$fail"
echo "JDK selection lives in config/zsh/java.zsh (static; it discovers installed JDKs)."
echo
echo "Installed JVMs:"
/usr/libexec/java_home -V 2>&1 || true
echo
echo "Switch: java-use 21-temurin"
