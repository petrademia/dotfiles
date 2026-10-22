#!/bin/bash
# Runs scripts/sync-bitbucket-repos.sh against a stub curl and git that serve three canned pages, newest
# first like the real API: repositories older than the cutoff are skipped and paging stops at the first
# page that contains one.
set -euo pipefail
repo=${1:-$(cd "$(dirname "$0")/.." && pwd)}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "[-] jq not installed; skipped"; exit 0; }

python3 - "$work" <<'PY'
import datetime as dt, json, sys
work = sys.argv[1]
now = dt.datetime.now(dt.timezone.utc)
def r(name, days):
    v = {"name": name, "project": {"name": "Alpha"},
         "links": {"clone": [{"name": "ssh", "href": f"git@bitbucket.org:amartha/{name}.git"}]}}
    if days is not None:
        v["updated_on"] = (now - dt.timedelta(days=days)).strftime("%Y-%m-%dT%H:%M:%S.000000+00:00")
    return v
pages = [
    [r("repo-a", 0), r("repo-b", 100), r("repo-nodate", None)],
    [r("repo-c", 300), r("repo-d", 400), r("repo-e", 500)],
    [r("repo-f", 900), r("repo-g", 1000)],
]
for i, values in enumerate(pages, 1):
    page = {"values": values}
    if i < len(pages):
        page["next"] = f"https://api.bitbucket.org/2.0/repositories/Amartha?sort=-updated_on&pagelen=100&page={i + 1}"
    json.dump(page, open(f"{work}/page{i}.json", "w"))
PY

mkdir -p "$work/bin"
cat > "$work/bin/curl" <<'STUB'
#!/bin/sh
cat > /dev/null
url=""; out=""
while [ $# -gt 0 ]; do
  case "$1" in -o) out=$2; shift ;; http*) url=$1 ;; esac
  shift
done
echo "$url" >> "$STUB_DIR/requests.log"
case "$url" in *page=3*) f=page3.json ;; *page=2*) f=page2.json ;; *) f=page1.json ;; esac
cp "$STUB_DIR/$f" "$out"
STUB
cat > "$work/bin/git" <<'STUB'
#!/bin/sh
[ "$1" = clone ] && { echo "$2" >> "$STUB_DIR/clones.log"; mkdir -p "$3"; }
exit 0
STUB
chmod +x "$work/bin/curl" "$work/bin/git"

# run <shell> [env assignments...]: runs the script in a fresh directory and prints the exit code
run() {
  local shell=$1; shift
  rm -rf "$work/run" "$work/requests.log" "$work/clones.log"
  mkdir "$work/run"; : > "$work/requests.log"; : > "$work/clones.log"
  ( cd "$work/run" && env "$@" STUB_DIR="$work" AUTH_CREDS="user:secret" PATH="$work/bin:$PATH" \
      "$shell" "$repo/scripts/sync-bitbucket-repos.sh" > "$work/output.txt" 2>&1 ) && return 0 || return $?
}
requests() { wc -l < "$work/requests.log" | tr -d ' '; }
cloned() { sed 's#.*/\(.*\)\.git#\1#' "$work/clones.log" | sort | tr '\n' ' '; }
expect() { [ "$1" = "$2" ] || fail "$3: expected '$2', got '$1'"; }

for shell in bash zsh; do
  command -v "$shell" >/dev/null 2>&1 || continue
  echo "-- $shell"
  # default 365 days: page 2 holds the first old repository, so page 3 is never requested
  run "$shell" SYNC_X=1
  expect "$(requests)" 2 "$shell default: pages requested"
  expect "$(cloned)" "repo-a repo-b repo-c repo-nodate " "$shell default: repositories cloned"
  grep -q 'stopping after page 2' "$work/output.txt" || fail "$shell default: no stop message"
  grep -q 'not updated since' "$work/output.txt" || fail "$shell default: the cutoff was not announced"

  # 0 turns the cutoff off: every page, every repository
  run "$shell" SYNC_MAX_AGE_DAYS=0
  expect "$(requests)" 3 "$shell 0: pages requested"
  expect "$(cloned)" "repo-a repo-b repo-c repo-d repo-e repo-f repo-g repo-nodate " "$shell 0: repositories cloned"

  # a short cutoff stops after the first page
  run "$shell" SYNC_MAX_AGE_DAYS=30
  expect "$(requests)" 1 "$shell 30: pages requested"
  expect "$(cloned)" "repo-a repo-nodate " "$shell 30: repositories cloned"

  # a cutoff between repo-d (400 days) and repo-e (500 days) keeps repo-d and still stops after page 2
  run "$shell" SYNC_MAX_AGE_DAYS=450
  expect "$(requests)" 2 "$shell 450: pages requested"
  expect "$(cloned)" "repo-a repo-b repo-c repo-d repo-nodate " "$shell 450: repositories cloned"
done

# an invalid value is rejected before any request
rc=0; run bash SYNC_MAX_AGE_DAYS=abc || rc=$?
[ "$rc" != 0 ] || fail "an invalid SYNC_MAX_AGE_DAYS was accepted"
expect "$(requests)" 0 "invalid value: requests made"
grep -q 'whole number' "$work/output.txt" || fail "no message for an invalid SYNC_MAX_AGE_DAYS"

echo 'Bitbucket sync checks passed.'
