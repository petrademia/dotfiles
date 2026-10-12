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
_java_use_default() {
  [[ -d "$JAVA_JVM_DIR/temurin-25.jdk/Contents/Home" ]] && _java_set_home "$JAVA_JVM_DIR/temurin-25.jdk/Contents/Home"
}
_java_use_default

# Per-project JDK. The nearest .java-version (jenv format: "17" or "21-temurin") or the java line of
# a .tool-versions (asdf format: "java adoptopenjdk-17.0.12+7") picks the JDK when you cd into the
# project, and the default comes back when you leave it. A manual java-use sticks until you move to
# a different project.

# Prints the nearest pin file at or above $PWD.
_java_pin_file() {
  local dir="$PWD"
  while [[ -n "$dir" ]]; do
    [[ -f "$dir/.java-version" ]] && { print -r -- "$dir/.java-version"; return 0 }
    if [[ -f "$dir/.tool-versions" ]] && grep -q '^java[[:space:]]' "$dir/.tool-versions"; then
      print -r -- "$dir/.tool-versions"; return 0
    fi
    [[ "$dir" == "$HOME" || "$dir" == "/" ]] && break
    dir=${dir:h}
  done
  return 1
}

# Turns a pin ("17", "21-temurin", "adoptopenjdk-17.0.12+7", "1.8") into an installed
# "<version>-<vendor>". The requested vendor wins; otherwise or when it is missing, the first
# installed vendor with that major version, in the order temurin, zulu, corretto, liberica, microsoft.
_java_resolve() {
  local raw="${1:l}" major vendor v installed
  [[ "$raw" == 1.* ]] && raw=${raw#1.}
  [[ "$raw" =~ '[0-9]+' ]] || return 1
  major=$MATCH
  case "$raw" in
    *temurin*|*adoptopenjdk*|*adoptium*) vendor=temurin ;;
    *zulu*) vendor=zulu ;;
    *corretto*) vendor=corretto ;;
    *liberica*) vendor=liberica ;;
    *microsoft*) vendor=microsoft ;;
  esac
  installed=$(_java_installed | awk '{ print $1 }')
  for v in $vendor temurin zulu corretto liberica microsoft; do
    [[ -n "$v" ]] && print -rl -- ${(f)installed} | grep -qx "$major-$v" && { print -r -- "$major-$v"; return 0 }
  done
  return 1
}

_java_pin_apply() {
  local file request choice home
  file=$(_java_pin_file)
  [[ "$file" == "$_JAVA_PIN_FILE" ]] && return 0
  _JAVA_PIN_FILE="$file"
  if [[ -z "$file" ]]; then
    _java_use_default
    return 0
  fi
  case "${file:t}" in
    .java-version) request=$(head -n 1 "$file" | tr -d '[:space:]') ;;
    .tool-versions) request=$(awk '$1 == "java" { print $2; exit }' "$file") ;;
  esac
  if choice=$(_java_resolve "$request") && [[ -n "$choice" ]]; then
    home=$(_java_installed | awk -v w="$choice" '$1 == w { print $2 }')
    _java_set_home "$home"
    echo "java: using $choice (from ${file/#$HOME/~})" >&2
  else
    echo "java: no installed JDK matches '$request' in ${file/#$HOME/~}; keeping $JAVA_HOME" >&2
  fi
}

autoload -Uz add-zsh-hook
add-zsh-hook chpwd _java_pin_apply
_java_pin_apply
