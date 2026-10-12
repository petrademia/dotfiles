#!/bin/bash
# Checks the package lists in setup/macos.sh: every tap-qualified package has a matching `brew tap`
# line, and no formula or cask is listed twice.
set -euo pipefail
repo=${1:-$(cd "$(dirname "$0")/.." && pwd)}
script="$repo/setup/macos.sh"
fail() { echo "FAIL: $*" >&2; exit 1; }

# Prints the words of the named bash array, one per line.
array_items() {
  awk -v name="$1" '
    $0 ~ "^" name "=\\($" { inside = 1; next }
    inside && /^\)/ { exit }
    inside { sub(/#.*/, ""); n = split($0, w, " "); for (i = 1; i <= n; i++) print w[i] }
  ' "$script"
}

taps=$(grep -E '^brew tap ' "$script" | awk '{ print $3 }')
for list in FORMULAS CASKS; do
  items=$(array_items "$list")
  [ -n "$items" ] || fail "could not read the $list array"
  dup=$(printf '%s\n' "$items" | sort | uniq -d)
  [ -z "$dup" ] || fail "$list lists a package twice: $dup"
  while IFS= read -r item; do
    case "$item" in
      */*/*)
        tap=${item%/*}
        printf '%s\n' "$taps" | grep -qxF "$tap" || fail "$item has no 'brew tap $tap' line"
        ;;
    esac
  done <<< "$items"
done

printf 'Package list checks passed.\n'
