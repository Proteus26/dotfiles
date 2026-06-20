export ZSH="$HOME/.oh-my-zsh"
export LANG="en_US.UTF-8"

ZSH_THEME="robbyrussell"

plugins=(
  git
  zsh-autosuggestions
  zsh-syntax-highlighting
  zoxide
  fzf
  fzf-tab
)

source $ZSH/oh-my-zsh.sh

export EDITOR='nvim'
export PATH="$HOME/.local/bin:$PATH"
export PATH="/usr/local/go/bin/:$PATH"
export PNPM_HOME="/home/proteus/.local/share/pnpm"
export PATH="$HOME/.npm-global/bin:$PATH"
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac

#Claude Code vars
export ANTHROPIC_BASE_URL="http://172.16.88.158:8000"
export ANTHROPIC_API_KEY="ollama"
export ANTHROPIC_MODEL="QuantTrio/Qwen3.6-35B-A3B-AWQ"
export API_TIMEOUT_MS=12000000
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1

alias zshconfig="nvim ~/.zshrc"
alias docker-dev="docker compose --profile dev"
alias docker-prod="docker compose --profile prod"
alias yay="paru"
alias ssh='TERM="xterm-256color" kitty +kitten ssh'

alias ls='eza --icons'
alias ll='eza -lh --icons --git'
alias la='eza -lah --icons --git'
alias tree='eza --tree --icons'
compdef eza=ls
alias cat='bat'
alias grep='rg --color=auto'
alias diff='diff --color=auto'
alias df='df -h'
alias find='fd'

eval "$(zoxide init zsh)"
source <(fzf --zsh)


# Added by Antigravity CLI installer
export PATH="/home/proteus/.local/bin:$PATH"
