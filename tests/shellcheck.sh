#!/bin/bash
# Runs shellcheck over every tracked bash/sh script. zsh scripts are skipped because shellcheck
# cannot parse zsh.
set -euo pipefail
repo=${1:-$(cd "$(dirname "$0")/.." && pwd)}
cd "$repo"
command -v shellcheck >/dev/null 2>&1 || { echo "shellcheck not found (brew install shellcheck)" >&2; exit 127; }

files=()
while IFS= read -r f; do
  [ -f "$f" ] || continue
  case "$(head -n 1 "$f")" in
    *zsh*) continue ;;
    '#!'*sh*) files+=("$f") ;;
  esac
done < <(git ls-files '*.sh' 'git/hooks/*' 'bin/*')

[ ${#files[@]} -gt 0 ] || { echo "no shell scripts found" >&2; exit 1; }
shellcheck -S warning "${files[@]}"
echo "Shellcheck passed on ${#files[@]} scripts."
