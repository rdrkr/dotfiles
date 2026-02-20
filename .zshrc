# initialization
export XDG_CONFIG_HOME="${HOME}/.config"

if [[ -f "/opt/homebrew/bin/brew" ]] then
  export FPATH="$(brew --prefix)/share/zsh-completions:${FPATH}"
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

if [[ -f "${HOME}/.env" ]] then
  source "${HOME}/.env"
fi

# treats all special characters as word boundaries
WORDCHARS=''

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
zinit light matheusml/zsh-ai
#zinit light jeffreytse/zsh-vi-mode

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

# zsh-vi-mode
ZVM_SYSTEM_CLIPBOARD_ENABLED=true

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

# persistent CWD handling for tmux and OSC-7-aware terminals like Ghostty
function chpwd() {
  # update tmux status line
  [[ -n "$TMUX" ]] && tmux refresh-client -S

  # tell Ghostty (and other OSC-7-aware terminals) the new CWD
  if [[ -n "$TMUX" ]]; then
    # Pass OSC 7 through tmux using passthrough sequence \ePtmux;...\e\\
    # Inside, escape \e as \e\e
    printf '\ePtmux;\e\e]7;file://%s%s\a\e\\' "$HOST" "$PWD"
  else
    printf '\e]7;file://%s%s\a' "$HOST" "$PWD"
  fi

  # Update parent tmux pwd file if it exists
  [[ -n "$TMUX_PWD_FILE" ]] && echo "$PWD" > "$TMUX_PWD_FILE"
}

function notify() {
  local title=$1 body=$2

  if [[ -n "${TMUX}" ]]; then
    printf "\ePtmux;\e\e]777;notify;%s;%s\a\e\\" "${title}" "${body}"
  else
    printf "\e]777;notify;%s;%s\a" "${title}" "${body}"
  fi
}

# notify hooks
function _notify_preexec() {
  _NOTIFY_CMD="$1"
}

function _notify_precmd() {
  if [[ -n "$_NOTIFY_CMD" ]]; then
    notify "Command Finished" "$_NOTIFY_CMD"
    unset _NOTIFY_CMD
  fi
}

autoload -Uz add-zsh-hook
add-zsh-hook preexec _notify_preexec
add-zsh-hook precmd _notify_precmd

# history
HISTSIZE=10000
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
zstyle ':completion:*' format $'\e[2;37mCompleting %d\e[m'
## fzf-tab settings
zstyle ':completion:*' menu no
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls --color $realpath'
zstyle ':fzf-tab:*' query-string prefix first
zstyle ':fzf-tab:*' continuous-trigger '/'
zstyle ':fzf-tab:*' fzf-command ftb-tmux-popup
zstyle ':fzf-tab:*' popup-min-size 40 20
#zstyle ':fzf-tab:complete:__zoxide_z:*' fzf-preview 'ls --color $realpath'

# bind keyos
bindkey -e                            # disable vi mode
#bindkey -v                           # enable vi mode
bindkey "^[[1;3C" forward-word        # autosuggest next word
bindkey "^[[1;3D" backward-word       # autosuggest previous word
bindkey "^[[1;3D" backward-word       # autosuggest previous word
bindkey '^[^?'    backward-kill-word  # delete previous word
#bindkey '^R'     history-incremental-search-backward 
#bindkey '^S'     history-incremental-search-forward

# aliases
l() { nu -c "ls -a $@" }
which() { nu -c "which $@" }

alias ls='ls --color=always'
alias vim='nvim'
alias c='clear'

## update all tools with a single command, showing a spinner for each task if gum is available
function update-all() {
  local zinit_home="${ZINIT_HOME:-${HOME}/.local/share/zinit/zinit.git}"
  
  local -a titles cmds outputs
  titles=(
    "Updating Homebrew..."
    "Upgrading Homebrew packages..."
    "Cleaning up Homebrew..."
    "Upgrading App Store apps..."
    "Upgrading Global NPM packages..."
    "Upgrading Pipx packages..."
    "Updating Zinit..."
    "Updating Zinit plugins..."
    "Clearing Zinit cache..."
    "Syncing LazyVim..."
    "Updating LazyVim..."
    "Updating Mason..."
    "Updating Treesitter..."
    "Updating Dotfiles pre-commit hooks..."
  )

  # zinit commands
  # We construct the source command explicitly to avoid quoting issues
  local z_update="source \"$zinit_home/zinit.zsh\" && zinit self-update"
  local z_plugins="source \"$zinit_home/zinit.zsh\" && zinit update --quiet --all"
  local z_clean="source \"$zinit_home/zinit.zsh\" && zinit cclear"

  cmds=(
    "brew update"
    "brew upgrade"
    "brew cleanup --prune=all"
    "mas upgrade"
    "npm upgrade --global"
    "pipx upgrade-all"
    "zsh -c '$z_update'"
    "zsh -c '$z_plugins'"
    "zsh -c '$z_clean'"
    'nvim --headless "+Lazy! sync" +qa'
    'nvim --headless "+Lazy! update" +qa'
    'nvim --headless "+MasonUpdate" +qa'
    'nvim --headless "+TSUpdate" +qa'
    "cd ~/dotfiles && pre-commit autoupdate"
  )

  outputs=(
    "--show-output"
    "--show-output"
    "--show-error"
    "--show-output"
    "--show-error"
    "--show-output"
    "--show-error"
    "--show-output"
    "--show-output"
    "--show-error"
    "--show-error"
    "--show-error"
    "--show-error"
    "--show-output"
  )

  if command -v gum >/dev/null 2>&1; then
    for i in {1..${#cmds}}; do
      local title="${titles[i]}"
      local cmd="${cmds[i]}"
      local output="${outputs[i]}"
      
      # Run command with spinner
      # We use zsh -l -c to ensure the environment (PATHs) is fully loaded
      gum spin --spinner="dot" --title="$title" "${output}" -- zsh -l -c "$cmd"
      
      # Check exit status
      if [ $? -eq 0 ]; then
        printf "%s  %-34s %s\n" "$(gum style --foreground 2 "")" "${title%...}..." "$(gum style --foreground 2 "done")"
      else
        printf "%s  %-34s %s\n" "$(gum style --foreground 1 "")" "${title%...}..." "$(gum style --foreground 1 "failed!")"
      fi
    done
  else
    for cmd in "${cmds[@]}"; do
      echo "Running: $cmd"
      eval "$cmd"
    done
  fi

  source ~/.zshrc
}
alias ua='update-all'

alias cc='claude --dangerously-skip-permissions'
alias ccg='claude-glm'
alias ccg45='claude-glm-4.5'
alias ccf='claude-glm-fast'
alias ccs="~/scripts/ccswitch.sh"
alias ccl="ccs --list"
alias cc1="ccs --switch-to 1 && cc"
alias cc2="ccs --switch-to 2 && cc"

# claude antigravity proxy handling
function _claude_antigravity_run() {
  local proxy_name="antigravity-claude-proxy"
  local proxy_cmd="/opt/homebrew/bin/antigravity-claude-proxy"
  local started_proxy=0

  # check if the proxy is already running (check process AND port)
  # we start it if process is missing OR port 8080 is closed
  if ! pgrep -f "$proxy_name" >/dev/null 2>&1 || ! nc -z 127.0.0.1 8080 >/dev/null 2>&1; then
    echo "Starting antigravity proxy..."
    # start proxy in background
    "$proxy_cmd" start >/dev/null 2>&1 &
    local proxy_pid=$!
    started_proxy=1

    # wait for the proxy to be ready on port 8080
    local timeout=50 # 5 seconds
    while ! nc -z 127.0.0.1 8080 >/dev/null 2>&1 && [[ $timeout -gt 0 ]]; do
      sleep 0.1
      ((timeout--))
    done

    if [[ $timeout -eq 0 ]]; then
      echo "Warning: antigravity proxy failed to start or port 8080 is not responsive."
    fi
  fi

  # run Claude
  command claude --dangerously-skip-permissions "$@"

  # cleanup
  if [[ $started_proxy -eq 1 ]]; then
    echo "Stopping antigravity proxy..."
    # kill the specific PID we started
    kill "$proxy_pid" 2>/dev/null || true
  fi
}

function claude-antigravity-opus() {
  local -x CLAUDE_CONFIG_DIR=~/.claude-account-antigravity
  local -x ANTHROPIC_AUTH_TOKEN="antigravity"
  local -x ANTHROPIC_BASE_URL="http://localhost:8080"
  local -x ANTHROPIC_MODEL="claude-opus-4-5-thinking"
  local -x ANTHROPIC_DEFAULT_OPUS_MODEL="claude-opus-4-5-thinking"
  local -x ANTHROPIC_DEFAULT_SONNET_MODEL="claude-sonnet-4-5-thinking"
  local -x ANTHROPIC_DEFAULT_HAIKU_MODEL="gemini-2.5-flash-lite[1m]"
  local -x CLAUDE_CODE_SUBAGENT_MODEL="claude-sonnet-4-5-thinking"
  local -x ENABLE_EXPERIMENTAL_MCP_CLI="true"

  _claude_antigravity_run "$@"
}
alias cco='claude-antigravity-opus'

function claude-antigravity-gemini() {
  local -x CLAUDE_CONFIG_DIR=~/.claude-account-antigravity
  local -x ANTHROPIC_AUTH_TOKEN="antigravity"
  local -x ANTHROPIC_BASE_URL="http://localhost:8080"
  local -x ANTHROPIC_MODEL="gemini-3-pro-high[1m]"
  local -x ANTHROPIC_DEFAULT_OPUS_MODEL="gemini-3-pro-high[1m]"
  local -x ANTHROPIC_DEFAULT_SONNET_MODEL="gemini-3-flash[1m]"
  local -x ANTHROPIC_DEFAULT_HAIKU_MODEL="gemini-2.5-flash-lite[1m]"
  local -x CLAUDE_CODE_SUBAGENT_MODEL="gemini-3-flash[1m]"
  local -x ENABLE_EXPERIMENTAL_MCP_CLI="true"

  _claude_antigravity_run "$@"
}
alias ccg='claude-antigravity-gemini'

# shell integrations
eval "$(fzf --zsh)"
eval "$(zoxide init zsh)"
source <(carapace _carapace)

# paths
if [[ -f "/opt/homebrew/bin/brew" ]] then
  export PATH="/opt/homebrew/opt/python@3.13/bin:$PATH"
  export PATH="/opt/homebrew/opt/openjdk@21/bin:$PATH"
  export PATH="/opt/homebrew/opt/node@22/bin:$PATH"
  export PATH="/opt/homebrew/opt/libpq/bin:$PATH"
  export DYLD_LIBRARY_PATH="/opt/homebrew/lib:/opt/homebrew/lib/pam:$DYLD_LIBRARY_PATH"
fi

export PATH="$PATH:$HOME/.local/bin:$HOME/local/bin"
export PATH="/Users/ronendruker/.antigravity/antigravity/bin:$PATH"

# tmux
## generate fun docker-style names
function _tmux_random_name() {
  local adjectives=(brave calm clever cool daring eager fancy gentle happy jolly angry)
  local animals=(otter fox panda koala falcon badger lynx wolf raven hawk hamster)
  echo "${adjectives[$RANDOM % ${#adjectives[@]} + 1]}-${animals[$RANDOM % ${#animals[@]} + 1]}"
}

## gum/fzf picker with option to create new session
function _tmux_pick_session() {
  local selection
  if command -v gum >/dev/null 2>&1; then
    selection=$( (echo "+ new session"; tmux list-sessions -F "#{session_name}" 2>/dev/null) | \
      gum filter --placeholder "Pick session...")
  elif command -v fzf >/dev/null 2>&1; then
    selection=$( (echo "+ new session"; tmux ls -F "#{session_name}: #{session_windows} windows" 2>/dev/null) | \
      fzf --height 40% --reverse --prompt="tmux session> ")
  else
    selection="+ new session"
  fi
  echo "$selection"
}

## auto-start tmux when opening a new terminal, but only if we're in Ghostty or SSH and not already inside tmux
if [[ ("${TERM_PROGRAM}" == "ghostty" || -n "${SSH_CONNECTION}") && -z "$TMUX" && -o interactive ]]; then
  # avoid nested/double tmux if the shell command line already invokes tmux
  # (e.g. zsh -c 'tmux ...')
  if ! ps -p $$ -o args= | grep -q "tmux"; then
    if [[ -n "${SSH_CONNECTION}" ]]; then
      selection=$(_tmux_pick_session)
      if [[ "$selection" == "+ new session" ]]; then
        exec tmux new-session -s "$(_tmux_random_name)"
      elif [[ -n "$selection" ]]; then
        session=$(echo "$selection" | cut -d: -f1)
        exec tmux attach -t "$session"
      fi
    else
      # define a temp file for PWD persistence
      export TMUX_PWD_FILE="$(mktemp -t tmux-pwd.XXXXXX)"
    
      # check for detached sessions
      # get list of detached session names (split by newline)
      local -a _detached_sessions
      _detached_sessions=("${(@f)$(tmux list-sessions -f "#{==:#{session_attached},0}" -F "#{session_name}" 2>/dev/null)}")
      # filter out empty elements (important when no sessions exist)
      _detached_sessions=("${_detached_sessions[@]:#}")

      if [[ ${#_detached_sessions[@]} -gt 0 ]]; then
        local _target_session="${_detached_sessions[1]}"

        # if there are more detached sessions, open another terminal window to handle them
        if [[ ${#_detached_sessions[@]} -gt 1 ]]; then
          nohup open -n -a Ghostty >/dev/null 2>&1 &
        fi

        tmux attach-session -t "$_target_session"
      else
        tmux new-session -s "$(_tmux_random_name)" -e TMUX_PWD_FILE="$TMUX_PWD_FILE"
      fi
      unset _detached_sessions
    
      # upon exit, read the PWD and switch to it
      if [[ -f "$TMUX_PWD_FILE" ]]; then
         local last_pwd="$(cat "$TMUX_PWD_FILE")"
         if [[ -n "$last_pwd" && -d "$last_pwd" ]]; then
            builtin cd -- "$last_pwd"
         fi
         rm -f "$TMUX_PWD_FILE"
      fi
      unset TMUX_PWD_FILE
    fi
  fi
fi

