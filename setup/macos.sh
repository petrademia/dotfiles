#!/bin/zsh

set -e -o pipefail
export PATH="$HOME/.local/bin:$PATH"
INSTALLED_COUNT=0
UPDATED_COUNT=0
CURRENT_COUNT=0
FAILED_COUNT=0
TARGET_COUNT=0

record_result() {
  TARGET_COUNT=$((TARGET_COUNT + 1))
  case "$1" in
    installed) INSTALLED_COUNT=$((INSTALLED_COUNT + 1)) ;;
    updated) UPDATED_COUNT=$((UPDATED_COUNT + 1)) ;;
    current) CURRENT_COUNT=$((CURRENT_COUNT + 1)) ;;
    failed) FAILED_COUNT=$((FAILED_COUNT + 1)) ;;
    *) FAILED_COUNT=$((FAILED_COUNT + 1)); echo "Warning: unknown setup result: $1" ;;
  esac
}

record_version_result() {
  local before=$1
  local after=$2
  if [ -z "$after" ]; then
    record_result failed
    return 1
  elif [ -z "$before" ]; then
    record_result installed
  elif [ "$before" = "$after" ]; then
    record_result current
  else
    record_result updated
  fi
}

record_update_result() {
  local before=$1
  local after=$2
  if [ -z "$before" ] || [ -z "$after" ]; then
    record_result failed
    return 1
  elif [ "$before" = "$after" ]; then
    record_result current
  else
    record_result updated
  fi
}

cli_version() {
  "$1" --version 2>/dev/null | sed -n '1p' || true
}

brew_formula_installed() {
  local pkg=$1
  brew list --formula --versions "$pkg" >/dev/null 2>&1 && return 0
  local short="${pkg##*/}"
  [ "$short" != "$pkg" ] && brew list --formula --versions "$short" >/dev/null 2>&1
}

brew_cask_installed() {
  local pkg=$1
  brew list --cask --versions "$pkg" >/dev/null 2>&1 && return 0
  local short="${pkg##*/}"
  [ "$short" != "$pkg" ] && brew list --cask --versions "$short" >/dev/null 2>&1
}

xcode-select -p >/dev/null 2>&1 || xcode-select --install

# Check translation support directly; oahd is not always running when Rosetta
# is installed.
if [ "$(uname -m)" = "arm64" ] && ! /usr/bin/arch -x86_64 /usr/bin/true >/dev/null 2>&1; then
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
  rustup fastfetch aria2 p7zip sqlite
  gradle maven plantuml kafka tmux zellij helix ripgrep python neovim
  graphviz z3 zstd jenv mas opencode llama.cpp herdr kimi-code
  block-goose-cli kind kubernetes-cli k3d podman-compose
  charmbracelet/tap/crush
  omar16100/atlassian-cli/atlassian-cli
)

# Repo-managed brew formulas: install when missing and upgrade when outdated.
for formula in "${FORMULAS[@]}"; do
  if brew_formula_installed "$formula"; then
    outdated=""
    if ! outdated=$(brew outdated --formula --quiet "$formula") && [ -z "$outdated" ]; then
      echo "Warning: could not check whether formula is outdated: $formula"
      record_result failed
      continue
    fi
    if [ -z "$outdated" ]; then
      echo "[-] $formula is current. Skipping..."
      record_result current
      continue
    fi
    echo "==> Updating formula: $formula"
    if brew upgrade --formula --no-ask "$formula"; then record_result updated
    else record_result failed; echo "Warning: formula upgrade failed: $formula"; fi
  else
    echo "==> Installing formula: $formula"
    if brew install "$formula"; then record_result installed
    else record_result failed; echo "Warning: formula install failed: $formula"; fi
  fi
done

CASKS=(
  1password
  1password-cli
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
  github-copilot-app
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
  ngrok
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
  if brew_cask_installed "$cask"; then
    outdated=""
    if ! outdated=$(brew outdated --cask --quiet "$cask") && [ -z "$outdated" ]; then
      echo "Warning: could not check whether cask is outdated: $cask"
      record_result failed
      continue
    fi
    if [ -z "$outdated" ]; then
      echo "[-] $cask is current. Skipping..."
      record_result current
      continue
    fi
    echo "==> Updating cask: $cask"
    if brew upgrade --cask --no-ask "$cask"; then record_result updated
    else record_result failed; echo "Warning: cask upgrade failed: $cask"; fi
  else
    echo "==> Installing cask: $cask"
    if [ "$cask" = "github-copilot-app" ]; then
      if brew install --cask --appdir="$HOME/Applications" --adopt "$cask"; then record_result installed
      else record_result failed; echo "Warning: cask install failed: $cask"; fi
    elif brew install --cask "$cask"; then record_result installed
    else record_result failed; echo "Warning: cask install failed: $cask"; fi
  fi
done

# CotEditor cot CLI - https://coteditor.com/cot
COTEDITOR_COT="/Applications/CotEditor.app/Contents/SharedSupport/bin/cot"
if [ -x /usr/local/bin/cot ]; then
  echo "[-] cot already present. Skipping..."
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

# App Store targets are version-checked and updated individually. mas requires
# a TTY and root privileges for install/update operations.
for app in "${MAS_APPS[@]}"; do
  app_id="${app%% *}"
  app_name="${app#* }"
  if ! command -v mas >/dev/null 2>&1 || [ ! -t 0 ]; then
    echo "Warning: cannot check App Store target in this non-interactive run: $app_name"
    record_result failed
    continue
  fi

  if ! installed_apps=$(mas list 2>/dev/null); then
    echo "Warning: could not list Mac App Store apps"
    record_result failed
    continue
  fi
  installed_version=$(printf '%s\n' "$installed_apps" | awk -v id="$app_id" '$1 == id { print $NF; exit }')
  if [ -z "$installed_version" ]; then
    echo "==> Installing App Store app: $app_name"
    if sudo mas get "$app_id" || sudo mas install "$app_id"; then
      installed_apps=$(mas list 2>/dev/null || true)
      installed_version=$(printf '%s\n' "$installed_apps" | awk -v id="$app_id" '$1 == id { print $NF; exit }')
      if [ -n "$installed_version" ]; then record_result installed
      else record_result failed; echo "Warning: could not verify App Store install: $app_name"; fi
    else
      record_result failed
      echo "Warning: App Store install failed: $app_name ($app_id)"
    fi
    continue
  fi

  if outdated=$(mas outdated "$app_id" 2>/dev/null); then
    if [ -z "$outdated" ]; then
      echo "[-] $app_name is current. Skipping..."
      record_result current
      continue
    fi
  else
    echo "Warning: could not check App Store version: $app_name"
    record_result failed
    continue
  fi

  echo "==> Updating App Store app: $app_name"
  if sudo mas update "$app_id"; then
    installed_apps=$(mas list 2>/dev/null || true)
    updated_version=$(printf '%s\n' "$installed_apps" | awk -v id="$app_id" '$1 == id { print $NF; exit }')
    if [ -n "$updated_version" ] && [ "$updated_version" != "$installed_version" ]; then
      record_result updated
    else
      record_result failed
      echo "Warning: App Store update did not change the detected version: $app_name"
    fi
  else
    record_result failed
    echo "Warning: App Store update failed: $app_name ($app_id)"
  fi
done

# Brew keg-only formulas - add to PATH for this script
export PATH="/opt/homebrew/opt/rustup/bin:$PATH"
export PATH="/opt/homebrew/opt/llvm/bin:$PATH"
export PATH="/opt/homebrew/opt/openjdk/bin:$PATH"
export JAVA_HOME="/opt/homebrew/opt/openjdk"

if command -v rustup >/dev/null 2>&1; then
  echo "==> Updating Rust stable toolchain"
  rust_before=$(rustup run stable rustc --version 2>/dev/null || true)
  if rustup update stable && rustup default stable; then
    rust_after=$(rustup run stable rustc --version 2>/dev/null || true)
    record_version_result "$rust_before" "$rust_after" \
      || echo "Warning: could not verify the Rust stable toolchain version"
  else
    record_result failed
    echo "Warning: Rust stable toolchain update failed"
  fi
else
  record_result failed
  echo "Warning: rustup is unavailable; could not check Rust stable"
fi
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

node_before=$(node --version 2>/dev/null || true)
if command -v fnm >/dev/null 2>&1 \
  && eval "$(fnm env --use-on-cd)" \
  && fnm install --lts --use \
  && fnm default lts-latest; then
  node_after=$(node --version 2>/dev/null || true)
  record_version_result "$node_before" "$node_after" \
    || echo "Warning: could not verify the Node.js LTS version"
else
  record_result failed
  echo "Warning: could not install or select the latest Node.js LTS"
fi

# Install missing npm global tools and update only when outdated.
run_npm_global() {
  local package=$1
  local ignore_scripts=${2:-}
  local installed_package=${package%@latest}
  local result=installed
  if npm list --global --depth=0 "$installed_package" >/dev/null 2>&1; then
    local outdated
    if outdated=$(npm outdated --global --depth=0 "$installed_package" 2>/dev/null); then
      echo "[-] $installed_package is current. Skipping..."
      record_result current
      return 0
    elif [ -n "$outdated" ]; then
      echo "==> Updating npm package: $package"
      result=updated
    else
      record_result failed
      echo "[-] Could not check npm package: $installed_package"
      return 0
    fi
  else
    echo "==> Installing npm package: $package"
  fi
  if [ "$ignore_scripts" = "--ignore-scripts" ]; then
    if npm install -g --ignore-scripts "$package" --silent; then
      record_result "$result"
    else
      record_result failed
      echo "[-] npm install failed: $package"
    fi
  else
    if npm install -g "$package" --silent; then
      record_result "$result"
    else
      record_result failed
      echo "[-] npm install failed: $package"
    fi
  fi
}

run_npm_global @z_ai/coding-helper
run_npm_global @earendil-works/pi-coding-agent --ignore-scripts
run_npm_global reasonix
run_npm_global @deepseek-ai/dsh
run_npm_global wrangler
run_npm_global openclaw@latest
run_npm_global impeccable
run_npm_global playwright
npx playwright install chromium || true

claude_cmd=$(command -v claude 2>/dev/null || true)
if [ -z "$claude_cmd" ] && [ -x "$HOME/.local/bin/claude" ]; then
  claude_cmd="$HOME/.local/bin/claude"
fi
if [ -n "$claude_cmd" ]; then
  claude_before=$(cli_version "$claude_cmd")
  if "$claude_cmd" update; then
    claude_after=$(cli_version "$claude_cmd")
    record_update_result "$claude_before" "$claude_after" \
      || echo "Warning: could not verify Claude Code CLI version"
  else
    record_result failed
    echo "Warning: Claude Code CLI update failed"
  fi
else
  echo "==> Installing Claude Code CLI"
  if curl -fsSL https://claude.ai/install.sh | bash; then
    claude_cmd=$(command -v claude 2>/dev/null || true)
    if [ -z "$claude_cmd" ] && [ -x "$HOME/.local/bin/claude" ]; then
      claude_cmd="$HOME/.local/bin/claude"
    fi
    claude_after=""
    if [ -n "$claude_cmd" ]; then claude_after=$(cli_version "$claude_cmd"); fi
    record_version_result "" "$claude_after" \
      || echo "Warning: could not verify Claude Code CLI installation"
  else
    record_result failed
    echo "Warning: Claude Code CLI install failed"
  fi
fi

if command -v hermes >/dev/null 2>&1; then
  hermes_cmd=$(command -v hermes)
  hermes_info=$("$hermes_cmd" --version 2>/dev/null || true)
  hermes_before=$(printf '%s\n' "$hermes_info" | sed -n '1p')
  hermes_dir=$(printf '%s\n' "$hermes_info" | sed -n 's/^Install directory: //p' | sed -n '1p')
  hermes_worktree=""
  hermes_ahead=""
  if [ -n "$hermes_dir" ] && git -C "$hermes_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    hermes_worktree=$(git -C "$hermes_dir" status --porcelain --untracked-files=all \
      -- . ':(exclude).install_method' 2>/dev/null || echo "unavailable")
    hermes_ahead=$(git -C "$hermes_dir" rev-list --left-right --count '@{upstream}...HEAD' 2>/dev/null \
      | awk '{ print $2 }')
  fi
  if [ -n "$hermes_worktree" ] || { [ -n "$hermes_dir" ] && [ "$hermes_ahead" != "0" ]; }; then
    record_result failed
    echo "Warning: Hermes Agent has local changes or commits; update skipped to preserve them"
  elif "$hermes_cmd" update; then
    hermes_after=$(cli_version "$hermes_cmd")
    record_update_result "$hermes_before" "$hermes_after" \
      || echo "Warning: could not verify Hermes Agent version"
  else
    record_result failed
    echo "Warning: Hermes Agent update failed"
  fi
else
  echo "==> Installing Hermes Agent"
  if curl -fsSL https://hermes-agent.nousresearch.com/install.sh |
    bash -s -- --skip-setup --non-interactive; then
    hermes_after=""
    if hermes_cmd=$(command -v hermes 2>/dev/null); then
      hermes_after=$(cli_version "$hermes_cmd")
    fi
    record_version_result "" "$hermes_after" \
      || echo "Warning: could not verify Hermes Agent installation"
  else
    record_result failed
    echo "Warning: Hermes Agent install failed"
  fi
fi

if command -v omp >/dev/null 2>&1; then
  omp_before=$(cli_version "$(command -v omp)")
  if omp update; then
    omp_after=$(cli_version "$(command -v omp)")
    record_update_result "$omp_before" "$omp_after" \
      || echo "Warning: could not verify Oh My Pi version"
  else
    record_result failed
    echo "Warning: Oh My Pi update failed"
  fi
else
  echo "==> Installing Oh My Pi"
  if curl -fsSL https://omp.sh/install | sh; then
    omp_after=""
    if omp_cmd=$(command -v omp 2>/dev/null); then
      omp_after=$(cli_version "$omp_cmd")
    fi
    record_version_result "" "$omp_after" \
      || echo "Warning: could not verify Oh My Pi installation"
  else
    record_result failed
    echo "Warning: Oh My Pi install failed"
  fi
fi
if [ -d "$HOME/.cursor/skills/impeccable" ] || [ -d "$HOME/.claude/skills/impeccable" ]; then
  echo "[-] impeccable skills already present. Skipping..."
else
  npx --yes impeccable install --scope=global --providers=claude,codex,cursor,gemini,opencode,pi --force \
    || echo "Note: impeccable skills install failed"
fi
echo "==> Updating uv tools"
uv_tool_version() {
  printf '%s\n' "$1" | awk -v tool="$2" '$1 == tool { print $2; exit }'
}

if uv_before=$(uv tool list --show-version-specifiers); then
  for tool in zai-cli graphifyy; do
    before=$(uv_tool_version "$uv_before" "$tool")
    if [ "$tool" = "zai-cli" ]; then
      if ! uv tool install --upgrade zai-cli --python 3; then
        record_result failed
        echo "Warning: uv tool install/upgrade failed: $tool"
        continue
      fi
    else
      if ! uv tool install --upgrade graphifyy --python 3; then
        record_result failed
        echo "Warning: uv tool install/upgrade failed: $tool"
        continue
      fi
    fi
    if uv_after=$(uv tool list --show-version-specifiers); then
      after=$(uv_tool_version "$uv_after" "$tool")
      if [ -z "$after" ]; then
        record_result failed
        echo "Warning: could not verify the installed uv tool: $tool"
      elif [ -z "$before" ]; then
        record_version_result "" "$after"
      else
        record_version_result "$before" "$after"
      fi
    else
      record_result failed
      echo "Warning: could not check uv tool version after install: $tool"
    fi
  done
else
  echo "Warning: could not read installed uv tools before updating"
  for tool in zai-cli graphifyy; do
    if [ "$tool" = "zai-cli" ]; then
      uv tool install --upgrade zai-cli --python 3 || true
    else
      uv tool install --upgrade graphifyy --python 3 || true
    fi
    record_result failed
    echo "Warning: could not classify the uv tool result: $tool"
  done
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
if [ "$FAILED_COUNT" -eq 0 ]; then
  echo "Setup finished"
else
  echo "Setup finished with failures"
fi
echo
echo "Version-managed target summary"
echo "  Targets:   $TARGET_COUNT"
echo "  Installed: $INSTALLED_COUNT"
echo "  Updated:   $UPDATED_COUNT"
echo "  Current:   $CURRENT_COUNT"
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
