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

for formula in "${FORMULAS[@]}"; do
  if brew list --formula --versions "$formula" >/dev/null 2>&1; then
    echo "==> Updating formula: $formula"
    if brew upgrade "$formula"; then record_result updated
    else record_result failed; echo "Warning: formula upgrade failed: $formula"; fi
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
    echo "==> Updating cask: $cask"
    if brew upgrade --cask "$cask"; then record_result updated
    else record_result failed; echo "Warning: cask upgrade failed: $cask"; fi
  else
    echo "==> Installing cask: $cask"
    if brew install --cask "$cask"; then record_result installed
    else record_result failed; echo "Warning: cask install failed: $cask"; fi
  fi
done

# CotEditor cot CLI - https://coteditor.com/cot
COTEDITOR_COT="/Applications/CotEditor.app/Contents/SharedSupport/bin/cot"
if [ -x "$COTEDITOR_COT" ]; then
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
      echo "==> Installing App Store app: $app_name"
      sudo mas get "$app_id" || sudo mas install "$app_id" || echo "Warning: mas failed for $app_name ($app_id)"
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

rustup update stable || echo "Warning: rustup update stable failed"
rustup default stable || echo "Warning: rustup default stable failed"
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

eval "$(fnm env --use-on-cd)"
fnm use --install-if-missing lts-latest
fnm default lts-latest

npm install -g @z_ai/coding-helper || true
npm install -g --ignore-scripts @earendil-works/pi-coding-agent || true
npm install -g reasonix || true
npm install -g @deepseek-ai/dsh || true
npm install -g wrangler || true
npm install -g openclaw@latest || true
npm install -g impeccable || true

npm install -g playwright || true
npx playwright install chromium || true

curl -fsSL https://claude.ai/install.sh | bash
if ! command -v hermes >/dev/null 2>&1; then
  curl -fsSL https://hermes-agent.nousresearch.com/install.sh |
    bash -s -- --skip-setup --non-interactive || true
fi
if ! command -v omp >/dev/null 2>&1; then
  curl -fsSL https://omp.sh/install | sh || echo "Note: Oh My Pi (omp) install failed"
fi
npx --yes impeccable install --scope=global --providers=claude,codex,cursor,gemini,opencode,pi --force || echo "Note: impeccable skills install failed"
uv tool install --upgrade zai-cli --python 3 || true
uv tool install --upgrade graphifyy --python 3 || true

if command -v gh >/dev/null 2>&1; then
  gh extension install github/gh-copilot --force >/dev/null 2>&1 || true
fi

echo "==> Installing Claude Code plugins"
claude plugin marketplace add https://github.com/JuliusBrussee/caveman 2>/dev/null || true
claude plugin marketplace add https://github.com/DietrichGebert/ponytail 2>/dev/null || true
claude plugin install caveman 2>/dev/null || echo "Note: caveman plugin install failed - may need manual install"
claude plugin install ponytail 2>/dev/null || echo "Note: ponytail plugin install failed - may need manual install"

if command -v codex >/dev/null 2>&1; then
  echo "==> Installing Codex / ChatGPT plugins"
  codex plugin marketplace add JuliusBrussee/caveman 2>/dev/null || true
  codex plugin marketplace add DietrichGebert/ponytail 2>/dev/null || true
  codex plugin add caveman@caveman 2>/dev/null || echo "Note: caveman Codex plugin install failed - may need manual install"
  codex plugin add ponytail@ponytail 2>/dev/null || echo "Note: ponytail Codex plugin install failed - may need manual install"
  echo "Restart the ChatGPT app and start a new thread to use caveman/ponytail"
  echo "For ponytail: open /hooks in Codex and trust its lifecycle hooks"
else
  echo "==> Skipping Codex plugins; install codex cask first"
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
