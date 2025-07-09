export PATH="/opt/homebrew/opt/python@3.13/bin:$PATH"

# Created by `pipx` on 2025-05-20 14:16:07
export PATH="$PATH:$HOME/.local/bin"

# starship
export STARSHIP_CONFIG=~/.config/starship/starship.toml
eval "$(starship init zsh)"

# Enable auto-complete
autoload -Uz compinit
compinit
