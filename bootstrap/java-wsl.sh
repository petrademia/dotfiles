#!/usr/bin/env bash
# WSL Java matrix via SDKMAN - mirrors the macOS java-macos.sh vendor/version set.
set -uo pipefail

if [ ! -d "$HOME/.sdkman" ]; then
  export sdkman_auto_answer=true
  curl -s "https://get.sdkman.io?rcupdate=false" | bash
fi
set +u
[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ] && . "$HOME/.sdkman/bin/sdkman-init.sh"

MAJORS=(8 11 17 21 25)
VENDOR_NAMES=(temurin zulu corretto liberica microsoft)
declare -A SUFFIX=([temurin]=tem [zulu]=zulu [corretto]=amzn [liberica]=librca [microsoft]=ms)

AVAIL="$(sdk list java 2>/dev/null || true)"

resolve_id() {
  local major=$1 suffix=$2
  printf '%s\n' "$AVAIL" \
    | grep -oE "\b${major}\.[0-9.]+-${suffix}\b" \
    | sort -V | tail -1
}

for major in "${MAJORS[@]}"; do
  for name in "${VENDOR_NAMES[@]}"; do
    if [ "$name" = "microsoft" ] && [ "$major" = "8" ]; then
      continue
    fi
    id="$(resolve_id "$major" "${SUFFIX[$name]}")"
    if [ -z "$id" ]; then
      echo "[-] No SDKMAN build for Java $major $name"
      continue
    fi
    if [ -d "$HOME/.sdkman/candidates/java/$id" ]; then
      echo "[-] $id already installed"
      continue
    fi
    echo "==> Installing $id ($name $major)"
    yes n | sdk install java "$id" >/dev/null 2>&1 || echo "[!] failed: $id"
  done
done

DEFAULT_ID="$(resolve_id 21 tem)"
if [ -n "$DEFAULT_ID" ] && [ -d "$HOME/.sdkman/candidates/java/$DEFAULT_ID" ]; then
  sdk default java "$DEFAULT_ID" >/dev/null 2>&1 || true
  echo "Default JDK: $DEFAULT_ID"
fi

echo
echo "Installed JDKs (~/.sdkman/candidates/java):"
ls -1 "$HOME/.sdkman/candidates/java" 2>/dev/null | grep -v '^current$' || true
echo
echo "Switch with: java-use 21-temurin   (or: sdk use java <identifier>)"
