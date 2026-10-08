#!/bin/bash
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

link() {
  local src="$1"
  local dest="$2"

  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
    return 0
  fi

  mkdir -p "$(dirname "$dest")"
  ln -sfn "$src" "$dest"
  echo "linked $dest -> $src"
}

setup_codex_work() {
  mkdir -p "$HOME/.codex-work"
  chmod 700 "$HOME/.codex-work"
  link "$DOTFILES/global/AGENTS.md" "$HOME/.codex-work/AGENTS.md"
  link "$HOME/.codex/skills" "$HOME/.codex-work/skills"
}

if [ "$(uname -s)" = "Darwin" ]; then
  link "$DOTFILES/shell/.zshrc" "$HOME/.zshrc"
  link "$DOTFILES/config/zsh" "$HOME/.config/zsh"
  mkdir -p "$HOME/.claude-work"
  chmod 700 "$HOME/.claude-work"
  link "$DOTFILES/global/AGENTS.md" "$HOME/.claude-work/CLAUDE.md"
  link "$HOME/.claude/skills" "$HOME/.claude-work/skills"
  if ! python3 "$DOTFILES/bootstrap/claude-work.py"; then
    echo "[!] Could not set up Claude profile launchers"
  fi
  link "$DOTFILES/config/containers/containers.conf" "$HOME/.config/containers/containers.conf"
fi

link "$DOTFILES/config/nvim" "$HOME/.config/nvim"
link "$DOTFILES/config/zellij" "$HOME/.config/zellij"
link "$DOTFILES/global/AGENTS.md" "$HOME/AGENTS.md"
link "$DOTFILES/global/AGENTS.md" "$HOME/.claude/CLAUDE.md"
link "$DOTFILES/global/AGENTS.md" "$HOME/.codex/AGENTS.md"
setup_codex_work

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
  elif [ -n "$(git -C "$checkout" status --porcelain)" ]; then
    echo "[!] Cursor pstack checkout has local changes; preserving it without updating"
  elif ! git -C "$checkout" pull --ff-only; then
    echo "[!] Cursor pstack checkout could not be updated; keeping its current version"
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
    if grep -Eq '"name"[[:space:]]*:[[:space:]]*"pstack"' "$local_plugin/.cursor-plugin/plugin.json" 2>/dev/null \
      && grep -Eq '"repository"[[:space:]]*:[[:space:]]*"https://github\.com/cursor/plugins"' \
        "$local_plugin/.cursor-plugin/plugin.json" 2>/dev/null; then
      :
    else
      echo "[-] Cursor pstack path is not a pstack plugin. Skipping..."
      return 0
    fi
  fi

  local source_skill skill_name global_skill changes
  local sync_options=(--recursive --links --perms --times --omit-dir-times --checksum --itemize-changes)
  for source_skill in "$checkout/pstack/skills"/*; do
    [ -f "$source_skill/SKILL.md" ] || continue
    skill_name="${source_skill##*/}"
    global_skill="$HOME/.agents/skills/$skill_name"
    if { [ -L "$global_skill" ] && [ "$(readlink "$global_skill")" = "$source_skill" ]; } \
      || { [ -f "$global_skill/SKILL.md" ] && cmp -s "$global_skill/SKILL.md" "$source_skill/SKILL.md"; }; then
      sync_options+=("--exclude=/skills/$skill_name/SKILL.md")
    fi
  done

  if changes=$(rsync "${sync_options[@]}" "$checkout/pstack/" "$local_plugin/"); then
    if [ -n "$changes" ]; then
      echo "[+] Cursor pstack plugin synced from checkout"
    fi
  else
    echo "[!] Could not update Cursor pstack plugin"
  fi
}

install_cursor_pstack

remove_duplicate_cursor_pstack_skills() {
  local plugin_root="$HOME/.cursor/plugins/local/pstack"
  local source_root="$HOME/.local/share/pstack-cursor/pstack/skills"
  local source_skill plugin_skill global_skill
  local skill_name
  local removed=0

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
        removed=$((removed + 1))
      fi
    elif [ -f "$global_skill/SKILL.md" ] && cmp -s "$global_skill/SKILL.md" "$source_skill/SKILL.md"; then
      if rm "$plugin_skill"; then
        removed=$((removed + 1))
      fi
    fi
  done

  [ "$removed" -eq 0 ] || echo "[-] Using shared user-level pstack skills in Cursor ($removed duplicates removed)"
}

install_shared_global_skills() {
  local source_root="$1"
  local collection="$2"
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
    echo "[!] $collection skills source missing; skipping other clients"
    return 0
  fi

  while IFS= read -r -d '' source_skill; do
    source_skill="${source_skill%/SKILL.md}"
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
        echo "[!] Could not link $collection skill: $destination"
        failed=$((failed + 1))
      fi
    done
  done < <(find "$source_root" -name SKILL.md -type f -print0)
  echo "[+] $collection skills installed: $installed linked, $preserved existing paths preserved, $failed failed"
}

install_shared_global_skills "$HOME/.local/share/pstack-cursor/pstack/skills" pstack
remove_duplicate_cursor_pstack_skills

install_engineering_skills() {
  local repo checkout name
  for repo in addyosmani/agent-skills mattpocock/skills; do
    name="${repo//\//-}"
    checkout="$HOME/.local/share/$name"
    if [ ! -d "$checkout/.git" ]; then
      if ! git clone --depth 1 "https://github.com/$repo.git" "$checkout"; then
        echo "[!] Could not install $repo skills"
        continue
      fi
    elif [ -n "$(git -C "$checkout" status --porcelain)" ]; then
      echo "[!] $repo checkout has local changes; preserving it without updating"
    elif ! git -C "$checkout" pull --ff-only --quiet; then
      echo "[!] Could not update $repo; keeping its current skills"
    fi
    install_shared_global_skills "$checkout/skills" "$repo"
  done
}

install_engineering_skills

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
link_skill_path() {
  local src="$1"
  local dest="$2"

  if [ -d "$dest" ] && [ ! -L "$dest" ]; then
    echo "[-] Existing skill directory preserved: $dest"
    return 0
  fi
  link "$src" "$dest"
}

link_skill() {
  local src="$1"
  local name="$2"
  [ -d "$src" ] || return 0
  link_skill_path "$src" "$HOME/.agents/skills/$name"
  # Codex discovers make-verifiable through the shared agents root.
  [ "$name" = make-verifiable ] || link_skill_path "$src" "$HOME/.codex/skills/$name"
  link_skill_path "$src" "$HOME/.gemini/config/skills/$name"
  link_skill_path "$src" "$HOME/.gemini/antigravity/skills/$name"
  link_skill_path "$src" "$HOME/.gemini/antigravity-cli/skills/$name"
  link_skill_path "$src" "$HOME/.gemini/skills/$name"
}

for command in grammar leetcode handoff; do
  link "$DOTFILES/ai/commands/${command}.md" "$HOME/.cursor/commands/${command}.md"
  link "$DOTFILES/ai/commands/${command}.md" "$HOME/.claude/commands/${command}.md"
  link "$DOTFILES/ai/commands/${command}.md" "$HOME/.zai/commands/${command}.md"
  link "$DOTFILES/ai/gemini/${command}.toml" "$HOME/.gemini/commands/${command}.toml"
  link_skill "$DOTFILES/ai/codex/${command}" "$command"
done

link_skill "$DOTFILES/ai/codex/make-verifiable" make-verifiable
link_skill_path "$DOTFILES/ai/codex/make-verifiable" "$HOME/.claude/skills/make-verifiable"

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
