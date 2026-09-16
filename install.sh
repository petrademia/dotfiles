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

# Cursor's pstack plugin is distributed from the cursor/plugins monorepo. Keep
# the checkout outside dotfiles and copy the plugin into Cursor's user-level
# local-plugin directory. Cursor does not register the old symlink install.
install_cursor_pstack() {
  local checkout="$HOME/.local/share/pstack-cursor"
  local local_plugin="$HOME/.cursor/plugins/local/pstack"
  local repo="https://github.com/cursor/plugins.git"

  mkdir -p "$HOME/.cursor/plugins/local" "$HOME/.local/share"

  if [ ! -d "$checkout/.git" ]; then
    echo "==> Installing Cursor pstack plugin"
    if ! git clone --depth 1 --filter=blob:none --sparse "$repo" "$checkout"; then
      echo "[!] Cursor pstack install failed; install it from Cursor's Customize page"
      return 0
    fi
  fi

  if ! git -C "$checkout" sparse-checkout set pstack; then
    echo "[!] Cursor pstack checkout failed; install it from Cursor's Customize page"
    return 0
  fi

  if [ ! -f "$checkout/pstack/.cursor-plugin/plugin.json" ]; then
    echo "[!] Cursor pstack manifest not found; install it from Cursor's Customize page"
    return 0
  fi

  if [ -L "$local_plugin" ]; then
    if [ "$(readlink "$local_plugin")" = "$checkout/pstack" ]; then
      rm "$local_plugin"
    else
      echo "[-] Cursor pstack path is managed elsewhere. Skipping..."
      return 0
    fi
  elif [ -e "$local_plugin" ]; then
    echo "[-] Cursor pstack plugin already present. Skipping..."
    return 0
  fi

  if cp -R "$checkout/pstack" "$local_plugin"; then
    echo "[+] Cursor pstack plugin installed"
  else
    echo "[!] Could not copy Cursor pstack plugin; install it from Cursor's Customize page"
  fi
}

install_cursor_pstack

remove_duplicate_cursor_pstack_skills() {
  local plugin_root="$HOME/.cursor/plugins/local/pstack"
  local source_root="$HOME/.local/share/pstack-cursor/pstack/skills"
  local source_skill plugin_skill global_skill
  local skill_name

  if [ -L "$plugin_root" ]; then
    return 0
  fi

  for source_skill in "$source_root"/*; do
    [ -f "$source_skill/SKILL.md" ] || continue
    skill_name="${source_skill##*/}"
    plugin_skill="$plugin_root/skills/$skill_name/SKILL.md"
    global_skill="$HOME/.agents/skills/$skill_name"
    [ -f "$plugin_skill" ] || continue

    if [ -L "$global_skill" ] && [ "$(readlink "$global_skill")" = "$source_skill" ]; then
      if rm "$plugin_skill"; then
        echo "[-] Using the shared user-level pstack skill in Cursor: $skill_name"
      fi
    elif [ -f "$global_skill/SKILL.md" ] && cmp -s "$global_skill/SKILL.md" "$source_skill/SKILL.md"; then
      if rm "$plugin_skill"; then
        echo "[-] Using the shared user-level pstack skill in Cursor: $skill_name"
      fi
    fi
  done
}

install_pstack_global_skills() {
  local source_root="$HOME/.local/share/pstack-cursor/pstack/skills"
  local source_skill
  local skill_root
  local destination
  local skill_name
  local installed=0
  local preserved=0
  local failed=0
  local skill_roots=(
    "$HOME/.agents/skills"
    "$HOME/.claude/skills"
    "$HOME/.gemini/skills"
    "$HOME/.gemini/config/skills"
    "$HOME/.gemini/antigravity/skills"
    "$HOME/.gemini/antigravity-cli/skills"
  )

  if [ ! -d "$source_root" ]; then
    echo "[!] pstack skills source missing; skipping other clients"
    return 0
  fi

  for source_skill in "$source_root"/*; do
    [ -f "$source_skill/SKILL.md" ] || continue
    skill_name="${source_skill##*/}"
    for skill_root in "${skill_roots[@]}"; do
      mkdir -p "$skill_root"
      destination="$skill_root/$skill_name"
      if [ -L "$destination" ] && [ "$(readlink "$destination")" = "$source_skill" ]; then
        continue
      fi
      if [ -e "$destination" ] || [ -L "$destination" ]; then
        preserved=$((preserved + 1))
        continue
      fi
      if ln -s "$source_skill" "$destination"; then
        installed=$((installed + 1))
      else
        echo "[!] Could not link pstack skill: $destination"
        failed=$((failed + 1))
      fi
    done
  done
  echo "[+] pstack skills installed: $installed linked, $preserved existing paths preserved, $failed failed"
}

install_pstack_global_skills
remove_duplicate_cursor_pstack_skills

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
