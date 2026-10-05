#!/bin/bash
set -euo pipefail

repo=$(cd "$(dirname "$0")/.." && pwd)
test_home=$(mktemp -d)
trap 'rm -rf "$test_home"' EXIT

# Exercise the installer helpers without running package installs or changing home.
eval "$(sed -n '/^link() {/,/^}/p; /^link_skill_path() {/,/^}/p; /^link_skill() {/,/^}/p' "$repo/install.sh" | sed 's/\$HOME/\$test_home/g')"
mkdir -p "$test_home/source/make-verifiable" "$test_home/source/grammar"
for pass in 1 2; do
  link_skill "$test_home/source/make-verifiable" make-verifiable
  link_skill "$test_home/source/grammar" grammar
  test -L "$test_home/.agents/skills/make-verifiable"
  test ! -e "$test_home/.codex/skills/make-verifiable"
  test -L "$test_home/.codex/skills/grammar"
  test -L "$test_home/.gemini/config/skills/make-verifiable"
done
printf 'Skill installation checks passed.\n'
