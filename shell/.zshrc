
# The next line updates PATH for the Google Cloud SDK.
if [ -f '/Users/Apple/Downloads/google-cloud-sdk/path.zsh.inc' ]; then . '/Users/Apple/Downloads/google-cloud-sdk/path.zsh.inc'; fi

# The next line enables shell command completion for gcloud.
if [ -f '/Users/Apple/Downloads/google-cloud-sdk/completion.zsh.inc' ]; then . '/Users/Apple/Downloads/google-cloud-sdk/completion.zsh.inc'; fi

eval "$(/Users/Apple/.local/bin/mise activate zsh)" # added by https://mise.run/zsh


# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$('/opt/anaconda3/bin/conda' 'shell.zsh' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "/opt/anaconda3/etc/profile.d/conda.sh" ]; then
        . "/opt/anaconda3/etc/profile.d/conda.sh"
    else
        export PATH="/opt/anaconda3/bin:$PATH"
    fi
fi
unset __conda_setup
# <<< conda initialize <<<


[[ "$TERM_PROGRAM" == "kiro" ]] && . "$(kiro --locate-shell-integration-path zsh)"

# Added by LM Studio CLI (lms)
export PATH="$PATH:/Users/Apple/.lmstudio/bin"
# End of LM Studio CLI section


export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# Added by Antigravity
export PATH="/Users/Apple/.antigravity/antigravity/bin:$PATH"
export ANDROID_HOME=$HOME/Library/Android/sdk
export PATH=$PATH:$ANDROID_HOME/emulator
export PATH=$PATH:$ANDROID_HOME/platform-tools

# Podman compatibility aliases for Docker-oriented workflows.
if command -v podman >/dev/null 2>&1; then
  alias docker='podman'
  alias docker-compose='podman compose'
fi


# opencode
export PATH=/Users/Apple/.opencode/bin:$PATH
export GOROOT=/usr/local/go
export PATH=$GOROOT/bin:$PATH

# Added by codebase-memory-mcp install
export PATH="/Users/Apple/.local/bin:$PATH"

# Claude Code aliases
alias cc='claude'
alias ccr='claude --resume'

# Added by Antigravity IDE
export PATH="/Users/Apple/.antigravity-ide/antigravity-ide/bin:$PATH"
