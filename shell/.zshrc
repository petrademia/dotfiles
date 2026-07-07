for f in ~/.config/zsh/*.zsh; do
  [ -r "$f" ] && . "$f"
done
