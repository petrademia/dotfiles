#!/bin/bash
# Runs the uv tools step of setup/macos.sh against a stub `uv` and checks that every declared tool is
# installed, and that the MLX tools are pinned to a Python they have wheels for.
set -euo pipefail
repo=${1:-$(cd "$(dirname "$0")/.." && pwd)}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

mkdir -p "$work/bin"
cat > "$work/bin/uv" <<'STUB'
#!/bin/sh
case "$1 $2" in
  "tool list") cat "$STUB_LIST" ;;
  "tool install")
    echo "install $*" >> "$STUB_LOG"
    shift 2
    tool=$2; [ "$1" = "--upgrade" ] && tool=$2
    printf '%s 1.0\n' "$tool" >> "$STUB_LIST"
    ;;
  *) exit 99 ;;
esac
STUB
chmod +x "$work/bin/uv"

{
  echo 'set -e -o pipefail'
  echo 'record_result() { echo "result:$1"; }'
  echo 'record_version_result() { echo "version:$1:$2"; }'
  sed -n '/^echo "==> Updating uv tools"/,/^# Go tools with no Homebrew formula/p' "$repo/setup/macos.sh"
} > "$work/step.zsh"
grep -q 'uv_tool_python' "$work/step.zsh" || fail "could not extract the uv tools step"

export STUB_LIST="$work/list" STUB_LOG="$work/log"
: > "$STUB_LIST"; : > "$STUB_LOG"
PATH="$work/bin:$PATH" zsh "$work/step.zsh" > "$work/out" 2>&1 || { cat "$work/out"; fail "step exited non-zero on a fresh machine"; }

for tool in graphifyy mlx-lm mlx-optiq; do
  grep -q "install tool install --upgrade $tool " "$STUB_LOG" || grep -q "install .*$tool" "$STUB_LOG" || fail "$tool was not installed"
done
grep -E 'mlx-(lm|optiq)' "$STUB_LOG" | grep -vq -- '--python 3.12' && fail "an MLX tool is not pinned to Python 3.12"
grep -E 'graphifyy' "$STUB_LOG" | grep -q -- '--python 3$' || fail "graphifyy lost its --python 3"
echo 'uv tools checks passed.'
