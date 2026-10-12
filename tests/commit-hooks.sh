#!/bin/bash
# Makes real commits in a throwaway repo and checks that the hooks strip AI attribution but keep
# the rest of the message.
set -euo pipefail
repo=${1:-$(cd "$(dirname "$0")/.." && pwd)}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

cd "$work"
git init -q .
git config user.name test
git config user.email test@example.com
git config core.hooksPath "$repo/git/hooks"

echo a > a
git add a
git commit -q -F - <<'MSG'
feat: add a

Body line that must survive.

Co-authored-by: Claude <noreply@anthropic.com>
Co-authored-by: Cursor <cursoragent@cursor.com>
Made-with: Cursor
Generated with [Claude Code](https://claude.com/claude-code)
MSG
msg=$(git log -1 --format=%B)
case "$msg" in *'Body line that must survive.'*) ;; *) fail "commit body was lost: $msg" ;; esac
for pat in 'Claude' 'Cursor' 'Generated with' 'Co-authored-by'; do
  case "$msg" in *"$pat"*) fail "attribution '$pat' survived: $msg" ;; esac
done

echo b > b
git add b
git commit -q -m "fix: a plain message stays"
[ "$(git log -1 --format=%s)" = "fix: a plain message stays" ] || fail "plain message was altered"

# a human co-author is not AI attribution and must be kept
echo c > c
git add c
git commit -q -F - <<'MSG'
feat: pair work

Co-authored-by: Sam Person <sam@example.com>
MSG
git log -1 --format=%B | grep -q 'Sam Person' || fail "a human Co-authored-by trailer was stripped"

printf 'Commit hook checks passed.\n'
