#!/bin/bash
# Checks shell/.zshenv from a clean environment: the rustup directory must be on PATH for plain and
# login shells (which never read .zshrc), the file must stay silent, and PATH must not hold duplicates.
set -euo pipefail
repo=${1:-$(cd "$(dirname "$0")/.." && pwd)}
fail() { echo "FAIL: $*" >&2; exit 1; }

rustup_bin=/opt/homebrew/opt/rustup/bin
# ZDOTDIR points zsh at the repo copy, so the test does not depend on what is linked into $HOME.
clean=(env -i "HOME=$HOME" "ZDOTDIR=$repo/shell" "PATH=/usr/bin:/bin:/usr/sbin:/sbin")

grep -q 'shell/.zshenv' "$repo/install.sh" || fail "install.sh does not link shell/.zshenv"

out=$("${clean[@]}" zsh -c ':' 2>&1)
[ -z "$out" ] || fail ".zshenv printed output: $out"

# the system directories must still be there
"${clean[@]}" zsh -c 'print -r -- $PATH' | tr ':' '\n' | grep -qx /usr/bin || fail "PATH lost /usr/bin"

if [ -d "$rustup_bin" ]; then
  for mode in -c -lc; do
    "${clean[@]}" zsh "$mode" 'print -r -- $PATH' | tr ':' '\n' | grep -qxF "$rustup_bin" \
      || fail "zsh $mode does not have $rustup_bin on PATH"
  done
  count=$(env -i "HOME=$HOME" "ZDOTDIR=$repo/shell" "PATH=$rustup_bin:/usr/bin:$rustup_bin:/bin" \
    zsh -c 'print -r -- $PATH' | tr ':' '\n' | grep -cxF "$rustup_bin")
  [ "$count" = 1 ] || fail "PATH holds $count copies of $rustup_bin"
else
  echo "[-] $rustup_bin not present; skipped the PATH checks"
fi

echo 'Zshenv checks passed.'
