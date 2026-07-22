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
fi

link "$DOTFILES/config/nvim" "$HOME/.config/nvim"
link "$DOTFILES/claude/RTK.md" "$HOME/.claude/RTK.md"
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
mkdir -p "$HOME/.gemini/antigravity-cli/skills"
mkdir -p "$HOME/.agents/skills"
mkdir -p "$HOME/.codex/skills"

link "$DOTFILES/ai/commands/grammar.md" "$HOME/.cursor/commands/grammar.md"
link "$DOTFILES/ai/commands/grammar.md" "$HOME/.claude/commands/grammar.md"
link "$DOTFILES/ai/commands/grammar.md" "$HOME/.zai/commands/grammar.md"
link "$DOTFILES/ai/gemini/grammar.toml" "$HOME/.gemini/commands/grammar.toml"
link "$DOTFILES/ai/codex/grammar" "$HOME/.agents/skills/grammar"
link "$DOTFILES/ai/codex/grammar" "$HOME/.codex/skills/grammar"
link "$DOTFILES/ai/codex/grammar" "$HOME/.gemini/antigravity-cli/skills/grammar"

link "$DOTFILES/ai/commands/leetcode.md" "$HOME/.cursor/commands/leetcode.md"
link "$DOTFILES/ai/commands/leetcode.md" "$HOME/.claude/commands/leetcode.md"
link "$DOTFILES/ai/commands/leetcode.md" "$HOME/.zai/commands/leetcode.md"
link "$DOTFILES/ai/gemini/leetcode.toml" "$HOME/.gemini/commands/leetcode.toml"
link "$DOTFILES/ai/codex/leetcode" "$HOME/.agents/skills/leetcode"
link "$DOTFILES/ai/codex/leetcode" "$HOME/.codex/skills/leetcode"
link "$DOTFILES/ai/codex/leetcode" "$HOME/.gemini/antigravity-cli/skills/leetcode"

link "$DOTFILES/ai/commands/handoff.md" "$HOME/.cursor/commands/handoff.md"
link "$DOTFILES/ai/commands/handoff.md" "$HOME/.claude/commands/handoff.md"
link "$DOTFILES/ai/commands/handoff.md" "$HOME/.zai/commands/handoff.md"
link "$DOTFILES/ai/gemini/handoff.toml" "$HOME/.gemini/commands/handoff.toml"
link "$DOTFILES/ai/codex/handoff" "$HOME/.agents/skills/handoff"
link "$DOTFILES/ai/codex/handoff" "$HOME/.codex/skills/handoff"
link "$DOTFILES/ai/codex/handoff" "$HOME/.gemini/antigravity-cli/skills/handoff"

git config --global include.path "$DOTFILES/git/gitconfig"

chmod +x "$DOTFILES/git/hooks/prepare-commit-msg" "$DOTFILES/git/hooks/commit-msg"
git config --global core.hooksPath "$DOTFILES/git/hooks"

echo "dotfiles installed"
