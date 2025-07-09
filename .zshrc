export PATH="/opt/homebrew/opt/python@3.13/bin:$PATH"

# Created by `pipx` on 2025-05-20 14:16:07
export PATH="$PATH:$HOME/.local/bin"

# starship
export STARSHIP_CONFIG=~/.config/starship/starship.toml

if [ "$TERM_PROGRAM" != "Apple_Terminal" ]; then
  eval "$(starship init zsh)"
fi

# Enable auto-complete
autoload -Uz compinit
compinit
