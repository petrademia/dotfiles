# JDK selection. JDKs are discovered from the macOS JVM directory when the shell starts, so only
# installed ones are offered and nothing is exported for a JDK that is missing.
# bootstrap/java-macos.sh installs them; this file is static and not generated.

: "${JAVA_JVM_DIR:=/Library/Java/JavaVirtualMachines}"

# Prints "<version>-<vendor> <JAVA_HOME>" for each installed JDK, oldest version first.
_java_installed() {
  local dir name vendor version
  for dir in "$JAVA_JVM_DIR"/*.jdk(N); do
    name=${${dir:t}%.jdk}
    case "$name" in
      temurin-*)         vendor=temurin;   version=${name#temurin-} ;;
      zulu-*)            vendor=zulu;      version=${name#zulu-} ;;
      amazon-corretto-*) vendor=corretto;  version=${name#amazon-corretto-} ;;
      liberica-jdk-*)    vendor=liberica;  version=${name#liberica-jdk-} ;;
      microsoft-*)       vendor=microsoft; version=${name#microsoft-} ;;
      *) continue ;;
    esac
    [[ -d "$dir/Contents/Home" ]] && print -r -- "$version-$vendor $dir/Contents/Home"
  done | sort -t- -k1,1n -k2,2
}

# Points JAVA_HOME at $1 and puts its bin first on PATH, dropping the previous JAVA_HOME/bin so
# repeated switches do not grow PATH.
_java_set_home() {
  [[ -n "$JAVA_HOME" ]] && path=(${path:#"$JAVA_HOME/bin"})
  export JAVA_HOME="$1"
  path=("$JAVA_HOME/bin" $path)
}

java-use() {
  local want="$1" home
  [[ -n "$want" ]] && home=$(_java_installed | awk -v w="$want" '$1 == w { print $2 }')
  if [[ -z "$home" ]]; then
    echo "Usage: java-use <version-vendor>" >&2
    echo "Installed: $(_java_installed | awk '{ printf "%s ", $1 }')" >&2
    return 1
  fi
  _java_set_home "$home"
  java -version
}

# Default JDK, only when it is installed.
[[ -d "$JAVA_JVM_DIR/temurin-21.jdk/Contents/Home" ]] && _java_set_home "$JAVA_JVM_DIR/temurin-21.jdk/Contents/Home"
