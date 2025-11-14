# initialization
export XDG_CONFIG_HOME="$HOME/.config"

if [[ -f "/opt/homebrew/bin/brew" ]] then
  export FPATH="$(brew --prefix)/share/zsh-completions:$FPATH"
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

# zinit
# set the directory we want to store zinit and plugins
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"

# download zinit, if it's not there yet
if [ ! -d "$ZINIT_HOME" ]; then
   mkdir -p "$(dirname $ZINIT_HOME)"
   git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi

# load zinit
source "${ZINIT_HOME}/zinit.zsh"
zinit ice depth=1

# add in zsh plugins
zinit light zsh-users/zsh-syntax-highlighting
zinit light zsh-users/zsh-completions
zinit light zsh-users/zsh-autosuggestions
zinit light Aloxaf/fzf-tab

# add in snippets
zinit snippet OMZL::git.zsh
zinit snippet OMZP::git
zinit snippet OMZP::sudo
zinit snippet OMZP::archlinux
zinit snippet OMZP::aws
zinit snippet OMZP::kubectl
zinit snippet OMZP::kubectx
zinit snippet OMZP::command-not-found

# load completions
autoload -Uz compinit && compinit
zinit cdreplay -q

# starship
export STARSHIP_CONFIG=~/.config/starship/starship.toml

if [ "$TERM_PROGRAM" != "Apple_Terminal" ]; then
  eval "$(starship init zsh)"
fi

# yazi
function y() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
	yazi "$@" --cwd-file="$tmp"
	IFS= read -r -d '' cwd < "$tmp"
	[ -n "$cwd" ] && [ "$cwd" != "$PWD" ] && builtin cd -- "$cwd"
	rm -f -- "$tmp"
}

# editor
export EDITOR=nvim
export VISUAL="$EDITOR"

# claude code
export CLAUDE_POWERLINE_CONFIG=~/.config/claude/powerline/config.json
export CLAUDE_POWERLINE_DEBUG=0
export DEBUG=false

# history
HISTSIZE=5000
HISTFILE=~/.zsh_history
SAVEHIST=$HISTSIZE
HISTDUP=erase
setopt appendhistory
setopt sharehistory
setopt hist_ignore_space
setopt hist_ignore_all_dups
setopt hist_save_no_dups
setopt hist_ignore_dups
setopt hist_find_no_dups

# completion styling
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
zstyle ':completion:*' menu no
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls --color $realpath'
zstyle ':fzf-tab:complete:__zoxide_z:*' fzf-preview 'ls --color $realpath'

# aliases
alias ls='ls --color'
alias vim='nvim'
alias c='clear'
alias cc='claude'
alias ccg='claude-glm'
alias ccg45='claude-glm-4.5'
alias ccf='claude-glm-fast'
alias ccs="~/scripts/ccswitch.sh"
alias ccl="ccs --list"
alias cc1="ccs --switch-to 1 && cc"
alias cc2="ccs --switch-to 2 && cc"

# shell integrations
eval "$(fzf --zsh)"
eval "$(zoxide init zsh)"

# ghostty
#if [ -n "$GHOSTTY_RESOURCES_DIR" ]; then
#  nu
#fi

# paths
if [[ -f "/opt/homebrew/bin/brew" ]] then
  export PATH="/opt/homebrew/opt/python@3.13/bin:$PATH"
  export PATH="/opt/homebrew/opt/openjdk@21/bin:$PATH"
  export PATH="/opt/homebrew/opt/node@22/bin:$PATH"
  export PATH="$PATH:$HOME/.local/bin:$HOME/local/bin"
fi

