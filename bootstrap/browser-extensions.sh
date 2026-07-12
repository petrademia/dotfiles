#!/bin/bash
set -euo pipefail

# Browsers deliberately block silent extension installs. This helper opens the
# correct store page for each extension in the browsers you choose, so you just
# click "Add". It picks the right uBlock variant per engine:
#   - Chromium (Chrome/Edge/Vivaldi/Opera/...) : uBlock Origin Lite (MV3; full uBO is dead on Chrome)
#   - Brave                                     : full uBlock Origin (Brave keeps MV2) or built-in Shields
#   - Firefox family                            : full uBlock Origin
#
# Usage:
#   bootstrap/browser-extensions.sh                 # default set: Chrome, Brave, Firefox, Edge
#   bootstrap/browser-extensions.sh all             # every installed supported browser
#   bootstrap/browser-extensions.sh "Google Chrome" "Firefox"

# Chrome Web Store IDs (verified July 2026)
CWS_FDM="ahmpjcflkgiildlgicmcieglgoilbfdp"        # Free Download Manager integration
CWS_UBOL="ddkjiahejlhfcafbddmgiahcphecmpfh"       # uBlock Origin Lite (MV3)
CWS_UBO="cjpalhdlnbpafiamejdnhcphjbkeiagm"        # uBlock Origin (full, MV2 - Brave only)
CWS_1PW="aeblfdkhhhdcdjpifhhbdiojplfjncoa"        # 1Password X

cws() { echo "https://chromewebstore.google.com/detail/$1"; }

# Firefox AMO pages
AMO_UBO="https://addons.mozilla.org/firefox/addon/ublock-origin/"
AMO_1PW="https://addons.mozilla.org/firefox/addon/1password-x-password-manager/"
AMO_FDM="https://addons.mozilla.org/firefox/search/?q=Free%20Download%20Manager"

# Supported browsers: "App Name|engine"  (engine: chromium | brave | firefox)
BROWSERS=(
  "Google Chrome|chromium"
  "Google Chrome Beta|chromium"
  "Google Chrome Canary|chromium"
  "Microsoft Edge|chromium"
  "Vivaldi|chromium"
  "Opera|chromium"
  "Chromium|chromium"
  "Helium|chromium"
  "Brave Browser|brave"
  "Firefox|firefox"
  "Firefox Developer Edition|firefox"
  "Floorp|firefox"
  "Waterfox|firefox"
  "LibreWolf|firefox"
  "Mullvad Browser|firefox"
)

DEFAULTS=("Google Chrome" "Brave Browser" "Firefox" "Microsoft Edge")

is_installed() { [ -d "/Applications/$1.app" ]; }

open_for() {
  local app="$1" engine="$2"
  local urls=()
  case "$engine" in
    chromium)
      urls=("$(cws "$CWS_UBOL")" "$(cws "$CWS_1PW")" "$(cws "$CWS_FDM")")
      ;;
    brave)
      urls=("$(cws "$CWS_UBO")" "$(cws "$CWS_1PW")" "$(cws "$CWS_FDM")")
      ;;
    firefox)
      urls=("$AMO_UBO" "$AMO_1PW" "$AMO_FDM")
      ;;
  esac
  echo "==> $app: opening ${#urls[@]} extension pages (click Add on each)"
  open -a "$app" "${urls[@]}" 2>/dev/null || echo "    could not open $app"
}

engine_for() {
  local want="$1"
  for entry in "${BROWSERS[@]}"; do
    if [ "${entry%%|*}" = "$want" ]; then echo "${entry##*|}"; return 0; fi
  done
  return 1
}

# Resolve target list
targets=()
if [ "$#" -eq 0 ]; then
  targets=("${DEFAULTS[@]}")
elif [ "$1" = "all" ]; then
  for entry in "${BROWSERS[@]}"; do targets+=("${entry%%|*}"); done
else
  targets=("$@")
fi

opened=0
for app in "${targets[@]}"; do
  engine="$(engine_for "$app" || true)"
  if [ -z "${engine:-}" ]; then
    echo "-- skip '$app' (not a supported browser name)"
    continue
  fi
  if ! is_installed "$app"; then
    echo "-- skip '$app' (not installed)"
    continue
  fi
  open_for "$app" "$engine"
  opened=$((opened + 1))
done

echo
echo "Done. Opened pages in $opened browser(s)."
echo "Notes:"
echo "  - Chrome/Edge/Vivaldi/Opera use uBlock Origin Lite (full uBO no longer works on Chrome)."
echo "  - LibreWolf and Mullvad usually ship uBlock Origin preinstalled."
echo "  - 1Password and FDM extensions need their desktop apps installed to function."
