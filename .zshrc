# initialization
export XDG_CONFIG_HOME="${HOME}/.config"

# keep PATH and FPATH free of duplicates: every nested shell (each tmux pane
# included) re-runs this file and would otherwise prepend the same dirs again,
# which makes command lookup and compinit's fpath scan slower in every pane
typeset -U path fpath

# ensure MSYS2 standard paths are available (for non-login shells)
if [[ -d "/usr/bin" ]] && [[ ":$PATH:" != *":/usr/bin:"* ]]; then
  export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"
fi

# platform detection ($OSTYPE is built in, so no `uname` process per shell)
case "$OSTYPE" in
  darwin*) _OS="macos" ;;
  linux*)  _OS="linux" ;;
  *)       _OS="unknown" ;;
esac

# homebrew (macOS Apple Silicon, macOS Intel, or Linuxbrew)
export HOMEBREW_CURLRC=1

## brew is a shell script and slow to start, so `brew shellenv` is skipped when
## a parent shell already ran it (e.g. inside tmux) - its exports are inherited
if [[ -z "$HOMEBREW_PREFIX" || ":$PATH:" != *":${HOMEBREW_PREFIX}/bin:"* ]]; then
  if [[ -f "/opt/homebrew/bin/brew" ]]; then
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -f "/usr/local/bin/brew" ]]; then
    eval "$(/usr/local/bin/brew shellenv)"
  elif [[ -f "/home/linuxbrew/.linuxbrew/bin/brew" ]]; then
    eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
  fi
fi
## (prepending through the fpath/path arrays is what lets `typeset -U` dedupe;
## assigning the FPATH/PATH strings directly bypasses it)
if [[ -n "$HOMEBREW_PREFIX" ]]; then
  fpath=("${HOMEBREW_PREFIX}/share/zsh-completions" $fpath)
  export FPATH
elif command -v brew &>/dev/null; then
  fpath=("$(brew --prefix)/share/zsh-completions" $fpath)
  export FPATH
fi

if [[ -f "${HOME}/.env" ]]; then
  source "${HOME}/.env"
fi

# treats all special characters as word boundaries
WORDCHARS=''

# init script cache
## Tools like starship, zoxide and carapace print their shell setup on every
## start, but that output only changes when the tool does. It is saved to disk
## once and sourced from there, which saves a process spawn per tool per shell.
_ZSH_CACHE_DIR="${XDG_CACHE_HOME:-${HOME}/.cache}/zsh"
zmodload -F zsh/stat b:zstat

##
# Makes sure the cached output of an init command is current.
#
# The cache is keyed on the resolved path and mtime of the tool (so a package
# upgrade, which changes the versioned path, is always picked up) plus the
# mtimes of any extra dependencies. When the key changed, the command is re-run
# and its output saved.
#
# The file is handed back in REPLY rather than sourced here, so the caller can
# `source "$REPLY"` at top level: sourcing inside a function would turn the
# script's own top-level `typeset`/`local` declarations into function locals.
#
# Usage: _cache_init <name> <tool> [<extra dependency>...] -- <command...>
#
# @param $1  name of the cache file (under $_ZSH_CACHE_DIR)
# @param $2  command name or path of the tool; skipped when not installed
# @param ... optional extra files or dirs whose changes invalidate the cache
# @param ... after `--`: the command that prints the init script
# @return 0 with REPLY set to the cache file; 1 when the tool is missing or
#         the command failed (nothing is cached then)
##
function _cache_init() {
  local name=$1 tool=$2 cache="${_ZSH_CACHE_DIR}/$1.zsh" stamp line dep out
  local -a mtime
  shift 2

  [[ "$tool" == */* ]] || tool="${commands[$tool]}"
  [[ -n "$tool" && -x "$tool" ]] || return 1

  stamp="# cache-key: ${tool:A}"
  for dep in "$tool" "${@[1,${@[(i)--]}-1]}"; do
    mtime=()
    zstat -A mtime +mtime -- "$dep" 2>/dev/null
    stamp+=":${mtime[1]}"
  done
  shift "${@[(i)--]}"

  [[ -r "$cache" ]] && IFS= read -r line < "$cache"
  if [[ "$line" != "$stamp" ]]; then
    out="$("$@")" && [[ -n "$out" ]] || return 1
    [[ -d "$_ZSH_CACHE_DIR" ]] || mkdir -p "$_ZSH_CACHE_DIR"
    print -r -- "${stamp}"$'\n'"${out}" >| "$cache" || return 1
  fi
  REPLY="$cache"
}

##
# Prints LS_COLORS from vivid as a sourceable `export` line, so it can be
# cached by _cache_init like the other init scripts.
##
function _vivid_ls_colors() {
  local colors
  colors="$(vivid generate ansi)" || return 1
  print -r -- "export LS_COLORS=${(qq)colors}"
}

# environment
## Everything exported here is set before tmux auto-starts below, so a tmux
## server launched from this shell (and whatever it runs outside a shell, like
## popups and plugin scripts) inherits the same environment as before.

# starship
export STARSHIP_CONFIG=~/.config/starship/starship.toml

# fzf
export FZF_DEFAULT_OPTS='
  --color=bg:#282828,bg+:#3c3836
  --color=fg:#ebdbb2,fg+:#fbf1c7
  --color=hl:#83a598,hl+:#8ec07c
  --color=info:#fabd2f,prompt:#fabd2f,pointer:#fe8019
  --color=marker:#b8bb26,spinner:#8ec07c,header:#83a598
  --layout=reverse-list
'

# zsh-vi-mode
ZVM_SYSTEM_CLIPBOARD_ENABLED=true

# editor
export EDITOR=nvim
export VISUAL="$EDITOR"

# paths
path_dirs=()

if [[ -f "/opt/homebrew/bin/brew" ]]; then
  path_dirs+=(
    "/opt/homebrew/opt/coreutils/libexec/gnubin"
    "/opt/homebrew/opt/ffmpeg-full/bin"
    "/opt/homebrew/opt/libpq/bin"
    "/opt/homebrew/opt/node@24/bin"
    "/opt/homebrew/opt/openjdk@21/bin"
    "/opt/homebrew/opt/python@3.13/bin"
  )

  export DYLD_LIBRARY_PATH="/opt/homebrew/lib:/opt/homebrew/lib/pam:$DYLD_LIBRARY_PATH"
fi

path_dirs+=(
  "$HOME/.local/bin"
  "$HOME/local/bin"
  "$HOME/.npm-global/bin"
  "$HOME/.antigravity/antigravity/bin"
  "$HOME/.bun/bin"
  "$HOME/.cargo/bin"
)

for p in "${path_dirs[@]}"; do
  path=("$p" $path)
done

if _cache_init vivid vivid -- _vivid_ls_colors; then
  source "$REPLY"
fi

# persistent CWD handling for tmux and OSC-7-aware terminals like Ghostty
## defined before tmux auto-starts, so the `cd` back into the session's last
## directory after tmux exits reports the new CWD to the terminal as well
function chpwd() {
  # update tmux status line
  [[ -n "$TMUX" ]] && tmux refresh-client -S

  # tell Ghostty (and other OSC-7-aware terminals) the new CWD
  if [[ -n "$TMUX" ]]; then
    # Pass OSC 7 through tmux using passthrough sequence \ePtmux;\e\e]7;file://%s%s\a\e\\
    # Inside, escape \e as \e\e
    printf '\ePtmux;\e\e]7;file://%s%s\a\e\\' "$HOST" "$PWD"
  else
    printf '\e]7;file://%s%s\a' "$HOST" "$PWD"
  fi

  # Update parent tmux pwd file if it exists
  [[ -n "$TMUX_PWD_FILE" ]] && echo "$PWD" > "$TMUX_PWD_FILE"
}

# tmux
## generate fun docker-style names
function _tmux_random_name() {
  local adjectives=(brave calm clever cool daring eager fancy gentle happy jolly angry)
  local animals=(otter fox panda koala falcon badger lynx wolf raven hawk hamster)
  local name
  while true; do
    name="${adjectives[$RANDOM % ${#adjectives[@]} + 1]}-${animals[$RANDOM % ${#animals[@]} + 1]}"
    if ! tmux has-session -t "$name" 2>/dev/null; then
      echo "$name"
      return
    fi
  done
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

##
# Brings back, once per boot, the tmux sessions that were open when the machine
# went down, before a new terminal picks a session to attach to.
#
# Sessions are saved by tmux-persist (see tmux.conf). This only acts on the
# first call after a reboot, and only when tmux has no sessions yet: it starts
# the server with a throwaway session so the plugins load, runs tmux-persist's
# restore of every saved session synchronously, then drops the throwaway one.
# Sessions closed on purpose were already forgotten when they closed, and a
# server that dies within a boot (kill-server, crash) is not restored
# automatically - use prefix + C-r per session, or its `restore.sh all`.
##
function _tmux_restore_after_boot() {
  local marker="${XDG_STATE_HOME:-${HOME}/.local/state}/tmux/restored-boot"
  local boot restored script

  if [[ -r /proc/sys/kernel/random/boot_id ]]; then
    boot="$(</proc/sys/kernel/random/boot_id)"
  elif [[ "$_OS" == "macos" ]]; then
    boot="$(sysctl -n kern.boottime 2>/dev/null)"
  fi
  [[ -n "$boot" ]] || return 0

  [[ -r "$marker" ]] && IFS= read -r restored < "$marker"
  [[ "$restored" == "$boot" ]] && return 0
  # record the boot first, so a failed restore is not retried in every window
  [[ -d "${marker:h}" ]] || mkdir -p "${marker:h}"
  print -r -- "$boot" >| "$marker"

  # sessions already running: nothing was lost
  [[ -n "$(tmux list-sessions -F x 2>/dev/null)" ]] && return 0

  tmux new-session -d -s __persist_restore 2>/dev/null || return 0
  script="$(tmux show-options -gqv @persist-restore-script-path)"
  if [[ -x "$script" ]]; then
    print -u2 "tmux: restoring saved sessions..."
    # through run-shell, which waits for it: the script finds its server
    # through $TMUX, and that is only set for commands tmux itself runs
    tmux run-shell "${(q)script} quiet all" >/dev/null 2>&1
  fi
  tmux kill-session -t '=__persist_restore' 2>/dev/null
}

##
# Attaches to the oldest detached tmux session, or starts a new one, and then
# moves this shell into the directory the session was last in.
#
# When more than one session is detached, another terminal window is opened to
# pick up the next one: Ghostty (macOS or Linux) or Windows Terminal (WSL).
# The session's shells report their directory through the file named by
# TMUX_PWD_FILE (see chpwd).
##
function _tmux_attach_local() {
  local -a detached
  local last_pwd

  # define a temp file for PWD persistence
  export TMUX_PWD_FILE="$(mktemp -t tmux-pwd.XXXXXX)"

  # get list of detached session names (split by newline), then filter out
  # empty elements (important when no sessions exist)
  detached=("${(@f)$(tmux list-sessions -f "#{==:#{session_attached},0}" -F "#{session_name}" 2>/dev/null)}")
  detached=("${detached[@]:#}")

  if [[ ${#detached[@]} -gt 0 ]]; then
    # if there are more detached sessions, open another terminal window to handle them
    if [[ ${#detached[@]} -gt 1 ]]; then
      if [[ "${TERM_PROGRAM}" == "ghostty" && "$_OS" == "macos" ]]; then
        nohup open -n -a Ghostty >/dev/null 2>&1 &
      elif [[ "${TERM_PROGRAM}" == "ghostty" ]]; then
        command -v ghostty &>/dev/null && nohup ghostty >/dev/null 2>&1 &
      elif command -v wt &>/dev/null; then
        nohup wt new-window --profile "Ubuntu" >/dev/null 2>&1 &
      else
        nohup wt.exe new-window --profile "Ubuntu" >/dev/null 2>&1 &
      fi
    fi

    tmux attach-session -t "${detached[1]}"
  else
    tmux new-session -s "$(_tmux_random_name)" -e TMUX_PWD_FILE="$TMUX_PWD_FILE"
  fi

  # upon exit, read the PWD and switch to it
  if [[ -f "$TMUX_PWD_FILE" ]]; then
    last_pwd="$(<"$TMUX_PWD_FILE")"
    if [[ -n "$last_pwd" && -d "$last_pwd" ]]; then
      builtin cd -- "$last_pwd"
    fi
    rm -f "$TMUX_PWD_FILE"
  fi
  unset TMUX_PWD_FILE
}

## auto-start tmux when opening a new terminal (Ghostty, SSH, or Windows
## Terminal under WSL), unless already inside tmux.
##
## This runs before plugins, completions and the prompt are loaded: the shell
## that starts tmux only waits for it, so loading all of that first made every
## new window pay the full startup cost twice (once here, once in the pane).
## If this shell keeps going after tmux exits, the rest of the file loads then.
if [[ -z "$TMUX" && -o interactive ]] &&
   [[ "${TERM_PROGRAM}" == "ghostty" || -n "${SSH_CONNECTION}" ||
      ( "$_OS" == "linux" && -n "$WT_PROFILE_ID" ) ]]; then
  # avoid nested/double tmux if the shell command line already invokes tmux
  # (e.g. zsh -c 'tmux ...')
  if ! ps -p $$ -o args= | grep -q "tmux"; then
    # the tmux server inherits this shell's environment, so put mise's tool
    # paths in it before starting tmux (see the mise section)
    command -v mise &>/dev/null && eval "$(mise activate zsh)"

    _tmux_restore_after_boot

    if [[ -n "${SSH_CONNECTION}" ]]; then
      selection=$(_tmux_pick_session)
      if [[ "$selection" == "+ new session" ]]; then
        exec tmux new-session -s "$(_tmux_random_name)"
      elif [[ -n "$selection" ]]; then
        session=$(echo "$selection" | cut -d: -f1)
        exec tmux attach -t "$session"
      fi
    else
      _tmux_attach_local
    fi
  fi
fi

# zinit
# set the directory we want to store zinit and plugins
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"

# download zinit, if it's not there yet
if [ ! -d "$ZINIT_HOME" ]; then
   mkdir -p "$(dirname $ZINIT_HOME)"
   git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi

# keep the completion dump out of ~/.zcompdump, which Ubuntu's global compinit
# rewrites with a different fpath (see .zshenv); zinit clears this path too
# whenever it installs completions, so it must know about it
typeset -gA ZINIT
ZINIT[ZCOMPDUMP_PATH]="${_ZSH_CACHE_DIR}/zcompdump"

# load zinit
source "${ZINIT_HOME}/zinit.zsh"
zinit ice depth=1

# add in zsh plugins
zinit light zsh-users/zsh-syntax-highlighting
zinit light zsh-users/zsh-completions
zinit light zsh-users/zsh-autosuggestions
zinit light Aloxaf/fzf-tab
#zinit light matheusml/zsh-ai
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
## A plain `compinit` audits every fpath dir for insecure permissions on each
## start. The audit, permission fix and rebuild only run when compinit would
## rebuild its dump anyway - the number of completion files in fpath or the zsh
## version changed - or once a day; otherwise the dump is loaded with -C.
autoload -Uz compinit

##
# Loads the completion system, rebuilding the dump (with the insecure-dir
# self-heal) only when it is out of date.
#
# Freshness is judged the way compinit judges it - file count in fpath plus zsh
# version - but against a key saved beside the dump rather than the dump's own
# header, because the header counts files after `compinit -i` has dropped any
# insecure dirs, so it never matches a plain count while one of those remains.
##
function _load_compinit() {
  setopt localoptions extendedglob
  local dump="${ZINIT[ZCOMPDUMP_PATH]}" key saved
  local -a files expired

  [[ -d "${dump:h}" ]] || mkdir -p "${dump:h}"

  # the same completion-file glob compinit counts
  files=( ${^~fpath:/.}/^([^_]*|*~|*.zwc)(N) )
  key="${#files} ${ZSH_VERSION}"
  [[ -r "${dump}.key" ]] && IFS= read -r saved < "${dump}.key"
  expired=( "$dump"(N.mh+24) )

  if [[ -s "$dump" && "$saved" == "$key" && ${#expired} -eq 0 ]]; then
    compinit -C -d "$dump"
  else
    # fix insecure dirs automatically, fall back to -i if no permission
    compaudit 2>/dev/null | xargs chmod g-w,o-w 2>/dev/null || true
    compinit -i -d "$dump"
    print -r -- "$key" >| "${dump}.key"
    # `source` picks up the compiled copy automatically while it is newer
    zcompile "$dump" 2>/dev/null
  fi
}
_load_compinit
zinit cdreplay -q

# starship
if [ "$TERM_PROGRAM" != "Apple_Terminal" ]; then
  # Workaround for starship init zsh quoting bug when the path contains spaces
  if [[ "$_OS" == "unknown" && -x /usr/bin/sed ]]; then
    eval "$(starship init zsh | /usr/bin/sed -E "s|'[^']*[/\\\\\\\\]starship(\\.exe)?'|starship|g")"
  elif _cache_init starship starship -- starship init zsh --print-full-init; then
    source "$REPLY"
  fi
fi

# yazi
function y() {
	local tmp="$(mktemp -t "yazi-cwd.XXXXXX")" cwd
	yazi "$@" --cwd-file="$tmp"
	IFS= read -r -d '' cwd < "$tmp"
	[ -n "$cwd" ] && [ "$cwd" != "$PWD" ] && builtin cd -- "$cwd"
	rm -f -- "$tmp"
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
zstyle ':fzf-tab:*' use-fzf-default-opts yes
zstyle ':fzf-tab:*' continuous-trigger '/'
zstyle ':fzf-tab:*' fzf-command ftb-tmux-popup
zstyle ':fzf-tab:*' popup-smart-tab yes
zstyle ':fzf-tab:*' popup-min-size 40 20
#zstyle ':fzf-tab:complete:__zoxide_z:*' fzf-preview 'ls --color $realpath'

# bind keys
bindkey -e                            # disable vi mode
#bindkey -v                           # enable vi mode
bindkey "^[[1;3C" forward-word        # next word
bindkey "^[[1;3D" backward-word       # previous word
bindkey "^[[1;5C" forward-word        # next word
bindkey "^[[1;5D" backward-word       # previous word
bindkey '^[^?'    backward-kill-word  # delete previous word
#bindkey '^R'     history-incremental-search-backward
#bindkey '^S'     history-incremental-search-forward

# aliases
if command -v nu &>/dev/null; then
  l() { nu -c "ls -a $@" }
  which() { nu -c "which $@" }
fi

alias ls='ls --color=always'
alias vim='nvim'
alias v='nvim'
alias lg='lazygit'
# superfile
alias s='spf'
alias ld='lazydocker'
alias c='clear'
# update all: run the per-OS task list with the task runner's own tsx (installing its
# dependencies on first use); options such as --verbose or --help are passed through.
# On Linux, prompt for sudo up front (the parallel task runner ignores child stdin, so an
# interactive sudo prompt inside a task would hang forever), then keep the sudo timestamp
# fresh in the background until the run finishes.
ua() {
  setopt localoptions localtraps nomonitor
  local runner_dir=~/dotfiles/scripts/run-tasks
  # tsx's CLI runs through node and needs esbuild's binary for this platform: node_modules
  # synced from another OS lacks both the executable bit and that binary, so reinstall then
  local tsx="${runner_dir}/node_modules/tsx/dist/cli.mjs"
  local esbuild="${runner_dir}/node_modules/@esbuild/$(node -p "process.platform + '-' + process.arch")"
  local sudo_keepalive= rc

  if [[ ! -f "$tsx" || ! -d "$esbuild" ]]; then
    print -u2 "ua: installing task runner dependencies..."
    npm ci --prefix "$runner_dir" --silent || return 1
  fi

  if [[ "$_OS" == "linux" && ${@[(I)(-h|--help)]} -eq 0 ]]; then
    sudo -v || return 1
    ( while true; do sudo -n true; sleep 60; kill -0 "$$" 2>/dev/null || exit; done ) &>/dev/null &
    sudo_keepalive=$!
    trap 'kill "$sudo_keepalive" 2>/dev/null; return 130' INT TERM
  fi

  node "$tsx" "${runner_dir}/run-tasks.ts" "${runner_dir}/update-${_OS}.yaml" "$@"
  rc=$?

  [[ -n "$sudo_keepalive" ]] && kill "$sudo_keepalive" 2>/dev/null
  return $rc
}

## claude code aliases
alias cc='claude --dangerously-skip-permissions'
alias ccs="~/scripts/ccswitch.sh"
alias ccl="ccs --list"
alias cc1="ccs --switch-to 1 && cc"
alias cc2="ccs --switch-to 2 && cc"

## dotfiles-sync: keep this repo and the work one in sync (see scripts/dotfiles-sync.sh)
alias dotfiles-sync="~/scripts/dotfiles-sync.sh"

# shell integrations (cached, see _cache_init)
_cache_init fzf fzf -- fzf --zsh && source "$REPLY"
_cache_init zoxide zoxide -- zoxide init zsh && source "$REPLY"
_cache_init notify ~/scripts/notify.sh -- ~/scripts/notify.sh --completions zsh && source "$REPLY"
_cache_init mole mole -- mole completion zsh && source "$REPLY"
## carapace's list of completers also depends on the user specs in its config dir
_cache_init carapace carapace "${XDG_CONFIG_HOME}/carapace" "${XDG_CONFIG_HOME}/carapace/specs" \
  -- carapace _carapace zsh && source "$REPLY"

# mise: tools pinned in ~/.config/mise/config.toml (e.g. the remux CLI)
## not cached: its output depends on mise's settings and the current env, and
## it must come after the command-not-found snippet so it can chain onto it
command -v mise &>/dev/null && eval "$(mise activate zsh)"

# bun completions
[ -s "/$HOME/.bun/_bun" ] && source "/$HOME/.bun/_bun"


# --- PERSISTENT SSH AGENT & KEY (only inside tmux) ---
if [[ -n "$TMUX" ]]; then
  SSH_ENV="$HOME/.ssh/agent.env"

  ##
  # Starts a new ssh-agent (keys expire after 24h), records its environment in
  # $SSH_ENV for later shells to reuse, and loads it into this shell.
  ##
  start_agent() {
    mkdir -p ~/.ssh/agent
    ssh-agent -t 24h > "$SSH_ENV" 2>/dev/null && source "$SSH_ENV" > /dev/null
  }

  # If no valid SSH_AUTH_SOCK, reuse the agent recorded in $SSH_ENV, and only
  # start a new one when that agent is gone - otherwise every new pane would
  # start (and leave behind) an ssh-agent of its own
  if [[ ! -S "$SSH_AUTH_SOCK" || "$SSH_AUTH_SOCK" != /tmp/ssh-*/* && "$SSH_AUTH_SOCK" != ~/.ssh/agent/* ]]; then
    [[ -f "$SSH_ENV" ]] && source "$SSH_ENV" > /dev/null
    if [[ ! -S "$SSH_AUTH_SOCK" ]] || ! kill -0 "$SSH_AGENT_PID" 2>/dev/null; then
      start_agent
    fi
  fi

  # If SSH_ENV exists, source it so SSH_AUTH_SOCK/SSH_AGENT_PID are set
  if [[ -f "$SSH_ENV" ]]; then
    source "$SSH_ENV" > /dev/null
  fi

  # Extra safety: export if set (sourcing $SSH_ENV already exports them)
  [[ -n "$SSH_AUTH_SOCK" ]] && export SSH_AUTH_SOCK
  [[ -n "$SSH_AGENT_PID" ]] && export SSH_AGENT_PID

  # Auto-add key once per agent session if not loaded
  if [[ -f ~/.ssh/dell-wsl && "$(ssh-add -l 2>/dev/null)" != *"$HOME/.ssh/dell-wsl"* ]]; then
    ssh-add ~/.ssh/dell-wsl 2>/dev/null || true
  fi
fi

# machine-specific settings kept outside the repo (see .syncignore)
[[ -r ~/.zshrc.local ]] && source ~/.zshrc.local
