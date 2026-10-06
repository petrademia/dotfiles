#!/bin/bash
set -euo pipefail
repo=${1:-$(cd "$(dirname "$0")/.." && pwd)}
test_home=$(mktemp -d)
trap 'rm -rf "$test_home"' EXIT

eval "$(sed -n '/^link() {/,/^}/p; /^install_cursor_pstack() {/,/^}/p; /^remove_duplicate_cursor_pstack_skills() {/,/^}/p' "$repo/install.sh" | sed 's/\$HOME/\$test_home/g')"
# Keep the real installer flow, but use a local checkout without network access.
git() { return 0; }
checkout="$test_home/.local/share/pstack-cursor"
plugin="$test_home/.cursor/plugins/local/pstack"
mkdir -p "$checkout/.git" "$checkout/pstack/.cursor-plugin" "$checkout/pstack/skills/shared" "$checkout/pstack/skills/custom"
printf '{"name":"pstack","repository":"https://github.com/cursor/plugins"}\n' > "$checkout/pstack/.cursor-plugin/plugin.json"
printf 'shared\n' > "$checkout/pstack/skills/shared/SKILL.md"
printf 'custom\n' > "$checkout/pstack/skills/custom/SKILL.md"
printf 'original\n' > "$checkout/pstack/settings.json"
link "$checkout/pstack/skills/shared" "$test_home/.agents/skills/shared" >/dev/null
install_cursor_pstack >/dev/null
remove_duplicate_cursor_pstack_skills >/dev/null
test ! -e "$plugin/skills/shared/SKILL.md"
test -f "$plugin/skills/custom/SKILL.md"

# An unchanged rerun must leave the shared skill absent and report no sync.
output=$(install_cursor_pstack)
if [ -e "$plugin/skills/shared/SKILL.md" ]; then
  echo 'FAIL: unchanged setup recopied a removed shared skill' >&2
  exit 1
fi
case "$output" in *'synced'*|*'installed'*) echo 'FAIL: unchanged plugin was copied' >&2; exit 1 ;; esac
test -z "$(link "$checkout/pstack/skills/shared" "$test_home/.agents/skills/shared")"

# Real updates still copy changes, repair drift, and keep non-shared skills.
printf 'updated\n' > "$checkout/pstack/settings.json"
printf 'updated custom\n' > "$checkout/pstack/skills/custom/SKILL.md"
install_cursor_pstack >/dev/null
cmp "$checkout/pstack/settings.json" "$plugin/settings.json"
cmp "$checkout/pstack/skills/custom/SKILL.md" "$plugin/skills/custom/SKILL.md"
printf 'local drift\n' > "$plugin/settings.json"
install_cursor_pstack >/dev/null
cmp "$checkout/pstack/settings.json" "$plugin/settings.json"

# A link with the wrong target must still be repaired.
link "$checkout/pstack/skills/custom" "$test_home/.agents/skills/shared" >/dev/null
test "$(readlink "$test_home/.agents/skills/shared")" = "$checkout/pstack/skills/custom"
printf 'Installer idempotency checks passed.\n'
