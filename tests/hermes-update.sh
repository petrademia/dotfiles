#!/usr/bin/env bash
# Runs scripts/hermes-update.sh against a stub `hermes` and a throwaway git install directory.
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

# A clean install directory with an upstream, like a real Hermes checkout.
git init -q --bare "$work/remote.git"
git clone -q "$work/remote.git" "$work/install" 2>/dev/null
git -C "$work/install" config user.name test
git -C "$work/install" config user.email test@example.com
git -C "$work/install" checkout -q -b main
echo one > "$work/install/file"
git -C "$work/install" add file
git -C "$work/install" commit -q -m one
git -C "$work/install" push -q -u origin main 2>/dev/null

mkdir -p "$work/bin"
cat > "$work/bin/hermes" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "$HERMES_TEST_LOG"
case "$*" in
  --version)
    if [ -f "$HERMES_TEST_BUMPED" ]; then echo 'Hermes v2'; else echo 'Hermes v1'; fi
    echo "Install directory: $HERMES_TEST_DIR"
    ;;
  'update --check'*) printf '%s\n' "$HERMES_TEST_VERDICT"; exit "$HERMES_TEST_CHECK_EXIT" ;;
  'update --plan'*) echo 'plan: no running services' ;;
  'update --yes'*)
    [ -n "${HERMES_TEST_NO_BUMP:-}" ] || touch "$HERMES_TEST_BUMPED"
    exit "$HERMES_TEST_UPDATE_EXIT"
    ;;
  *) exit 99 ;;
esac
STUB
chmod +x "$work/bin/hermes"

export HERMES_TEST_LOG="$work/calls.log" HERMES_TEST_BUMPED="$work/bumped" HERMES_TEST_DIR="$work/install"

# run <verdict> <check-exit> <update-exit> <expected-rc> <update|skip> [label]
run() {
  export HERMES_TEST_VERDICT="$1" HERMES_TEST_CHECK_EXIT="$2" HERMES_TEST_UPDATE_EXIT="$3"
  rm -f "$HERMES_TEST_LOG" "$HERMES_TEST_BUMPED"
  local rc=0
  PATH="$work/bin:$PATH" bash "$root/scripts/hermes-update.sh" >/dev/null 2>&1 || rc=$?
  [ "$rc" = "$4" ] || fail "${6:-$1}: expected exit $4, got $rc"
  if [ "$5" = update ]; then
    grep -q '^update --yes ' "$HERMES_TEST_LOG" || fail "${6:-$1}: update was not run"
  else
    ! grep -q '^update --yes' "$HERMES_TEST_LOG" || fail "${6:-$1}: update ran but should not have"
  fi
}

run '✓ Already up to date.' 0 0 0 skip
run '✓ Up to date with the latest release (v1).' 0 0 0 skip
run '⚕ Update available: 1 commit behind origin/main.' 0 0 10 update
run '→ Selected release available: v2' 0 0 10 update
run '✗ Failed to fetch updates from origin.' 1 0 1 skip
run '⚕ Update available: 1 commit behind origin/main.' 0 1 1 update 'failing update'
run 'Unrecognized verdict' 0 0 10 update

# the update ran but the version did not change
HERMES_TEST_NO_BUMP=1 run '⚕ Update available.' 0 0 0 update 'unchanged version'

# flags: channel defaults to stable on check, plan and update; --yes is set; --backup is not forced
run '⚕ Update available.' 0 0 10 update
for f in 'update --check --channel stable' 'update --plan --channel stable' 'update --yes --channel stable'; do
  grep -qxF "$f" "$HERMES_TEST_LOG" || fail "missing call '$f'"
done
! grep -q -- '--backup' "$HERMES_TEST_LOG" || fail "--backup must not be forced"
HERMES_CHANNEL=main run '⚕ Update available.' 0 0 10 update 'channel override'
grep -qxF 'update --yes --channel main' "$HERMES_TEST_LOG" || fail "HERMES_CHANNEL was not passed to update"

# local changes in the install directory skip the update and leave it alone
echo dirty > "$work/install/untracked"
run '⚕ Update available.' 0 0 20 skip 'untracked file'
rm "$work/install/untracked"
echo two > "$work/install/file"
run '⚕ Update available.' 0 0 20 skip 'modified file'
git -C "$work/install" checkout -q -- file
echo two > "$work/install/file"
git -C "$work/install" commit -q -am two
run '⚕ Update available.' 0 0 20 skip 'unpushed commit'
git -C "$work/install" reset -q --hard origin/main
run '⚕ Update available.' 0 0 10 update 'clean again'

# The stable channel checks out a release on a detached HEAD, which has no upstream branch.
git -C "$work/install" checkout -q --detach
run '⚕ Update available.' 0 0 10 update 'detached at a commit already on a remote branch'
echo three > "$work/install/file"
git -C "$work/install" commit -q -am three
run '⚕ Update available.' 0 0 20 skip 'detached at an unpushed, untagged commit'
git -C "$work/install" tag v9.9.9
run '⚕ Update available.' 0 0 10 update 'detached at a tagged release'
git -C "$work/install" tag -d v9.9.9 >/dev/null
git -C "$work/install" checkout -q main
git -C "$work/install" reset -q --hard origin/main

# no hermes on PATH
rc=0
PATH="/usr/bin:/bin" bash "$root/scripts/hermes-update.sh" >/dev/null 2>&1 || rc=$?
[ "$rc" = 1 ] || fail "missing hermes should exit 1, got $rc"

# Both setup callers report preservation as skipped, rather than failed/current.
record_result() { result=$1; }
# shellcheck disable=SC2034  # read by the case block that eval pulls in from setup/*.sh
hermes_rc=20
for platform in macos wsl; do
  result=""
  eval "$(sed -n '/case "$hermes_rc" in/,/esac/p' "$root/setup/$platform.sh")"
  [ "$result" = skipped ] || fail "$platform classified preservation as $result"
done
echo 'Hermes update and setup classification checks passed.'
