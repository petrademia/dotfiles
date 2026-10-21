#!/bin/bash
# With PowerShell (pwsh) installed: parses every tracked .ps1 file (syntax only, nothing executes) and
# runs the new Windows setup logic against stubs. Skips when pwsh is not installed.
set -euo pipefail
repo=${1:-$(cd "$(dirname "$0")/.." && pwd)}
command -v pwsh >/dev/null 2>&1 || { echo "[-] pwsh not installed; skipped"; exit 0; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

# the parser must report an error for a broken file, or a clean result means nothing
printf 'function Broken {\n    if ($true) {\n' > "$work/known-bad.ps1"
if pwsh -NoProfile -NonInteractive -File "$repo/tests/powershell/parse.ps1" "$work/known-bad.ps1" >/dev/null 2>&1; then
  fail "the parser accepted a file with a missing brace"
fi

files=()
while IFS= read -r f; do files+=("$repo/$f"); done < <(git -C "$repo" ls-files '*.ps1')
[ ${#files[@]} -gt 0 ] || fail "no .ps1 files found"
pwsh -NoProfile -NonInteractive -File "$repo/tests/powershell/parse.ps1" "${files[@]}" || fail "a PowerShell file does not parse"

pwsh -NoProfile -NonInteractive -File "$repo/tests/powershell/logic.ps1" "$repo/setup/windows.ps1" "$work" \
  | sed 's/\x1b\[[0-9;]*m//g' > "$work/logic.out" || { cat "$work/logic.out" >&2; fail "the Windows logic checks failed"; }
grep -q 'FAIL' "$work/logic.out" && { cat "$work/logic.out" >&2; fail "a Windows logic check failed"; }

echo 'PowerShell checks passed.'
