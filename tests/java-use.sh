#!/bin/bash
# Checks config/zsh/java.zsh against a fake JVM directory: discovery, the default, switching without
# growing PATH, and refusing a JDK that is not installed.
set -euo pipefail
repo=${1:-$(cd "$(dirname "$0")/.." && pwd)}
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

jvm="$work/jvm"
for jdk in temurin-25 temurin-21 temurin-17 zulu-17 amazon-corretto-8 liberica-jdk-25 microsoft-11; do
  mkdir -p "$jvm/$jdk.jdk/Contents/Home/bin"
  printf '#!/bin/sh\necho "java from %s" >&2\n' "$jdk" > "$jvm/$jdk.jdk/Contents/Home/bin/java"
  chmod +x "$jvm/$jdk.jdk/Contents/Home/bin/java"
done
mkdir -p "$jvm/unknown-vendor-9.jdk/Contents/Home" "$jvm/broken-21.jdk"   # ignored: unknown vendor
run() { JAVA_JVM_DIR="$jvm" zsh -fc "source '$repo/config/zsh/java.zsh'; $1" 2>&1; }

# discovery: only installed JDKs, version-ordered, vendor names normalised
list=$(run '_java_installed | awk "{printf \"%s \", \$1}"')
[ "$list" = "8-corretto 11-microsoft 17-temurin 17-zulu 21-temurin 25-liberica 25-temurin " ] || fail "unexpected JDK list: $list"

# default is temurin 25 when installed
[ "$(run 'echo $JAVA_HOME')" = "$jvm/temurin-25.jdk/Contents/Home" ] || fail "default JAVA_HOME is not temurin-25"

# no default exported when temurin 25 is missing
out=$(JAVA_JVM_DIR="$work/empty" zsh -fc "unset JAVA_HOME; source '$repo/config/zsh/java.zsh'; echo \"[\${JAVA_HOME:-unset}]\"" 2>&1)
[ "$out" = "[unset]" ] || fail "JAVA_HOME was set without an installed default: $out"

# switching changes JAVA_HOME and the java on PATH
out=$(run 'java-use 17-zulu; echo $JAVA_HOME; command -v java')
case "$out" in *"java from zulu-17"*"$jvm/zulu-17.jdk/Contents/Home/bin/java") ;; *) fail "java-use 17-zulu did not switch: $out" ;; esac

# repeated switches leave exactly one JDK entry on PATH
count=$(run 'for i in 1 2 3 4 5; do java-use 17-temurin >/dev/null 2>&1; java-use 25-temurin >/dev/null 2>&1; done; print -l $path | grep -c "'"$jvm"'/"')
[ "$count" = "1" ] || fail "PATH holds $count JDK entries after repeated switches"

# a JDK that is not installed is refused and JAVA_HOME is left alone
out=$(run 'java-use 11-temurin; echo "rc=$? home=$JAVA_HOME"')
case "$out" in *"Installed: "*"rc=1 home=$jvm/temurin-25.jdk/Contents/Home") ;; *) fail "missing JDK was not refused cleanly: $out" ;; esac
out=$(run 'java-use; echo "rc=$?"')
case "$out" in *"rc=1") ;; *) fail "java-use without an argument did not fail: $out" ;; esac

# the macOS installer no longer generates the file
grep -q 'cat > .*java.zsh' "$repo/bootstrap/java-macos.sh" && fail "java-macos.sh still generates java.zsh"

printf 'Java selection checks passed.\n'
