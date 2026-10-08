#!/bin/bash
set -euo pipefail
repo=${1:-$(cd "$(dirname "$0")/.." && pwd)}
test_home=$(mktemp -d)
trap 'rm -rf "$test_home"' EXIT
DOTFILES="$repo"
eval "$(sed -n '/^link() {/,/^}/p; /^setup_codex_work() {/,/^}/p' "$repo/install.sh" | sed 's/\$HOME/\$test_home/g')"
mkdir -p "$test_home/.codex/skills"
printf 'personal sentinel\n' > "$test_home/.codex/auth.json"
setup_codex_work >/dev/null
test "$(readlink "$test_home/.codex-work/skills")" = "$test_home/.codex/skills"
test "$(readlink "$test_home/.codex-work/AGENTS.md")" = "$DOTFILES/global/AGENTS.md"
test ! -e "$test_home/.codex-work/auth.json"
test ! -e "$test_home/.codex-work/config.toml"
test ! -e "$test_home/.codex-work/sessions"
test -z "$(setup_codex_work)"
cmp "$test_home/.codex/auth.json" <(printf 'personal sentinel\n')
python3 - "$test_home/.codex-work" <<'PY'
import stat,sys
from pathlib import Path
assert stat.S_IMODE(Path(sys.argv[1]).stat().st_mode) == 0o700
PY
printf 'Codex work profile isolation and rerun checks passed.\n'
