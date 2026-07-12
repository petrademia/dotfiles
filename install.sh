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

link "$DOTFILES/shell/.zshrc" "$HOME/.zshrc"
link "$DOTFILES/config/zsh" "$HOME/.config/zsh"
link "$DOTFILES/config/nvim" "$HOME/.config/nvim"
link "$DOTFILES/claude/RTK.md" "$HOME/.claude/RTK.md"
link "$DOTFILES/AGENTS.md" "$HOME/AGENTS.md"

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
mkdir -p "$HOME/.agents/skills"
mkdir -p "$HOME/.codex/skills"

link "$DOTFILES/ai/commands/grammar.md" "$HOME/.cursor/commands/grammar.md"
link "$DOTFILES/ai/commands/grammar.md" "$HOME/.claude/commands/grammar.md"
link "$DOTFILES/ai/commands/grammar.md" "$HOME/.zai/commands/grammar.md"
link "$DOTFILES/ai/gemini/grammar.toml" "$HOME/.gemini/commands/grammar.toml"
link "$DOTFILES/ai/codex/grammar" "$HOME/.agents/skills/grammar"
link "$DOTFILES/ai/codex/grammar" "$HOME/.codex/skills/grammar"

link "$DOTFILES/ai/commands/leetcode.md" "$HOME/.cursor/commands/leetcode.md"
link "$DOTFILES/ai/commands/leetcode.md" "$HOME/.claude/commands/leetcode.md"
link "$DOTFILES/ai/commands/leetcode.md" "$HOME/.zai/commands/leetcode.md"
link "$DOTFILES/ai/gemini/leetcode.toml" "$HOME/.gemini/commands/leetcode.toml"
link "$DOTFILES/ai/codex/leetcode" "$HOME/.agents/skills/leetcode"
link "$DOTFILES/ai/codex/leetcode" "$HOME/.codex/skills/leetcode"

git config --global include.path "$DOTFILES/git/gitconfig"

chmod +x "$DOTFILES/git/hooks/prepare-commit-msg"
git config --global core.hooksPath "$DOTFILES/git/hooks"

echo "dotfiles installed"
