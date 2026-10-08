alias cc='claude'
alias ccr='claude --resume'
alias cdc='cd ~/code'
alias gcp='g++-16 -std=c++17 -O2 -Wall'
alias neofetch='fastfetch'
alias wiztree='open -a GrandPerspective'
alias vim='nvim'
alias vi='nvim'

# === AI tool profiles (managed block) ===
# Default Cursor.app / `cursor` = personal (current login + data).
# Work = isolated data dir; first launch is a clean slate (sign in + extensions).
cursor-work() {
  mkdir -p "$HOME/.cursor-profiles/work/extensions"
  open -na Cursor --args \
    --user-data-dir="$HOME/.cursor-profiles/work" \
    --extensions-dir="$HOME/.cursor-profiles/work/extensions" \
    "$@"
}
# Claude Code keeps work credentials, settings, and transcripts in a separate profile.
claude-work() {
  CLAUDE_CONFIG_DIR="$HOME/.claude-work" command claude "$@"
}
# Codex CLI keeps work login, configuration, and sessions in a separate home.
codex-personal() {
  CODEX_HOME="$HOME/.codex" command codex "$@"
}
codex-work() {
  CODEX_HOME="$HOME/.codex-work" command codex "$@"
}
# Note: Cursor agent CLI (`agent`) cannot be split this way — login is in the
# macOS Keychain. Use `agent logout` / `agent login` (or CURSOR_API_KEY) to switch.
# === end ===
