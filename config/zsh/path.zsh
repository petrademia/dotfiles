eval "$(/opt/homebrew/bin/brew shellenv)"
eval "$(fnm env --use-on-cd)"
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"
[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ] && . "$HOME/.sdkman/bin/sdkman-init.sh"

# Brew rustup is keg-only
export PATH="/opt/homebrew/opt/rustup/bin:$PATH"

export PATH="$HOME/.local/bin:$PATH"
