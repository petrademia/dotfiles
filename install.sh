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
link "$DOTFILES/claude/RTK.md" "$HOME/.claude/RTK.md"
link "$DOTFILES/AGENTS.md" "$HOME/AGENTS.md"

mkdir -p "$HOME/Library/Application Support/go"
link "$DOTFILES/go/env" "$HOME/Library/Application Support/go/env"

git config --global include.path "$DOTFILES/git/gitconfig"

echo "dotfiles installed"
