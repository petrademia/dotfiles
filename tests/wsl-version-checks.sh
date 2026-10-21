#!/bin/bash
# Runs the version-aware blocks of setup/wsl.sh against stubs: npm globals (two-call snapshot with a
# per-package fallback), apt-repo tools (upgrade when newer, plain skip when not apt-managed) and Rust.
set -euo pipefail
repo=${1:-$(cd "$(dirname "$0")/.." && pwd)}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "[-] jq not installed; skipped"; exit 0; }
wsl="$repo/setup/wsl.sh"
expect() { [ "$1" = "$2" ] || fail "$3: expected '$2', got '$1'"; }

mkdir -p "$work/bin" "$work/home/.cargo/bin"
export STUB_LOG="$work/calls.log" STUB_DIR="$work"

# ---------------------------------------------------------------- npm
cat > "$work/bin/npm" <<'STUB'
#!/bin/sh
echo "$*" >> "$STUB_LOG"
case "$*" in
  "ls --global --depth=0 --json") printf '%s\n' "$STUB_LS" ;;
  "outdated --global --json") printf '%s\n' "$STUB_OUTDATED"; case "$STUB_OUTDATED" in ''|'{}') exit 0 ;; *) exit 1 ;; esac ;;
  install*) exit 0 ;;
  *) exit 99 ;;
esac
STUB
chmod +x "$work/bin/npm"
printf '#!/bin/sh\nexit 0\n' > "$work/bin/alphacmd"; chmod +x "$work/bin/alphacmd"

{
  echo 'record_result() { echo "result:$1"; }'
  sed -n '/^# npm global state\./,/^run_npm_global @earendil-works/p' "$wsl" | sed '$d'
  echo 'run_npm_global "$@"'
} > "$work/npm.bash"
grep -q 'npm_global_state()' "$work/npm.bash" || fail "could not extract the npm step"

# npm <package> <cmd>: prints the result lines, one per line joined with |
npm_case() { : > "$STUB_LOG"; PATH="$work/bin:$PATH" bash "$work/npm.bash" "$@" 2>&1 | grep -E '^result:|Updating|Skipping' | tr '\n' '|'; }
LS='{"dependencies":{"alpha":{"version":"1"},"beta":{"version":"1"},"@s/gamma":{"version":"1"}}}'

out=$(STUB_LS="$LS" STUB_OUTDATED='{"beta":{"current":"1","latest":"2"}}' npm_case alpha alphacmd)
expect "$out" 'result:skipped|[-] alpha is current. Skipping...|' "npm current"
out=$(STUB_LS="$LS" STUB_OUTDATED='{"beta":{"current":"1","latest":"2"}}' npm_case beta betacmd)
expect "$out" '==> Updating npm package: beta|result:updated|' "npm outdated"
grep -q '^install -g beta' "$STUB_LOG" || fail "an outdated package was not reinstalled"
out=$(STUB_LS="$LS" STUB_OUTDATED='{}' npm_case delta deltacmd)
expect "$out" 'result:installed|' "npm missing"
out=$(STUB_LS="$LS" STUB_OUTDATED='{}' npm_case @s/gamma gammacmd)
expect "$out" 'result:skipped|[-] @s/gamma is current. Skipping...|' "npm scoped package"
out=$(STUB_LS="$LS" STUB_OUTDATED='{}' npm_case alpha@latest alphacmd)
expect "$out" 'result:skipped|[-] alpha is current. Skipping...|' "npm @latest name"
[ "$(grep -c -E '^(ls|outdated) --global' "$STUB_LOG")" = 2 ] || fail "the snapshot must take exactly two npm calls"

# unusable snapshot: fall back to "the command is already on PATH"
for bad in 'not json' ''; do
  out=$(STUB_LS="$bad" STUB_OUTDATED='{}' npm_case alpha alphacmd)
  expect "$out" 'result:skipped|[-] alpha is current. Skipping...|' "fallback with the command present ($bad)"
  out=$(STUB_LS="$bad" STUB_OUTDATED='{}' npm_case alpha nosuchcmd)
  expect "$out" 'result:installed|' "fallback with the command absent ($bad)"
done
out=$(STUB_LS="$LS" STUB_OUTDATED='{"error":{"code":"ENOTFOUND"}}' npm_case beta nosuchcmd)
expect "$out" 'result:installed|' "fallback when npm outdated reports an error"

# ---------------------------------------------------------------- apt
cat > "$work/bin/dpkg-query" <<'STUB'
#!/bin/sh
f="$STUB_DIR/pkg-$3"; [ -f "$f" ] || exit 1; cat "$f"
STUB
cat > "$work/bin/sudo" <<'STUB'
#!/bin/sh
exec "$@"
STUB
cat > "$work/bin/apt" <<'STUB'
#!/bin/sh
echo "apt $*" >> "$STUB_LOG"
[ -z "${STUB_APT_FAIL:-}" ] || exit 100
[ -z "${STUB_UPGRADE_TO:-}" ] || printf '%s' "$STUB_UPGRADE_TO" > "$STUB_DIR/pkg-$4"
STUB
chmod +x "$work/bin/dpkg-query" "$work/bin/sudo" "$work/bin/apt"
{
  echo 'record_result() { echo "result:$1"; }'
  sed -n '/^apt_upgrade_present() {/,/^}/p' "$wsl"
  echo 'apt_upgrade_present "$1"; echo "rc:$?"'
} > "$work/apt.bash"
apt_case() { : > "$STUB_LOG"; PATH="$work/bin:$PATH" bash "$work/apt.bash" "$@" 2>&1 | tr '\n' '|'; }

rm -f "$work"/pkg-*
out=$(apt_case gh)
expect "$out" 'rc:1|' "a package that is not apt-managed keeps the plain skip"
printf '1.0' > "$work/pkg-gh"
out=$(apt_case gh)
expect "$out" 'result:skipped|[-] gh is current (1.0). Skipping...|rc:0|' "apt package already current"
grep -q '^apt install -y --only-upgrade gh' "$STUB_LOG" || fail "apt was not asked to upgrade"
out=$(STUB_UPGRADE_TO='2.0' apt_case gh)
expect "$out" 'result:updated|[+] Updated gh: 1.0 -> 2.0|rc:0|' "apt package upgraded"
printf '1.0' > "$work/pkg-gh"
out=$(STUB_APT_FAIL=1 apt_case gh)
case "$out" in *'result:failed'*'rc:0|') ;; *) fail "a failed apt upgrade was not counted as failed: $out" ;; esac

# every apt-repo tool uses the helper
for pair in 'gh gh' 'ngrok ngrok' 'gcloud google-cloud-cli' 'crush crush'; do
  set -- $pair
  grep -q "apt_upgrade_present $2 ||" "$wsl" || fail "$1 does not use apt_upgrade_present"
done

# ---------------------------------------------------------------- rust
cat > "$work/bin/rustc" <<'STUB'
#!/bin/sh
echo "rustc $(cat "$STUB_DIR/rust-version")"
STUB
cat > "$work/home/.cargo/bin/rustup" <<'STUB'
#!/bin/sh
echo "rustup $*" >> "$STUB_LOG"
[ -z "${STUB_RUSTUP_FAIL:-}" ] || exit 1
[ "$1 $2" = "update stable" ] && [ -n "${STUB_RUST_TO:-}" ] && printf '%s' "$STUB_RUST_TO" > "$STUB_DIR/rust-version"
exit 0
STUB
chmod +x "$work/bin/rustc" "$work/home/.cargo/bin/rustup"
{
  echo 'record_result() { echo "result:$1"; }'
  echo "HOME='$work/home'"
  sed -n '/^if \[ -x "\$HOME\/.cargo\/bin\/rustup" \]/,/^fi$/p' "$wsl"
} > "$work/rust.bash"
grep -q 'rustup update stable' "$work/rust.bash" || fail "could not extract the Rust step"
rust_case() { : > "$STUB_LOG"; PATH="$work/bin:$work/home/.cargo/bin:$PATH" bash "$work/rust.bash" 2>&1 | tr '\n' '|'; }

printf '1.99.1' > "$work/rust-version"
out=$(rust_case)
expect "$out" 'result:skipped|[-] Rust stable is current (rustc 1.99.1). Skipping...|' "Rust unchanged"
grep -q '^rustup update stable' "$STUB_LOG" || fail "rustup update stable was not run"
out=$(STUB_RUST_TO='1.99.2' rust_case)
expect "$out" 'result:updated|[+] Rust updated: rustc 1.99.1 -> rustc 1.99.2|' "Rust updated"
printf '1.99.1' > "$work/rust-version"
out=$(STUB_RUSTUP_FAIL=1 rust_case)
case "$out" in *'result:failed'*) ;; *) fail "a failing rustup update was not counted as failed: $out" ;; esac

echo 'WSL version checks passed.'
