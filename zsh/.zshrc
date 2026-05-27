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
case ":$PATH:" in
  *":$PNPM_HOME:"*) ;;
  *) export PATH="$PNPM_HOME:$PATH" ;;
esac

alias zshconfig="nvim ~/.zshrc"
alias docker-dev="docker compose --profile dev"
alias docker-prod="docker compose --profile prod"
alias ll="ls -lah"
alias yay="paru"
alias ssh='TERM="xterm-256color" kitty +kitten ssh'

eval "$(zoxide init zsh)"
source <(fzf --zsh)
