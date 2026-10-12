for f in ~/.config/zsh/*.zsh; do
  [ -r "$f" ] && . "$f"
done

# Hermes Agent — ensure ~/.local/bin is on PATH
export PATH="$HOME/.local/bin:$PATH"

# Keep PATH free of duplicates (several of the files above prepend the same directories).
typeset -U path PATH
