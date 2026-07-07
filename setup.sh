#!/bin/zsh

set -e

xcode-select -p >/dev/null 2>&1 || xcode-select --install

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

FORMULAS=(
  dockutil
  git gh go fnm uv xmake jq socat dust fzf cmake ninja llvm gcc
  rustup fastfetch aria2 p7zip 1password-cli
  gradle maven plantuml kafka tmux ripgrep python
  graphviz z3 zstd ngrok jenv
  charmbracelet/tap/crush
)

for formula in "${FORMULAS[@]}"; do
  echo "==> Installing formula: $formula"
  brew install "$formula"
done

CASKS=(
  1password
  alacritty
  codex
  copilot-cli
  cursor
  deskflow
  ghostty
  herd
  helium-browser
  hyper
  iterm2
  kitty
  librewolf
  libreoffice
  obsidian
  osaurus
  openvpn-connect
  opencode-desktop
  opencoworkai/tap/open-codesign
  postman
  rio
  slack
  surfshark
  tabby
  ungoogled-chromium
  vlc
  warp
  wezterm
  discord
  stremio
  localsend
  brave-browser
  firefox@developer-edition
  floorp
  vivaldi
  vivaldi@snapshot
  opera
  visual-studio-code
  jetbrains-toolbox
  podman-desktop
  spotify
  monitorcontrol
  rectangle
  iina
  grandperspective
  omnidisksweeper
  font-jetbrains-mono-nerd-font
)

for cask in "${CASKS[@]}"; do
  echo "==> Installing cask: $cask"
  brew install --cask "$cask"
done

# Brew keg-only formulas - add to PATH for this script
export PATH="/opt/homebrew/opt/rustup/bin:$PATH"
export PATH="/opt/homebrew/opt/llvm/bin:$PATH"
export PATH="/opt/homebrew/opt/openjdk/bin:$PATH"
export JAVA_HOME="/opt/homebrew/opt/openjdk"

# Install Rust toolchain
rustup default stable || echo "Warning: rustup default stable failed"
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

eval "$(fnm env --use-on-cd)"
fnm use --install-if-missing lts-latest
fnm default lts-latest

curl -fsSL https://claude.ai/install.sh | bash
[ -d "$HOME/.opencode" ] || curl -fsSL https://opencode.ai/install | bash
uv tool install zai-cli --python 3 || true
uv tool install graphifyy --python 3 || true

# Install Claude Code plugins
echo "==> Installing Claude Code plugins"
claude plugin marketplace add https://github.com/JuliusBrussee/caveman 2>/dev/null || true
claude plugin marketplace add https://github.com/DietrichGebert/ponytail 2>/dev/null || true
claude plugin install caveman 2>/dev/null || echo "Note: caveman plugin install failed - may need manual install"
claude plugin install ponytail 2>/dev/null || echo "Note: ponytail plugin install failed - may need manual install"

# Install RTK
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

mkdir -p "$(dirname "$HOME/.zshrc")"
ln -sfn "$DOTFILES/shell/.zshrc" "$HOME/.zshrc"
mkdir -p "$HOME/.config"
ln -sfn "$DOTFILES/config/zsh" "$HOME/.config/zsh"

echo
echo "=== Versions ==="

# Ensure cargo/bin is in PATH for rustc
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

op --version || true
codex --version || true
crush --version || true
claude --version || true

echo
echo "✅ Setup complete!"
echo
echo "Restart your terminal or run:"
echo "source ~/.zshrc"
