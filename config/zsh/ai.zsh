# Loads AI provider keys from 1Password into the current shell. Reads run in parallel and nothing
# is exported unless every read succeeded.
get-keys() {
  command -v op >/dev/null 2>&1 || { echo "get-keys: op (1Password CLI) not found" >&2; return 1; }
  op whoami >/dev/null 2>&1 || { echo "get-keys: 1Password CLI is not signed in (unlock the desktop app)" >&2; return 1; }

  local -A items=(
    OPENROUTER_API_KEY OpenRouter
    ANTHROPIC_API_KEY Anthropic
    GEMINI_API_KEY Gemini
  )
  local dir var
  dir=$(mktemp -d) || return 1
  for var in ${(k)items}; do
    op read "op://Private/${items[$var]}/credential" >"$dir/$var" 2>/dev/null &
  done
  wait

  local failed=()
  for var in ${(k)items}; do
    [ -s "$dir/$var" ] || failed+=("${items[$var]}")
  done
  if [ ${#failed[@]} -gt 0 ]; then
    rm -rf "$dir"
    echo "get-keys: could not read: ${failed[*]}" >&2
    return 1
  fi
  for var in ${(k)items}; do
    export "$var=$(<"$dir/$var")"
  done
  rm -rf "$dir"
  echo "AI keys loaded."
}
