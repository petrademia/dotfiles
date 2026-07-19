for f in ~/.config/zsh/*.zsh; do
  [ -r "$f" ] && . "$f"
done

# Hermes Agent — ensure ~/.local/bin is on PATH
export PATH="$HOME/.local/bin:$PATH"
