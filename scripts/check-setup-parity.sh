#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

for file in \
  install.sh \
  setup/macos.sh \
  setup/windows.ps1 \
  setup/wsl.sh \
  global/AGENTS.md \
  config/nvim/init.lua \
  cursor/cli-config.json \
  git/gitconfig \
  git/hooks/prepare-commit-msg \
  git/hooks/commit-msg; do
  if [ ! -e "$ROOT/$file" ]; then
    echo "missing source file: $file" >&2
    exit 1
  fi
done

require() {
  local file="$1"
  local text="$2"
  local description="$3"

  if ! rg --fixed-strings --quiet "$text" "$ROOT/$file"; then
    echo "missing: $description ($file)" >&2
    return 1
  fi
}

require setup/macos.sh "google-drive" "Google Drive macOS cask"
require setup/macos.sh "onedrive" "OneDrive macOS cask"
require setup/macos.sh "zen" "Zen Browser macOS cask"

require setup/windows.ps1 '"Google.GoogleDrive"' "Google Drive Windows package"
require setup/windows.ps1 '"Microsoft.OneDrive"' "OneDrive Windows package"
require setup/windows.ps1 '"Zen-Team.Zen-Browser"' "Zen Browser Windows package"
require setup/windows.ps1 '"Microsoft.VisualStudioCode"' "VS Code Windows package"
require setup/windows.ps1 '"SlackTechnologies.Slack"' "Slack Windows package"
require setup/windows.ps1 '"Discord.Discord"' "Discord Windows package"
require setup/windows.ps1 "fnm use --install-if-missing lts-latest" "Windows Node LTS bootstrap"
require setup/windows.ps1 "cargo install atlassian-cli" "Windows Atlassian CLI"
require setup/windows.ps1 "Sync-Dotfile" "Windows shared dotfile synchronization"

require setup/wsl.sh '"$DOTFILES/install.sh"' "WSL shared dotfile installation"
require setup/wsl.sh "cargo install atlassian-cli" "WSL Atlassian CLI"

require install.sh 'if [ "$(uname -s)" = "Darwin" ]; then' "macOS-only shell links"

bash -n "$ROOT/install.sh" "$ROOT/setup/wsl.sh" "$0"
if command -v zsh >/dev/null 2>&1; then
  zsh -n "$ROOT/setup/macos.sh"
fi
if command -v pwsh >/dev/null 2>&1; then
  export SETUP_WINDOWS="$ROOT/setup/windows.ps1"
  pwsh -NoProfile -Command '
    $tokens = $null
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile(
      $env:SETUP_WINDOWS,
      [ref]$tokens,
      [ref]$errors
    ) > $null
    if ($errors.Count) {
      $errors | ForEach-Object { Write-Error $_ }
      exit 1
    }
  '
fi

echo "setup parity checks passed"
