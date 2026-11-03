#!/bin/bash
# Runs the Finder view-memory reset from bootstrap/macos.sh against a fake HOME: it must delete .DS_Store
# in visible folders and leave hidden, Library and node_modules trees alone (a full walk of $HOME looks
# like a hang on a real machine).
set -euo pipefail
repo=${1:-$(cd "$(dirname "$0")/.." && pwd)}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

home="$work/home"
for d in Desktop Documents/a/b Downloads Library/Caches .cache/x .local/share node_modules/pkg Pictures; do
  mkdir -p "$home/$d"; : > "$home/$d/.DS_Store"
done
: > "$home/.DS_Store"
mkdir -p "$home/.hidden" && : > "$home/.hidden/.DS_Store"

{
  echo "HOME=$home"
  sed -n '/^find "\$HOME" -maxdepth 4/,/|| true$/p' "$repo/bootstrap/macos.sh"
} > "$work/step.sh"
grep -q 'find' "$work/step.sh" || fail "could not extract the find step"
bash "$work/step.sh"

for gone in Desktop Documents/a/b Downloads Pictures .; do
  [ ! -e "$home/$gone/.DS_Store" ] || fail "$gone/.DS_Store was not removed"
done
for kept in Library/Caches .cache/x .local/share node_modules/pkg .hidden; do
  [ -e "$home/$kept/.DS_Store" ] || fail "$kept/.DS_Store should have been skipped"
done
echo 'Finder reset checks passed.'
