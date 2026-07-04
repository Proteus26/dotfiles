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

alias zshconfig="nvim ~/.zshrc"
alias docker-dev="docker compose --profile dev"
alias docker-prod="docker compose --profile prod"
alias yay="paru"
alias ssh='TERM="xterm-256color" kitty +kitten ssh'

alias ls='eza -a --icons'
alias ll='eza -lh --icons --git'
alias la='eza -lah --icons --git'
alias tree='eza --tree --icons'
compdef eza=ls
alias grep='rg --color=auto'
alias diff='diff --color=auto'
alias df='df -h'

eval "$(zoxide init zsh)"
source <(fzf --zsh)

# Added by Antigravity CLI installer
export PATH="/home/proteus/.local/bin:$PATH"

[ -f ~/.env ] && source ~/.env
