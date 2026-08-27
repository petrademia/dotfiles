#!/bin/zsh

set -e
INSTALLED_COUNT=0
UPDATED_COUNT=0
SKIPPED_COUNT=0
FAILED_COUNT=0

record_result() {
  case "$1" in
    installed) INSTALLED_COUNT=$((INSTALLED_COUNT + 1)) ;;
    updated) UPDATED_COUNT=$((UPDATED_COUNT + 1)) ;;
    skipped) SKIPPED_COUNT=$((SKIPPED_COUNT + 1)) ;;
    failed) FAILED_COUNT=$((FAILED_COUNT + 1)) ;;
  esac
}

# Direct installers use this guard when they do not expose a safe version check.
smart_check() {
  local cmd=$1
  local install_path=${2:-}
  if command -v "$cmd" >/dev/null 2>&1 || { [ -n "$install_path" ] && { [ -d "$install_path" ] || [ -f "$install_path" ]; }; }; then
    echo "[-] $cmd already present. Skipping..."
    record_result skipped
    return 0
  fi
  return 1
}

xcode-select -p >/dev/null 2>&1 || xcode-select --install

if [ "$(uname -m)" = "arm64" ] && ! /usr/bin/pgrep -q oahd; then
  softwareupdate --install-rosetta --agree-to-license || true
fi

if ! command -v brew >/dev/null 2>&1; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi

eval "$(/opt/homebrew/bin/brew shellenv)"
brew update

brew tap charmbracelet/tap
brew trust charmbracelet/tap

brew tap deskflow/tap
brew trust deskflow/tap

brew tap opencoworkai/tap
brew trust opencoworkai/tap

brew tap omar16100/atlassian-cli
brew trust omar16100/atlassian-cli

FORMULAS=(
  dockutil
  git gh go fnm uv xmake jq socat dust fzf cmake ninja llvm gcc
  rustup fastfetch aria2 p7zip 1password-cli sqlite
  gradle maven plantuml kafka tmux zellij helix ripgrep python neovim
  graphviz z3 zstd ngrok jenv mas opencode llama.cpp herdr kimi-code
  block-goose-cli kind kubernetes-cli k3d
  charmbracelet/tap/crush
  omar16100/atlassian-cli/atlassian-cli
)

# Repo-managed brew formulas: install when missing; skip when already present.
# Upgrades are left to `brew upgrade` so re-runs stay mostly Skipped.
for formula in "${FORMULAS[@]}"; do
  if brew list --formula --versions "$formula" >/dev/null 2>&1; then
    echo "[-] $formula already present. Skipping..."
    record_result skipped
  else
    echo "==> Installing formula: $formula"
    if brew install "$formula"; then record_result installed
    else record_result failed; exit 1; fi
  fi
done

CASKS=(
  1password
  alacritty
  alfred
  antigravity
  antigravity-cli
  appcleaner
  block-goose
  claude
  codex
  chatgpt
  codex-app
  copilot-cli
  coteditor
  cursor
  kimi
  deskflow
  displaylink
  dockdoor
  cmux
  ghostty
  helium-browser
  hyper
  iterm2
  kitty
  keka
  lapce
  librewolf
  libreoffice
  lm-studio
  neovide-app
  notesnook
  obsidian
  ollama-app
  osaurus
  openvpn-connect
  opencode-desktop
  opencoworkai/tap/open-codesign
  postman
  qbittorrent
  rio
  slack
  transmission
  surfshark
  tabby
  trae
  ungoogled-chromium
  vlc
  warp
  whatsapp
  wezterm
  wispr-flow
  discord
  stremio
  localsend
  macpacker
  brave-browser
  firefox@developer-edition
  floorp
  free-download-manager
  google-chrome
  google-chrome@beta
  google-chrome@canary
  google-drive
  microsoft-edge
  mullvad-browser
  onedrive
  orion
  sigmaos
  simplenote
  standard-notes
  vivaldi
  vivaldi@snapshot
  waterfox
  zen
  opera
  visual-studio-code
  jetbrains-toolbox
  podman-desktop
  spotify
  monitorcontrol
  rectangle
  raycast
  scroll-reverser
  iina
  joplin
  zed
  grandperspective
  omnidisksweeper
  font-jetbrains-mono-nerd-font
)

for cask in "${CASKS[@]}"; do
  if brew list --cask --versions "$cask" >/dev/null 2>&1; then
    echo "[-] $cask already present. Skipping..."
    record_result skipped
  else
    echo "==> Installing cask: $cask"
    if brew install --cask "$cask"; then record_result installed
    else record_result failed; echo "Warning: cask install failed: $cask"; fi
  fi
done

# CotEditor cot CLI - https://coteditor.com/cot
COTEDITOR_COT="/Applications/CotEditor.app/Contents/SharedSupport/bin/cot"
if [ -x /usr/local/bin/cot ]; then
  echo "[-] cot already present. Skipping..."
  record_result skipped
elif [ -x "$COTEDITOR_COT" ]; then
  echo "==> Linking cot CLI to /usr/local/bin/cot"
  sudo mkdir -p /usr/local/bin
  sudo ln -sfn "$COTEDITOR_COT" /usr/local/bin/cot
else
  echo "==> Skipping cot CLI link; CotEditor not found at $COTEDITOR_COT"
fi

MAS_APPS=(
  "1284863847 Unsplash Wallpapers"
  "1398373917 UpNote"
)

# mas 7 needs root. curl|bash has no TTY for sudo, so skip there.
if command -v mas >/dev/null 2>&1; then
  if [ -t 0 ]; then
    for app in "${MAS_APPS[@]}"; do
      app_id="${app%% *}"
      app_name="${app#* }"
      if mas list 2>/dev/null | grep -q "^${app_id}[[:space:]]"; then
        echo "[-] $app_name already present. Skipping..."
        record_result skipped
      else
        echo "==> Installing App Store app: $app_name"
        sudo mas get "$app_id" || sudo mas install "$app_id" || echo "Warning: mas failed for $app_name ($app_id)"
      fi
    done
  else
    echo "==> Skipping App Store apps (mas 7 needs sudo on a TTY). Later run:"
    echo "    sudo mas get 1284863847 1398373917"
  fi
fi

# Brew keg-only formulas - add to PATH for this script
export PATH="/opt/homebrew/opt/rustup/bin:$PATH"
export PATH="/opt/homebrew/opt/llvm/bin:$PATH"
export PATH="/opt/homebrew/opt/openjdk/bin:$PATH"
export JAVA_HOME="/opt/homebrew/opt/openjdk"

if command -v rustc >/dev/null 2>&1; then
  echo "[-] rustc already present. Skipping..."
  record_result skipped
else
  rustup update stable || echo "Warning: rustup update stable failed"
  rustup default stable || echo "Warning: rustup default stable failed"
fi
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

eval "$(fnm env --use-on-cd)"
fnm use --install-if-missing lts-latest
fnm default lts-latest

# Skip when the CLI is already on PATH so re-runs stay mostly skipped / Failed: 0.
run_npm_global() {
  local package=$1
  local cmd=$2
  local ignore_scripts=${3:-}
  if [ -n "$cmd" ] && command -v "$cmd" >/dev/null 2>&1; then
    record_result skipped
    echo "[-] $cmd already present. Skipping..."
    return 0
  fi
  if [ "$ignore_scripts" = "--ignore-scripts" ]; then
    if npm install -g --ignore-scripts "$package" --silent; then
      record_result installed
    else
      record_result failed
      echo "[-] npm install failed: $package"
    fi
  else
    if npm install -g "$package" --silent; then
      record_result installed
    else
      record_result failed
      echo "[-] npm install failed: $package"
    fi
  fi
}

run_npm_global @z_ai/coding-helper coding-helper
run_npm_global @earendil-works/pi-coding-agent pi --ignore-scripts
run_npm_global reasonix reasonix
run_npm_global @deepseek-ai/dsh dsh
run_npm_global wrangler wrangler
run_npm_global openclaw@latest openclaw
run_npm_global impeccable impeccable
run_npm_global playwright playwright
if find "$HOME/.cache/ms-playwright" -maxdepth 1 -type d -name 'chromium*' 2>/dev/null | grep -q .; then
  record_result skipped
  echo "[-] Playwright Chromium already installed. Skipping..."
else
  npx playwright install chromium || true
fi

if ! smart_check "claude" "$HOME/.local/bin/claude"; then
  curl -fsSL https://claude.ai/install.sh | bash
fi
if ! smart_check "hermes" "$HOME/.local/bin/hermes"; then
  curl -fsSL https://hermes-agent.nousresearch.com/install.sh |
    bash -s -- --skip-setup --non-interactive || true
fi
if ! smart_check "omp"; then
  curl -fsSL https://omp.sh/install | sh || echo "Note: Oh My Pi (omp) install failed"
fi
if [ -d "$HOME/.cursor/skills/impeccable" ] || [ -d "$HOME/.claude/skills/impeccable" ]; then
  record_result skipped
  echo "[-] impeccable skills already present. Skipping..."
else
  npx --yes impeccable install --scope=global --providers=claude,codex,cursor,gemini,opencode,pi --force \
    || echo "Note: impeccable skills install failed"
fi
if command -v zai >/dev/null 2>&1; then
  record_result skipped
  echo "[-] zai already present. Skipping..."
else
  uv tool install --upgrade zai-cli --python 3 || true
fi
if command -v graphify >/dev/null 2>&1; then
  record_result skipped
  echo "[-] graphify already present. Skipping..."
else
  uv tool install --upgrade graphifyy --python 3 || true
fi

# copilot comes from the copilot-cli cask (GitHub Copilot CLI).
# Do not install github/gh-copilot; that retired extension collides with gh.

echo "==> Installing Claude Code & Codex plugins (caveman, ponytail)"
claude_plugin_present() {
  [ -d "$HOME/.claude/plugins/cache/$1" ] \
    || [ -d "$HOME/.claude/plugins/marketplaces/$1" ] \
    || [ -d "$HOME/.claude/plugins/installed/$1" ]
}
codex_plugin_present() {
  [ -d "$HOME/.codex/plugins/cache/$1" ] \
    || [ -d "$HOME/.codex/plugins/cache/$1/$1" ] \
    || find "$HOME/.codex/plugins/cache/$1" -mindepth 1 -maxdepth 1 2>/dev/null | grep -q .
}

CLAUDE_PLUGINS_OK=0
CODEX_PLUGINS_OK=0
if claude_plugin_present caveman && claude_plugin_present ponytail; then
  CLAUDE_PLUGINS_OK=1
fi
if codex_plugin_present caveman && codex_plugin_present ponytail; then
  CODEX_PLUGINS_OK=1
fi
if [ "$CLAUDE_PLUGINS_OK" -eq 1 ] && [ "$CODEX_PLUGINS_OK" -eq 1 ]; then
  record_result skipped
  echo "[-] caveman/ponytail plugins already present. Skipping..."
else
  if command -v claude >/dev/null 2>&1 && [ "$CLAUDE_PLUGINS_OK" -eq 0 ]; then
    claude plugin marketplace add https://github.com/JuliusBrussee/caveman 2>/dev/null || true
    claude plugin marketplace add https://github.com/DietrichGebert/ponytail 2>/dev/null || true
    claude plugin install caveman 2>/dev/null || echo "Note: caveman plugin install failed - may need manual install"
    claude plugin install ponytail 2>/dev/null || echo "Note: ponytail plugin install failed - may need manual install"
  elif [ "$CLAUDE_PLUGINS_OK" -eq 1 ]; then
    echo "[-] Claude caveman/ponytail already present. Skipping..."
  fi
  if command -v codex >/dev/null 2>&1 && [ "$CODEX_PLUGINS_OK" -eq 0 ]; then
    echo "==> Installing Codex / ChatGPT plugins"
    codex plugin marketplace add JuliusBrussee/caveman 2>/dev/null || true
    codex plugin marketplace add DietrichGebert/ponytail 2>/dev/null || true
    codex plugin add caveman@caveman 2>/dev/null || echo "Note: caveman Codex plugin install failed - may need manual install"
    codex plugin add ponytail@ponytail 2>/dev/null || echo "Note: ponytail Codex plugin install failed - may need manual install"
    echo "Restart the ChatGPT app and start a new thread to use caveman/ponytail"
    echo "For ponytail: open /hooks in Codex and trust its lifecycle hooks"
  elif [ "$CODEX_PLUGINS_OK" -eq 1 ]; then
    echo "[-] Codex caveman/ponytail already present. Skipping..."
  else
    echo "==> Skipping Codex plugins; install codex cask first"
  fi
fi

DOTFILES="$HOME/dotfiles"

if [ ! -d "$DOTFILES" ]; then
  echo "Cloning dotfiles..."
  git clone https://github.com/petrademia/dotfiles.git "$DOTFILES"
fi

echo "==> Installing dotfiles symlinks"
"$DOTFILES/install.sh"

echo
echo "=== Versions ==="

[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

brew --version
node --version
python3 --version
go version
rustc --version || echo "Warning: rustc not found - run 'rustup default stable' to install Rust"

java --version || true
javac --version || true
mvn --version || true
gradle --version || true

git --version
gh --version
atlassian-cli --version || true

op --version || true
codex --version || true
crush --version || true
claude --version || true
agy --version || true
omp --version || true
reasonix --version || true
dsh --version || true
wrangler --version || true
impeccable --version || true
goose --version || true
kubectl version --client --short 2>/dev/null || kubectl version --client || true
kind version || true
k3d version || true
tmux -V || true
zellij --version || true
hx --version || true
zed --version || true

echo
echo "SETUP COMPLETE"
echo
echo "Setup summary"
echo "  Installed: $INSTALLED_COUNT"
echo "  Updated:   $UPDATED_COUNT"
echo "  Skipped:   $SKIPPED_COUNT"
echo "  Failed:    $FAILED_COUNT"
echo
echo "Restart your terminal or run:"
echo "source ~/.zshrc"
echo
echo "Manual follow-ups:"
echo "  - DisplayLink: reboot so the driver takes effect"
echo "  - Wavlink: no brew package - install drivers for your model from https://www.wavlink.com/en_us/Drivers.html"
echo "  - Antigravity: open the desktop app or run \`agy\` and sign in with Google"
echo "  - Goose: open Goose.app or run \`goose\` / \`goose configure\`"
echo "  - Impeccable: in a project, run \`/impeccable init\` once for design context"
echo "  - Kubernetes: create clusters yourself (e.g. \`kind create cluster\` / \`k3d cluster create\`); setup does not start one"
