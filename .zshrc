export PATH="/opt/homebrew/opt/python@3.13/bin:$PATH"
export XDG_CONFIG_HOME="$HOME/.config"

# Created by `pipx` on 2025-05-20 14:16:07
export PATH="$PATH:$HOME/.local/bin"

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

# auto-complete
autoload -Uz compinit
compinit
