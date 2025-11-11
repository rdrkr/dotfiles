# config.nu
#
# Installed by:
# version = "0.107.0"
#
# This file is used to override default Nushell settings, define
# (or import) custom commands, or run any other startup tasks.
# See https://www.nushell.sh/book/configuration.html
#
# Nushell sets "sensible defaults" for most configuration settings, 
# so your `config.nu` only needs to override these defaults if desired.
#
# You can open this file in your default editor using:
#     config nu
#
# You can also pretty-print and page through the documentation for configuration
# options using:
#     config nu --doc | nu-highlight | less -R

$env.config.show_banner = false

# Starship
mkdir ($nu.data-dir | path join "vendor/autoload")
starship init nu | save -f ($nu.data-dir | path join "vendor/autoload/starship.nu")

# Carapace
source $"($nu.cache-dir)/carapace.nu"

# Claude
def switch_claude_account_1 [] {
  ccs --switch-to 1; cc
}

def switch_claude_account_2 [] {
  ccs --switch-to 2; cc
}

$env.claude_powerline_config = "~/.config/claude/powerline/config.json"
$env.claude_powerline_debug = 0
$env.DEBUG = false

alias cc = claude
alias ccg = claude-glm
alias ccg45 = claude-glm-4.5
alias ccf = claude-glm-fast

alias ccs = ~/scripts/ccswitch.sh
alias ccl = ccs --list
alias cc1 = switch_claude_account_1
alias cc2 = switch_claude_account_2

