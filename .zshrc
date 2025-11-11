export PATH="/opt/homebrew/opt/python@3.13/bin:$PATH"
export PATH="/opt/homebrew/opt/openjdk@21/bin:$PATH"
export PATH="/opt/homebrew/opt/node@22/bin:$PATH"
export PATH="$PATH:$HOME/.local/bin:$HOME/local/bin"

export XDG_CONFIG_HOME="$HOME/.config"

# starship
export STARSHIP_CONFIG=~/.config/starship/starship.toml

if [ "$TERM_PROGRAM" != "Apple_Terminal" ]; then
  eval "$(starship init zsh)"
fi

# atuin
# eval "$(atuin init zsh)"

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

# fzf key bindings and fuzzy completion
source <(fzf --zsh)

# claude code
export claude_powerline_config=~/.config/claude/powerline/config.json
export claude_powerline_debug=0
export DEBUG=false

alias cc='claude'
alias ccg='claude-glm'
alias ccg45='claude-glm-4.5'
alias ccf='claude-glm-fast'

alias ccs="~/scripts/ccswitch.sh"
alias ccl="ccs --list"
alias cc1="ccs --switch-to 1 && cc"
alias cc2="ccs --switch-to 2 && cc"

if type brew &>/dev/null; then
  export DISABLE_AUTOUPDATER=1

  export ZSH_HIGHLIGHT_HIGHLIGHTERS_DIR=/opt/homebrew/share/zsh-syntax-highlighting/highlighters
  source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh

  export ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE="fg=8"
  source /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh

  # auto-complete
  FPATH=$(brew --prefix)/share/zsh-completions:$FPATH
  autoload -Uz compinit
  compinit
fi

# ghostty
if [ -n "$GHOSTTY_RESOURCES_DIR" ]; then
  nu
fi

