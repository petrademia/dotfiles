# Read by every zsh, including non-interactive and login shells that never load .zshrc, so keep it
# silent and fast.

# rustup is keg-only under Homebrew, so its rustc and cargo proxies are not on the default PATH.
# .zshrc (via config/zsh/path.zsh) adds this for interactive shells; this covers the rest, such as
# scripts and tools that start a login shell.
[[ -d /opt/homebrew/opt/rustup/bin ]] && path=(/opt/homebrew/opt/rustup/bin $path)
typeset -U path PATH
