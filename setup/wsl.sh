#!/usr/bin/env bash
# WSL setup - mirrors the macOS stack, adapted for Ubuntu/WSL.
set -euo pipefail

BASHRC="${HOME}/.bashrc"
ZSHRC="${HOME}/.zshrc"
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

version_matches() {
    [ -n "$1" ] && [ "${1#v}" = "${2#v}" ]
}

latest_github_tag() {
    curl -fsSL "https://api.github.com/repos/$1/releases/latest" \
        | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])'
}

# Direct installers use this guard when they do not expose a safe version check.
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
    llvm clang z3 plantuml maven ca-certificates gnupg sqlite3 libsqlite3-dev
record_result updated
if sudo apt install -y fastfetch 2>/dev/null; then record_result updated
else record_result skipped; echo "[-] fastfetch not in apt; skipping"; fi

echo "==> 1b) Zellij (terminal multiplexer)"
ZELLIJ_VER=$(latest_github_tag zellij-org/zellij 2>/dev/null || true)
ZELLIJ_CURRENT=$(zellij --version 2>/dev/null | awk '{print $2}' || true)
if [ -z "$ZELLIJ_CURRENT" ] || { [ -n "$ZELLIJ_VER" ] && ! version_matches "$ZELLIJ_CURRENT" "$ZELLIJ_VER"; }; then
    [ -n "$ZELLIJ_VER" ] || ZELLIJ_VER="v0.44.3"
    case "$(uname -m)" in
        aarch64|arm64) ZELLIJ_ARCH="aarch64" ;;
        *) ZELLIJ_ARCH="x86_64" ;;
    esac
    ZELLIJ_URL="https://github.com/zellij-org/zellij/releases/download/${ZELLIJ_VER}/zellij-${ZELLIJ_ARCH}-unknown-linux-musl.tar.gz"
    if curl -fL "$ZELLIJ_URL" -o /tmp/zellij.tar.gz \
        && tar xzf /tmp/zellij.tar.gz -C /tmp \
        && sudo install -m 0755 /tmp/zellij /usr/local/bin/zellij; then
        if [ -n "$ZELLIJ_CURRENT" ]; then record_result updated; echo "Zellij ${ZELLIJ_VER} updated"
        else record_result installed; echo "Zellij ${ZELLIJ_VER} installed"; fi
    else
        record_result failed
        echo "[-] Zellij install/update failed"
    fi
    rm -f /tmp/zellij.tar.gz /tmp/zellij
else
    record_result skipped
    echo "[-] Zellij ${ZELLIJ_CURRENT} is current"
fi

echo "==> 1c) Helix (modal editor)"
HELIX_VER=$(latest_github_tag helix-editor/helix 2>/dev/null || true)
HELIX_CMD=""
command -v hx >/dev/null 2>&1 && HELIX_CMD=hx
if [ -z "$HELIX_CMD" ] && command -v helix >/dev/null 2>&1; then HELIX_CMD=helix; fi
HELIX_CURRENT=$([ -n "$HELIX_CMD" ] && "$HELIX_CMD" --version 2>/dev/null | awk '{print $2}' || true)
if [ -z "$HELIX_CURRENT" ] || { [ -n "$HELIX_VER" ] && ! version_matches "$HELIX_CURRENT" "$HELIX_VER"; }; then
    [ -n "$HELIX_VER" ] || HELIX_VER="25.07.1"
    case "$(uname -m)" in
        aarch64|arm64) HELIX_ARCH="aarch64-linux" ;;
        *) HELIX_ARCH="x86_64-linux" ;;
    esac
    HELIX_URL="https://github.com/helix-editor/helix/releases/download/${HELIX_VER}/helix-${HELIX_VER}-${HELIX_ARCH}.tar.xz"
    if curl -fL "$HELIX_URL" -o /tmp/helix.tar.xz \
        && tar xJf /tmp/helix.tar.xz -C /tmp \
        && sudo install -m 0755 "/tmp/helix-${HELIX_VER}-${HELIX_ARCH}/hx" /usr/local/bin/hx; then
        if [ -n "$HELIX_CURRENT" ]; then record_result updated; echo "Helix ${HELIX_VER} updated"
        else record_result installed; echo "Helix ${HELIX_VER} installed"; fi
    else
        record_result failed
        echo "[-] Helix install/update failed"
    fi
    rm -rf /tmp/helix.tar.xz "/tmp/helix-${HELIX_VER}-${HELIX_ARCH}"
else
    record_result skipped
    echo "[-] Helix ${HELIX_CURRENT} is current"
fi

echo "==> 2) GitHub CLI (gh)"
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | sudo dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg
sudo chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
if sudo apt update && sudo apt install -y gh; then record_result updated
else record_result failed; echo "[-] gh install/update failed"; fi

echo "==> 3) Git & directory setup"
WINDOWS_USER_PROFILE=""
if command -v powershell.exe >/dev/null 2>&1; then
    WINDOWS_USER_PROFILE=$(powershell.exe -NoProfile -Command '$env:USERPROFILE' 2>/dev/null | tr -d '\r\n')
fi
GCM_ROOT=""
if [ -n "$WINDOWS_USER_PROFILE" ] && command -v wslpath >/dev/null 2>&1; then
    GCM_ROOT=$(wslpath -u "$WINDOWS_USER_PROFILE" 2>/dev/null || true)
fi
GCM_PATH=""
for candidate in \
    "$GCM_ROOT/scoop/apps/git/current/mingw64/bin/git-credential-manager.exe" \
    "$GCM_ROOT/scoop/apps/git/current/mingw64/libexec/git-core/git-credential-manager.exe" \
    "$GCM_ROOT/scoop/apps/git/current/usr/bin/git-credential-manager.exe" \
    "/mnt/c/Program Files/Git/mingw64/bin/git-credential-manager.exe" \
    "/mnt/c/Program Files/Git/mingw64/libexec/git-core/git-credential-manager.exe"; do
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then
        GCM_PATH="$candidate"
        break
    fi
done
if [ -n "$GCM_PATH" ]; then
    if git config --global credential.helper "$GCM_PATH"; then
        echo "Using Git Credential Manager: $GCM_PATH"
    else
        echo "Warning: could not configure Git Credential Manager; leaving credential.helper unchanged" >&2
    fi
else
    echo "Warning: Git Credential Manager not found; leaving credential.helper unchanged" >&2
fi
mkdir -p "$HOME/code"

echo "==> 4) Rust & Go"
if ! smart_check "rustup" "$HOME/.cargo/bin/rustup"; then
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
fi
. "$HOME/.cargo/env" 2>/dev/null || true
if rustup update stable; then record_result updated
else record_result failed; echo "Warning: rustup update stable failed"; fi
rustup default stable || echo "Warning: rustup default stable failed"
if ! smart_check "atlassian-cli"; then
    cargo install atlassian-cli || echo "[-] atlassian-cli install skipped"
fi

if ! smart_check "go" "/usr/bin/go"; then
    sudo add-apt-repository ppa:longsleep/golang-backports -y && sudo apt update
fi
if sudo apt install -y golang-go; then record_result updated
else record_result failed; echo "[-] Go install/update failed"; fi

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
    if ! curl -s "https://get.sdkman.io?rcupdate=false" | bash; then
        echo "[-] SDKMAN! installer returned a failure; continuing with the remaining WSL setup" >&2
    fi
fi
set +u
[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ] && . "$HOME/.sdkman/bin/sdkman-init.sh"
set -u
if sdk update >/dev/null 2>&1; then record_result updated
else record_result skipped; echo "[-] SDKMAN! metadata update skipped"; fi
if sdk current gradle >/dev/null 2>&1; then
    if sdk upgrade gradle </dev/null 2>/dev/null; then record_result updated
    else record_result failed; echo "[-] gradle via sdkman update failed"; fi
else
    if sdk install gradle </dev/null 2>/dev/null; then record_result installed
    else record_result failed; echo "[-] gradle via sdkman install failed"; fi
fi
echo "    (JDK matrix: run bootstrap/java-wsl.sh)"

if ! smart_check "xmake" "$HOME/.xmake/bin/xmake"; then
    curl -fsSL https://xmake.io/shget.text | bash
fi

echo "==> 7) Extra CLI tools (dust, ngrok)"
if ! smart_check "dust"; then
    cargo install du-dust || echo "[-] dust install skipped"
fi
curl -fsSL https://ngrok-agent.s3.amazonaws.com/ngrok.asc \
    | sudo tee /etc/apt/trusted.gpg.d/ngrok.asc >/dev/null
echo "deb https://ngrok-agent.s3.amazonaws.com buster main" \
    | sudo tee /etc/apt/sources.list.d/ngrok.list >/dev/null
if sudo apt update && sudo apt install -y ngrok; then record_result updated
else record_result failed; echo "[-] ngrok install/update failed"; fi

if ! smart_check "llama" "$HOME/.llama-app/llama"; then
    curl -fsSL https://llama.app/install.sh | sh || echo "[-] llama.cpp install skipped"
fi

echo "==> 7b) Kubernetes tools (kubectl, kind, k3d)"
ARCH=$(dpkg --print-architecture)
case "$ARCH" in
    amd64) K8S_ARCH="amd64" ;;
    arm64) K8S_ARCH="arm64" ;;
    *) K8S_ARCH="$ARCH" ;;
esac

KVER=$(curl -fsSL https://dl.k8s.io/release/stable.txt 2>/dev/null || true)
KUBECTL_CURRENT=$(kubectl version --client --output=json 2>/dev/null \
    | python3 -c 'import json,sys; print(json.load(sys.stdin)["clientVersion"]["gitVersion"])' 2>/dev/null || true)
if [ -z "$KUBECTL_CURRENT" ] || { [ -n "$KVER" ] && ! version_matches "$KUBECTL_CURRENT" "$KVER"; }; then
    [ -n "$KVER" ] || KVER="v1.34.1"
    curl -fsSLo /tmp/kubectl "https://dl.k8s.io/release/${KVER}/bin/linux/${K8S_ARCH}/kubectl" \
        && sudo install -m 0755 /tmp/kubectl /usr/local/bin/kubectl \
        && { [ -n "$KUBECTL_CURRENT" ] && record_result updated || record_result installed; } \
        || { record_result failed; echo "[-] kubectl install/update failed"; }
    rm -f /tmp/kubectl
else
    record_result skipped
    echo "[-] kubectl ${KUBECTL_CURRENT} is current"
fi

KIND_VER=$(latest_github_tag kubernetes-sigs/kind 2>/dev/null || true)
KIND_CURRENT=$(kind version 2>/dev/null | sed -n 's/.*kind //p' | awk '{print $1}' || true)
if [ -z "$KIND_CURRENT" ] || { [ -n "$KIND_VER" ] && ! version_matches "$KIND_CURRENT" "$KIND_VER"; }; then
    [ -n "$KIND_VER" ] || KIND_VER="v0.32.0"
    curl -fsSLo /tmp/kind "https://kind.sigs.k8s.io/dl/${KIND_VER}/kind-linux-${K8S_ARCH}" \
        && sudo install -m 0755 /tmp/kind /usr/local/bin/kind \
        && { [ -n "$KIND_CURRENT" ] && record_result updated || record_result installed; } \
        || { record_result failed; echo "[-] kind install/update failed"; }
    rm -f /tmp/kind
else
    record_result skipped
    echo "[-] kind ${KIND_CURRENT} is current"
fi

K3D_VER=$(latest_github_tag k3d-io/k3d 2>/dev/null || true)
K3D_CURRENT=$(k3d version 2>/dev/null | sed -n 's/.*k3d version //p' | awk '{print $1}' || true)
if [ -z "$K3D_CURRENT" ] || { [ -n "$K3D_VER" ] && ! version_matches "$K3D_CURRENT" "$K3D_VER"; }; then
    if curl -fsSL https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash; then
        [ -n "$K3D_CURRENT" ] && record_result updated || record_result installed
    else
        record_result failed
        echo "[-] k3d install/update failed"
    fi
else
    record_result skipped
    echo "[-] k3d ${K3D_CURRENT} is current"
fi

echo "==> 8) AI layer: Claude, Codex, OpenCode, Crush, Copilot, Z.ai"
curl -fsSL https://claude.ai/install.sh | bash || echo "[-] claude install skipped"
[ ! -f "$(npm config get prefix)/bin/codex" ] && npm install -g @openai/codex --silent || true

if ! smart_check "opencode" "$HOME/.opencode/bin/opencode"; then
    curl -fsSL https://opencode.ai/install | bash
fi

sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor --yes -o /etc/apt/keyrings/charm.gpg
echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" \
    | sudo tee /etc/apt/sources.list.d/charm.list >/dev/null
if sudo apt update && sudo apt install -y crush; then record_result updated
else record_result failed; echo "[-] crush install/update failed"; fi

run_npm_global() {
    if npm install -g "$@" --silent; then record_result updated
    else record_result failed; echo "[-] npm install/update failed: $1"; fi
}

run_npm_global @z_ai/coding-helper
if npm install -g --ignore-scripts @earendil-works/pi-coding-agent --silent; then record_result updated
else record_result failed; echo "[-] npm install/update failed: @earendil-works/pi-coding-agent"; fi
run_npm_global reasonix
run_npm_global @deepseek-ai/dsh
run_npm_global wrangler
run_npm_global openclaw@latest
run_npm_global impeccable
uv tool install --upgrade zai-cli --python 3 || true
uv tool install --upgrade graphifyy --python 3 || true

run_npm_global playwright
npx playwright install chromium || true

run_npm_global @github/copilot
if command -v gh >/dev/null 2>&1; then
    gh extension install github/gh-copilot --force >/dev/null 2>&1 || true
fi

if ! smart_check "hermes" "$HOME/.local/bin/hermes"; then
    curl -fsSL https://hermes-agent.nousresearch.com/install.sh |
        bash -s -- --skip-setup --skip-browser --non-interactive || echo "[-] Hermes Agent install skipped"
fi

if ! smart_check "kimi"; then
    curl -fsSL https://code.kimi.com/kimi-code/install.sh | bash || echo "[-] Kimi Code CLI install skipped"
fi

if ! smart_check "agy" "$HOME/.local/bin/agy"; then
    curl -fsSL https://antigravity.google/cli/install.sh | bash || echo "[-] Antigravity CLI (agy) install skipped"
fi

if ! smart_check "omp"; then
    curl -fsSL https://omp.sh/install | sh || echo "[-] Oh My Pi (omp) install skipped"
fi

if ! smart_check "goose" "$HOME/.local/bin/goose"; then
    curl -fsSL https://github.com/aaif-goose/goose/releases/download/stable/download_cli.sh |
        CONFIGURE=false bash || echo "[-] Goose CLI install skipped"
fi

npx --yes impeccable install --scope=global --providers=claude,codex,cursor,gemini,opencode,pi --force || echo "[-] impeccable skills install skipped"

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

echo "==> 10) Dotfiles"
DOTFILES="$HOME/dotfiles"
if [ ! -d "$DOTFILES" ]; then
    git clone https://github.com/petrademia/dotfiles.git "$DOTFILES"
fi

echo "==> Installing shared dotfiles"
"$DOTFILES/install.sh"

echo "==> 12) Injecting WSL shell bridge"
WIN_USER="${WSL_WIN_USER:-}"
if [ -z "$WIN_USER" ] && command -v powershell.exe >/dev/null 2>&1; then
  WIN_USER="$(powershell.exe -NoProfile -Command '$env:USERNAME' 2>/dev/null | tr -d '\r\n')"
fi
if [ -z "$WIN_USER" ] && [ -d /mnt/c/Users ]; then
  for d in /mnt/c/Users/*/; do
    base=$(basename "$d")
    case "$base" in Public|Default|"Default User"|All\ Users) continue ;; esac
    if [ -e "${d}AppData/Local/Microsoft/WindowsApps/op.exe" ] || [ -d "${d}AppData/Local/Programs/1Password" ]; then
      WIN_USER="$base"
      break
    fi
  done
fi
if [ -z "$WIN_USER" ]; then
  echo "Warning: could not detect Windows username; set WSL_WIN_USER and re-run setup/wsl.sh" >&2
  WIN_USER="UNKNOWN"
fi

BLOCK=$(cat << EOF
# --- DOTFILES DEV ENV (managed by setup/wsl.sh) ---
[ -f "\$HOME/.cargo/env" ] && . "\$HOME/.cargo/env"
[ -f "\$HOME/.local/bin/env" ] && . "\$HOME/.local/bin/env"
[ -f "\$HOME/.xmake/profile" ] && . "\$HOME/.xmake/profile"
[ -s "\$HOME/.sdkman/bin/sdkman-init.sh" ] && . "\$HOME/.sdkman/bin/sdkman-init.sh"

export PATH="\$HOME/.local/share/fnm:\$HOME/.local/bin:\$HOME/.opencode/bin:\$HOME/.llama-app:\$PATH"
export GOPATH="\$HOME/go"
export PATH="\$PATH:/usr/local/go/bin:\$GOPATH/bin"

alias op='/mnt/c/Users/${WIN_USER}/AppData/Local/Microsoft/WindowsApps/op.exe'
alias ssh='ssh.exe'
alias ssh-add='ssh-add.exe'

alias cc='claude'
alias ccr='claude --resume'
alias cdc='cd ~/code'
alias gcp='g++ -std=c++17 -O2 -Wall'
alias neofetch='fastfetch'
alias vim='nvim'
alias vi='nvim'

if command -v ollama.exe >/dev/null 2>&1; then
  alias ollama='ollama.exe'
fi

if command -v podman >/dev/null 2>&1; then
  alias docker='podman'
  alias docker-compose='podman compose'
fi

get-keys() {
  export OPENROUTER_API_KEY=\$(op read "op://Private/OpenRouter/credential")
  export ZAI_API_KEY=\$(op read "op://Private/ZAI/credential")
  export ANTHROPIC_API_KEY=\$(op read "op://Private/Anthropic/credential")
  export GEMINI_API_KEY=\$(op read "op://Private/Gemini/credential")
  echo "AI keys loaded."
}

java-use() {
  local spec="\${1:-}" major vendor suffix id
  case "\$spec" in
    (*-*) major="\${spec%%-*}"; vendor="\${spec#*-}" ;;
    (*) echo "Usage: java-use <version>-<temurin|zulu|corretto|liberica|microsoft>"; return 1 ;;
  esac
  case "\$vendor" in
    (temurin) suffix=tem ;;
    (zulu) suffix=zulu ;;
    (corretto) suffix=amzn ;;
    (liberica) suffix=librca ;;
    (microsoft) suffix=ms ;;
    (*) echo "Unknown vendor: \$vendor"; return 1 ;;
  esac
  id="\$(ls -1 "\$HOME/.sdkman/candidates/java" 2>/dev/null | grep -E "^\${major}[.-].*-\${suffix}\$" | sort -V | tail -1)"
  [ -z "\$id" ] && { echo "No installed JDK for \$spec (run bootstrap/java-wsl.sh)"; return 1; }
  sdk use java "\$id"
}

command -v fnm >/dev/null 2>&1 && eval "\$(fnm env --use-on-cd)"
# --- END DOTFILES DEV ENV ---
EOF
)

for RC in "$BASHRC" "$ZSHRC"; do
    [ -f "$RC" ] || touch "$RC"
    sed -i '/# --- DOTFILES DEV ENV/,/# --- END DOTFILES DEV ENV ---/d' "$RC" 2>/dev/null || true
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
echo "SETUP COMPLETE: WSL stack deployed (macOS parity)"
echo
echo "Setup summary"
echo "  Installed: $INSTALLED_COUNT"
echo "  Updated:   $UPDATED_COUNT"
echo "  Skipped:   $SKIPPED_COUNT"
echo "  Failed:    $FAILED_COUNT"
echo "Reload your shell: source ~/.zshrc  (or ~/.bashrc)"
