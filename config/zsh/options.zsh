# Interactive shell options.

# zsh only treats # as a comment when this is set, so a pasted snippet that has a comment
# with an apostrophe in it leaves the terminal waiting at a quote> prompt.
setopt interactive_comments

# History: long, shared between tabs, without noise. SHARE_HISTORY already appends as you go, so
# INC_APPEND_HISTORY is deliberately not set (zsh documents the two as redundant).
HISTFILE="${HISTFILE:-$HOME/.zsh_history}"
HISTSIZE=100000
SAVEHIST=100000
setopt hist_ignore_dups hist_ignore_space hist_reduce_blanks share_history
