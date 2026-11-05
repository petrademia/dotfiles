#!/bin/bash
# Loads config/nvim in a headless Neovim with stub language servers and checks that each server is
# enabled only when its binary exists, and that jdtls is started with a per-project workspace.
set -euo pipefail
repo=${1:-$(cd "$(dirname "$0")/.." && pwd)}
command -v nvim >/dev/null || { echo "nvim not installed; skipped"; exit 0; }
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir -p "$work/cfg" "$work/bin" "$work/a" "$work/b"
ln -s "$repo/config/nvim" "$work/cfg/nvim"
for s in gopls clangd; do printf '#!/bin/sh\nsleep 2\n' > "$work/bin/$s"; done
printf '#!/bin/sh\necho "$@" >> "%s/jdtls-args"\nsleep 2\n' "$work" > "$work/bin/jdtls"
chmod +x "$work/bin/"*
touch "$work/a/pom.xml" "$work/a/A.java" "$work/b/pom.xml" "$work/b/B.java"

nvim_bin=$(command -v nvim)
nv() {
  XDG_CONFIG_HOME=$work/cfg XDG_CACHE_HOME=$work/cache XDG_STATE_HOME=$work/state XDG_DATA_HOME=$work/data \
    PATH="$PATH_FOR_NVIM" "$nvim_bin" --headless "$@" 2>&1
}
enabled='lua print(tostring(vim.lsp.is_enabled("gopls")), tostring(vim.lsp.is_enabled("clangd")), tostring(vim.lsp.is_enabled("jdtls")))'

PATH_FOR_NVIM="$work/bin:/usr/bin:/bin"
got=$(nv -c "$enabled" -c 'qa!' </dev/null | tail -1 | tr -d '\r')
[ "$got" = "true true true" ] || fail "with all servers on PATH expected 'true true true', got '$got'"

rm -f "$work/bin/gopls"
PATH_FOR_NVIM="$work/bin:/usr/bin:/bin"
got=$(nv -c "$enabled" -c 'qa!' </dev/null | tail -1 | tr -d '\r')
[ "$got" = "false true true" ] || fail "without gopls expected 'false true true', got '$got'"

mkdir -p "$work/empty"
PATH_FOR_NVIM="$work/empty"
out=$(nv -c "$enabled" -c 'qa!' </dev/null)
[ "$(printf '%s' "$out" | tail -1 | tr -d '\r')" = "false false false" ] || fail "with no servers expected all disabled, got: $out"
printf '%s' "$out" | grep -qi 'error' && fail "startup printed an error with no servers installed: $out"

PATH_FOR_NVIM="$work/bin:/usr/bin:/bin"
for f in a/A.java b/B.java; do
  nv "$work/$f" -c 'lua vim.wait(5000, function() return #vim.lsp.get_clients({bufnr=0}) > 0 end, 100)' -c 'sleep 500m' -c 'qa!' </dev/null >/dev/null
done
[ "$(grep -c -- '-data' "$work/jdtls-args")" -ge 2 ] || fail "jdtls was not started with -data for both projects"
[ "$(awk '{print $2}' "$work/jdtls-args" | sort -u | wc -l | tr -d ' ')" = 2 ] || fail "two projects must get two different jdtls workspaces"
echo 'Neovim LSP checks passed.'
