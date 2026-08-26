#!/bin/bash
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

link() {
  local src="$1"
  local dest="$2"

  mkdir -p "$(dirname "$dest")"
  ln -sfn "$src" "$dest"
  echo "linked $dest -> $src"
}

if [ "$(uname -s)" = "Darwin" ]; then
  link "$DOTFILES/shell/.zshrc" "$HOME/.zshrc"
  link "$DOTFILES/config/zsh" "$HOME/.config/zsh"
  link "$DOTFILES/config/containers/containers.conf" "$HOME/.config/containers/containers.conf"
fi

link "$DOTFILES/config/nvim" "$HOME/.config/nvim"
link "$DOTFILES/config/zellij" "$HOME/.config/zellij"
link "$DOTFILES/global/AGENTS.md" "$HOME/AGENTS.md"
link "$DOTFILES/global/AGENTS.md" "$HOME/.claude/CLAUDE.md"

case "$(uname -s)" in
  Darwin) GO_ENV_DIR="$HOME/Library/Application Support/go" ;;
  *) GO_ENV_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/go" ;;
esac
mkdir -p "$GO_ENV_DIR"
link "$DOTFILES/go/env" "$GO_ENV_DIR/env"

mkdir -p "$HOME/.cursor"
link "$DOTFILES/cursor/cli-config.json" "$HOME/.cursor/cli-config.json"

mkdir -p "$HOME/.cursor/commands"
mkdir -p "$HOME/.claude/commands"
mkdir -p "$HOME/.zai/commands"
mkdir -p "$HOME/.gemini/commands"
# Antigravity Desktop, CLI, and IDE look in different skill roots.
# ~/.gemini/config/skills is the only global path shared by all three.
mkdir -p "$HOME/.gemini/config/skills"
mkdir -p "$HOME/.gemini/antigravity/skills"
mkdir -p "$HOME/.gemini/antigravity-cli/skills"
mkdir -p "$HOME/.gemini/skills"
mkdir -p "$HOME/.agents/skills"
mkdir -p "$HOME/.codex/skills"

# Link a skill folder into every Antigravity-relevant global root (+ agents/codex).
link_skill() {
  local src="$1"
  local name="$2"
  [ -d "$src" ] || return 0
  link "$src" "$HOME/.agents/skills/$name"
  link "$src" "$HOME/.codex/skills/$name"
  link "$src" "$HOME/.gemini/config/skills/$name"
  link "$src" "$HOME/.gemini/antigravity/skills/$name"
  link "$src" "$HOME/.gemini/antigravity-cli/skills/$name"
  link "$src" "$HOME/.gemini/skills/$name"
}

for command in grammar leetcode handoff; do
  link "$DOTFILES/ai/commands/${command}.md" "$HOME/.cursor/commands/${command}.md"
  link "$DOTFILES/ai/commands/${command}.md" "$HOME/.claude/commands/${command}.md"
  link "$DOTFILES/ai/commands/${command}.md" "$HOME/.zai/commands/${command}.md"
  link "$DOTFILES/ai/gemini/${command}.toml" "$HOME/.gemini/commands/${command}.toml"
  link_skill "$DOTFILES/ai/codex/${command}" "$command"
done

# Matt Pocock / npx skills land in ~/.agents/skills; mirror the ones we use
# into Antigravity global roots (Desktop/CLI do not share the same paths;
# CLI does not reliably read ~/.agents/skills as global).
for name in grill-with-docs grill-me grilling domain-modeling; do
  if [ -d "$HOME/.agents/skills/$name" ]; then
    src=$(cd "$HOME/.agents/skills/$name" && pwd -P)
    link "$src" "$HOME/.gemini/config/skills/$name"
    link "$src" "$HOME/.gemini/antigravity/skills/$name"
    link "$src" "$HOME/.gemini/antigravity-cli/skills/$name"
    link "$src" "$HOME/.gemini/skills/$name"
  fi
done

git config --global include.path "$DOTFILES/git/gitconfig"

chmod +x "$DOTFILES/git/hooks/prepare-commit-msg" "$DOTFILES/git/hooks/commit-msg"
git config --global core.hooksPath "$DOTFILES/git/hooks"

# Podman docker shims: Make/scripts need a real PATH binary (aliases are shell-only).
if command -v podman >/dev/null 2>&1; then
  mkdir -p "$HOME/.local/bin"
  chmod +x "$DOTFILES/bin/docker" "$DOTFILES/bin/docker-compose"
  link "$DOTFILES/bin/docker" "$HOME/.local/bin/docker"
  link "$DOTFILES/bin/docker-compose" "$HOME/.local/bin/docker-compose"
fi

echo "dotfiles installed"
