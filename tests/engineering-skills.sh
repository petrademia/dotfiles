#!/bin/bash
set -euo pipefail
repo=${1:-$(cd "$(dirname "$0")/.." && pwd)}
test_root=$(mktemp -d)
test_home="$test_root/home"
trap 'rm -rf "$test_root"' EXIT
mkdir -p "$test_home/.local/share" "$test_home/.agents/skills/tdd"
printf 'custom tdd\n' > "$test_home/.agents/skills/tdd/SKILL.md"
eval "$(sed -n '/^install_shared_global_skills() {/,/^}/p; /^install_engineering_skills() {/,/^}/p' "$repo/install.sh" | sed 's/\$HOME/\$test_home/g')"
for name in addyosmani-agent-skills mattpocock-skills; do
  upstream="$test_root/$name"
  command git init -q "$upstream"
  command git -C "$upstream" config user.name Test
  command git -C "$upstream" config user.email test@example.invalid
  mkdir -p "$upstream/skills/engineering/tdd" "$upstream/skills/review" "$upstream/references"
  printf 'upstream tdd\n' > "$upstream/skills/engineering/tdd/SKILL.md"
  printf 'review\n' > "$upstream/skills/review/SKILL.md"
  printf 'shared reference\n' > "$upstream/references/checklist.md"
  command git -C "$upstream" add .
  command git -C "$upstream" commit -qm initial
done
# Exercise the real clone/pull flow against local upstreams.
git() {
  if [ "$1" = clone ]; then
    local name=${4#https://github.com/}
    name=${name%.git}
    name=${name//\//-}
    if [ "${fail_clone:-}" = "$name" ]; then return 1; fi
    command git clone --quiet --depth 1 "file://$test_root/$name" "$5"
  else
    command git "$@"
  fi
}
install_engineering_skills >/dev/null
cmp "$test_home/.agents/skills/tdd/SKILL.md" <(printf 'custom tdd\n')
test -L "$test_home/.agents/skills/review"
test -L "$test_home/.claude/skills/tdd"
# References outside an individual skill remain reachable through the link.
cmp "$test_home/.agents/skills/review/../../references/checklist.md" "$test_root/addyosmani-agent-skills/references/checklist.md"
output=$(install_engineering_skills)
case "$output" in *'installed: '[1-9]*) echo 'FAIL: rerun created new links' >&2; exit 1 ;; esac
printf 'updated review\n' > "$test_root/addyosmani-agent-skills/skills/review/SKILL.md"
command git -C "$test_root/addyosmani-agent-skills" commit -qam updated
install_engineering_skills >/dev/null
cmp "$test_home/.agents/skills/review/SKILL.md" <(printf 'updated review\n')
printf 'local edit\n' > "$test_home/.local/share/addyosmani-agent-skills/skills/review/SKILL.md"
install_engineering_skills >/dev/null
cmp "$test_home/.agents/skills/review/SKILL.md" <(printf 'local edit\n')
test_home="$test_root/failure-home"
mkdir -p "$test_home/.local/share"
fail_clone=addyosmani-agent-skills
install_engineering_skills >/dev/null
test -L "$test_home/.agents/skills/review"
test "$(readlink "$test_home/.agents/skills/review")" = "$test_home/.local/share/mattpocock-skills/skills/review"
printf 'Engineering skills install, update, reference, preservation, and failure checks passed.\n'
