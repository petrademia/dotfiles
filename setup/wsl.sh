#!/usr/bin/env bash
# WSL setup - mirrors the macOS stack, adapted for Ubuntu/WSL.
set -euo pipefail

BASHRC="${HOME}/.bashrc"
ZSHRC="${HOME}/.zshrc"

smart_check() {
    local cmd=$1
    local install_path=${2:-}
    if command -v "$cmd" >/dev/null 2>&1 || { [ -n "$install_path" ] && { [ -d "$install_path" ] || [ -f "$install_path" ]; }; }; then
        echo "[-] $cmd already present. Skipping..."
        return 0
    fi
    return 1
}

echo "==> 1) System packages"
sudo apt update
sudo apt install -y \
    build-essential curl wget git zip unzip cmake pkg-config gdb ninja-build \
    jq socat ripgrep fzf tmux neovim graphviz zstd p7zip-full aria2 \
    llvm clang z3 plantuml maven ca-certificates gnupg
sudo apt install -y fastfetch 2>/dev/null || echo "[-] fastfetch not in apt; skipping"

echo "==> 2) GitHub CLI (gh)"
if ! smart_check "gh"; then
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
    sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
        | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
    sudo apt update && sudo apt install -y gh
fi

echo "==> 3) Git & directory setup"
git config --global credential.helper "/mnt/c/Program\ Files/Git/mingw64/bin/git-credential-manager.exe"
mkdir -p "$HOME/code"

echo "==> 4) Rust & Go"
if ! smart_check "rustup" "$HOME/.cargo/bin/rustup"; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
fi
. "$HOME/.cargo/env" 2>/dev/null || true
rustup default stable || echo "Warning: rustup default stable failed"

if ! smart_check "go" "/usr/bin/go"; then
    sudo add-apt-repository ppa:longsleep/golang-backports -y && sudo apt update
    sudo apt install -y golang-go
fi

echo "==> 5) fnm & uv"
if ! smart_check "fnm" "$HOME/.local/share/fnm/fnm"; then
    curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell
fi
export PATH="$HOME/.local/share/fnm:$PATH"
eval "$(fnm env --use-on-cd)"
fnm use --install-if-missing lts-latest
fnm default lts-latest

if ! smart_check "uv" "$HOME/.local/bin/uv"; then
    curl -LsSf https://astral.sh/uv/install.sh | sh
fi
. "$HOME/.local/bin/env" 2>/dev/null || true
uv python install 3 --default

echo "==> 6) SDKMAN!, gradle & xmake"
if [ ! -d "$HOME/.sdkman" ]; then
    export sdkman_auto_answer=true
    curl -s "https://get.sdkman.io?rcupdate=false" | bash
fi
set +u
[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ] && . "$HOME/.sdkman/bin/sdkman-init.sh"
set -u
sdk install gradle </dev/null 2>/dev/null || echo "[-] gradle via sdkman skipped"
echo "    (JDK matrix: run bootstrap/java-wsl.sh)"

if ! smart_check "xmake" "$HOME/.xmake/bin/xmake"; then
    curl -fsSL https://xmake.io/shget.text | bash
fi

echo "==> 7) Extra CLI tools (dust, ngrok)"
if ! smart_check "dust"; then
    cargo install du-dust || echo "[-] dust install skipped"
fi
if ! smart_check "ngrok"; then
    curl -fsSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc \
        | sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null
    echo "deb https://ngrok-agent.s3.amazonaws.com buster main" \
        | sudo tee /etc/apt/sources.list.d/ngrok.list >/dev/null
    sudo apt update && sudo apt install -y ngrok || echo "[-] ngrok install skipped"
fi

echo "==> 8) AI layer: Claude, Codex, OpenCode, Crush, Copilot, Z.ai"
curl -fsSL https://claude.ai/install.sh | bash || echo "[-] claude install skipped"
[ ! -f "$(npm config get prefix)/bin/codex" ] && npm install -g @openai/codex --silent || true

if ! smart_check "opencode" "$HOME/.opencode/bin/opencode"; then
    curl -fsSL https://opencode.ai/install | bash
fi

if ! smart_check "crush"; then
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg
    echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" \
        | sudo tee /etc/apt/sources.list.d/charm.list >/dev/null
    sudo apt update && sudo apt install -y crush || echo "[-] crush install skipped"
fi

npm install -g @z_ai/coding-helper || true
uv tool install zai-cli --python 3 || true
uv tool install graphifyy --python 3 || true

npm install -g playwright || true
npx playwright install chromium || true

npm install -g @github/copilot || true
if command -v gh >/dev/null 2>&1; then
    gh extension install github/gh-copilot --force >/dev/null 2>&1 || true
fi

echo "==> 9) Claude Code & Codex plugins (caveman, ponytail)"
if command -v claude >/dev/null 2>&1; then
    claude plugin marketplace add https://github.com/JuliusBrussee/caveman 2>/dev/null || true
    claude plugin marketplace add https://github.com/DietrichGebert/ponytail 2>/dev/null || true
    claude plugin install caveman 2>/dev/null || echo "Note: caveman plugin install failed"
    claude plugin install ponytail 2>/dev/null || echo "Note: ponytail plugin install failed"
fi
if command -v codex >/dev/null 2>&1; then
    codex plugin marketplace add JuliusBrussee/caveman 2>/dev/null || true
    codex plugin marketplace add DietrichGebert/ponytail 2>/dev/null || true
    codex plugin add caveman@caveman 2>/dev/null || echo "Note: caveman Codex plugin install failed"
    codex plugin add ponytail@ponytail 2>/dev/null || echo "Note: ponytail Codex plugin install failed"
fi

echo "==> 10) RTK (Rust Token Killer)"
if ! command -v rtk >/dev/null 2>&1; then
    RTK_VERSION=$(curl -fsSL https://api.github.com/repos/rtk-ai/rtk/releases/latest 2>/dev/null | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/' || echo "v0.43.0")
    case "$(uname -m)" in
        aarch64|arm64) RTK_ARCH="aarch64" ;;
        *) RTK_ARCH="x86_64" ;;
    esac
    RTK_URL="https://github.com/rtk-ai/rtk/releases/download/${RTK_VERSION}/rtk-${RTK_ARCH}-unknown-linux-gnu.tar.gz"
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

echo "==> 11) Dotfiles"
DOTFILES="$HOME/dotfiles"
if [ ! -d "$DOTFILES" ]; then
    git clone https://github.com/petrademia/dotfiles.git "$DOTFILES"
fi

echo "==> 12) Injecting WSL shell bridge"
BLOCK=$(cat << 'EOF'
# --- MISSION READY DEV ENV (managed by setup/wsl.sh) ---
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
[ -f "$HOME/.local/bin/env" ] && . "$HOME/.local/bin/env"
[ -f "$HOME/.xmake/profile" ] && . "$HOME/.xmake/profile"
[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ] && . "$HOME/.sdkman/bin/sdkman-init.sh"

export PATH="$HOME/.local/share/fnm:$HOME/.local/bin:$HOME/.opencode/bin:$PATH"
export GOPATH="$HOME/go"
export PATH="$PATH:/usr/local/go/bin:$GOPATH/bin"

alias op='/mnt/c/Users/petru/AppData/Local/Microsoft/WindowsApps/op.exe'
alias ssh='ssh.exe'
alias ssh-add='ssh-add.exe'

alias cc='claude'
alias ccr='claude --resume'
alias cdc='cd ~/code'
alias gcp='g++ -std=c++17 -O2 -Wall'
alias neofetch='fastfetch'
alias vim='nvim'
alias vi='nvim'

if command -v podman >/dev/null 2>&1; then
  alias docker='podman'
  alias docker-compose='podman compose'
fi

get-keys() {
  export OPENROUTER_API_KEY=$(op read "op://Private/OpenRouter/credential")
  export ZAI_API_KEY=$(op read "op://Private/ZAI/credential")
  export ANTHROPIC_API_KEY=$(op read "op://Private/Anthropic/credential")
  export GEMINI_API_KEY=$(op read "op://Private/Gemini/credential")
  echo "🔑 AI keys loaded."
}

java-use() {
  local spec="${1:-}" major vendor suffix id
  case "$spec" in
    (*-*) major="${spec%%-*}"; vendor="${spec#*-}" ;;
    (*) echo "Usage: java-use <version>-<temurin|zulu|corretto|liberica|microsoft>"; return 1 ;;
  esac
  case "$vendor" in
    (temurin) suffix=tem ;;
    (zulu) suffix=zulu ;;
    (corretto) suffix=amzn ;;
    (liberica) suffix=librca ;;
    (microsoft) suffix=ms ;;
    (*) echo "Unknown vendor: $vendor"; return 1 ;;
  esac
  id="$(ls -1 "$HOME/.sdkman/candidates/java" 2>/dev/null | grep -E "^${major}[.-].*-${suffix}$" | sort -V | tail -1)"
  [ -z "$id" ] && { echo "No installed JDK for $spec (run bootstrap/java-wsl.sh)"; return 1; }
  sdk use java "$id"
}

command -v fnm >/dev/null 2>&1 && eval "$(fnm env --use-on-cd)"
# --- END MISSION READY DEV ENV ---
EOF
)

for RC in "$BASHRC" "$ZSHRC"; do
    [ -f "$RC" ] || touch "$RC"
    sed -i '/# --- MISSION READY DEV ENV/,/# --- END MISSION READY DEV ENV ---/d' "$RC" 2>/dev/null || true
    echo "$BLOCK" >> "$RC"
done

echo
echo "=== Versions ==="
node --version 2>/dev/null || true
python3 --version 2>/dev/null || true
go version 2>/dev/null || true
rustc --version 2>/dev/null || echo "rustc not found - run 'rustup default stable'"
java -version 2>&1 | head -1 || true
git --version 2>/dev/null || true
gh --version 2>/dev/null | head -1 || true
codex --version 2>/dev/null || true
crush --version 2>/dev/null || true
claude --version 2>/dev/null || true

echo
echo "✅ MISSION COMPLETE: WSL stack deployed (macOS parity)"
echo "Reload your shell: source ~/.zshrc  (or ~/.bashrc)"
