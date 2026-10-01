#!/usr/bin/env bash
set -euo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export BREW_TEST_DIR="$work"
export PATH="$work:$PATH"
cat >"$work/inventory.json" <<'EOF'
{"formulae":[
  {"name":"python@3.14","full_name":"python@3.14","aliases":["python"],"oldnames":[]},
  {"name":"crush","full_name":"charmbracelet/tap/crush","aliases":[],"oldnames":[]}
],"casks":[
  {"token":"postman","full_token":"postman","old_tokens":[]},
  {"token":"open-codesign","full_token":"opencoworkai/tap/open-codesign","old_tokens":["old-codesign"],"outdated":true}
]}
EOF
cat >"$work/outdated.json" <<'EOF'
{"formulae":[{"name":"charmbracelet/tap/crush"}],"casks":[{"name":"postman"}]}
EOF
cat >"$work/brew" <<'EOF'
#!/usr/bin/env bash
echo "$*" >>"$BREW_TEST_DIR/calls"
case "$*" in
  'info --installed --json=v2')
    [ "${BREW_TEST_FAILURE:-}" != inventory ] || exit 1
    cat "$BREW_TEST_DIR/inventory.json" ;;
  'outdated --json=v2')
    [ "${BREW_TEST_FAILURE:-}" != outdated ] || exit 1
    cat "$BREW_TEST_DIR/outdated.json" ;;
  'list --formula --versions python') exit 0 ;;
  'list --formula --versions charmbracelet/tap/crush') exit 1 ;;
  'list --formula --versions crush') exit 0 ;;
  'list --cask --versions postman') exit 0 ;;
  'outdated --formula --quiet python')
    [ "${BREW_TEST_FAILURE:-}" != individual ] || exit 1 ;;
  'outdated --formula --quiet charmbracelet/tap/crush'|'outdated --cask --quiet postman')
    echo outdated; exit 1 ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$work/brew"
sed -n '/^brew_package_state() {/,/^xcode-select /p' "$root/setup/macos.sh" | sed '$d' >"$work/check.zsh"
cat >>"$work/check.zsh" <<'EOF'
set -e -o pipefail
load_brew_snapshot
[ "$BREW_SNAPSHOT_READY" -eq 1 ]
[ "$(brew_package_state formula python)" = current ]
[ "$(brew_package_state formula charmbracelet/tap/crush)" = outdated ]
[ "$(brew_package_state cask postman)" = outdated ]
[ "$(brew_package_state cask opencoworkai/tap/open-codesign)" = current ]
[ "$(brew_package_state cask old-codesign)" = current ]
[ "$(brew_package_state formula missing)" = missing ]
[ "$(wc -l <"$BREW_TEST_DIR/calls" | tr -d ' ')" -eq 2 ]
for failure in inventory outdated; do
  export BREW_TEST_FAILURE=$failure
  load_brew_snapshot
  [ "$BREW_SNAPSHOT_READY" -eq 0 ]
  [ "$(brew_package_state formula python)" = current ]
  [ "$(brew_package_state formula charmbracelet/tap/crush)" = outdated ]
  [ "$(brew_package_state cask postman)" = outdated ]
  [ "$(brew_package_state formula missing)" = missing ]
done
export BREW_TEST_FAILURE=individual
[ "$(brew_package_state formula python)" = failed ]
unset BREW_TEST_FAILURE
# Refresh after package mutations so dependency changes are visible.
echo '{"formulae":[],"casks":[]}' >"$BREW_TEST_DIR/outdated.json"
load_brew_snapshot
[ "$(brew_package_state cask postman)" = current ]
echo 'Homebrew snapshot checks passed.'
EOF
zsh "$work/check.zsh"
