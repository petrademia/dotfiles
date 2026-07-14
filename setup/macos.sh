#!/bin/zsh

set -e

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
  rustup fastfetch aria2 p7zip 1password-cli
  gradle maven plantuml kafka tmux ripgrep python neovim
  graphviz z3 zstd ngrok jenv mas opencode
  charmbracelet/tap/crush
  omar16100/atlassian-cli/atlassian-cli
)

for formula in "${FORMULAS[@]}"; do
  echo "==> Installing formula: $formula"
  brew install "$formula"
done

CASKS=(
  1password
  alacritty
  appcleaner
  claude
  codex
  chatgpt
  codex-app
  copilot-cli
  cursor
  deskflow
  displaylink
  dockdoor
  ghostty
  herd
  helium-browser
  hyper
  iterm2
  kitty
  keka
  librewolf
  libreoffice
  obsidian
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
  microsoft-edge
  mullvad-browser
  vivaldi
  vivaldi@snapshot
  waterfox
  opera
  visual-studio-code
  jetbrains-toolbox
  podman-desktop
  spotify
  monitorcontrol
  rectangle
  scroll-reverser
  iina
  grandperspective
  omnidisksweeper
  font-jetbrains-mono-nerd-font
)

for cask in "${CASKS[@]}"; do
  echo "==> Installing cask: $cask"
  brew install --cask "$cask"
done

MAS_APPS=(
  "1284863847 Unsplash Wallpapers"
)

if mas account >/dev/null 2>&1; then
  for app in "${MAS_APPS[@]}"; do
    app_id="${app%% *}"
    app_name="${app#* }"
    echo "==> Installing App Store app: $app_name"
    mas install "$app_id"
  done
else
  echo "==> Skipping App Store apps; sign in to the App Store, then run: mas install 1284863847"
fi

# Brew keg-only formulas - add to PATH for this script
export PATH="/opt/homebrew/opt/rustup/bin:$PATH"
export PATH="/opt/homebrew/opt/llvm/bin:$PATH"
export PATH="/opt/homebrew/opt/openjdk/bin:$PATH"
export JAVA_HOME="/opt/homebrew/opt/openjdk"

rustup default stable || echo "Warning: rustup default stable failed"
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

eval "$(fnm env --use-on-cd)"
fnm use --install-if-missing lts-latest
fnm default lts-latest

npm install -g @z_ai/coding-helper || true

npm install -g playwright || true
npx playwright install chromium || true

curl -fsSL https://claude.ai/install.sh | bash
uv tool install zai-cli --python 3 || true
uv tool install graphifyy --python 3 || true

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

if ! command -v rtk >/dev/null 2>&1; then
  echo "==> Installing RTK"
  RTK_VERSION=$(curl -fsSL https://api.github.com/repos/rtk-ai/rtk/releases/latest 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' || echo "v0.43.0")
  ARCH=$(uname -m)
  case "$ARCH" in
    arm64) RTK_ARCH="aarch64" ;;
    x86_64) RTK_ARCH="x86_64" ;;
  esac
  RTK_URL="https://github.com/rtk-ai/rtk/releases/download/${RTK_VERSION}/rtk-${RTK_ARCH}-apple-darwin.tar.gz"
  echo "Downloading: $RTK_URL"
  if curl -fL "$RTK_URL" -o /tmp/rtk.tar.gz 2>/dev/null && tar xzf /tmp/rtk.tar.gz -C /tmp 2>/dev/null; then
    sudo mv /tmp/rtk /usr/local/bin/rtk 2>/dev/null && echo "RTK installed"
  else
    echo "RTK download failed - install manually from GitHub releases"
  fi
  rm -f /tmp/rtk.tar.gz /tmp/rtk 2>/dev/null || true
else
  echo "RTK already installed"
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

echo
echo "✅ Setup complete!"
echo
echo "Restart your terminal or run:"
echo "source ~/.zshrc"
echo
echo "Manual follow-ups:"
echo "  - DisplayLink: reboot so the driver takes effect"
echo "  - Wavlink: no brew package - install drivers for your model from https://www.wavlink.com/en_us/Drivers.html"
