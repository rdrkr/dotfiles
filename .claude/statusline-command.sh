#!/bin/bash
config_file="$HOME/.claude/statusline-config.txt"
if [ -f "$config_file" ]; then
  source "$config_file"
  show_account=${SHOW_ACCOUNT:-1}
  show_dir=${SHOW_DIRECTORY:-1}
  show_model=${SHOW_MODEL:-1}
  show_branch=${SHOW_BRANCH:-1}
  show_usage=${SHOW_USAGE:-1}
  show_bar=${SHOW_PROGRESS_BAR:-1}
  show_reset=${SHOW_RESET_TIME:-1}
  show_weekly_usage=${SHOW_WEEKLY_USAGE:-1}
  show_weekly_bar=${SHOW_WEEKLY_PROGRESS_BAR:-1}
  show_weekly_reset=${SHOW_WEEKLY_RESET_TIME:-1}
  colorful_usage=${COLORFUL_USAGE:-0}
else
  show_account=1
  show_dir=1
  show_model=1
  show_branch=1
  show_usage=1
  show_bar=1
  show_reset=1
  show_weekly_usage=1
  show_weekly_bar=1
  show_weekly_reset=1
  colorful_usage=0
fi

input=$(cat)
current_dir_path=$(echo "$input" | grep -o '"current_dir":"[^"]*"' | sed 's/"current_dir":"//;s/"$//')
model_name=$(echo "$input" | jq -r '.model.display_name')
current_dir=$(basename "$current_dir_path")
BLUE=$'\033[0;34m'
GREEN=$'\033[0;32m'
GRAY=$'\033[0;90m'
YELLOW=$'\033[0;33m'
PURPLE=$'\033[0;35m'
RESET=$'\033[0m'

# 10-level gradient: dark green → deep red
LEVEL_1=$'\033[38;5;22m'   # dark green
LEVEL_2=$'\033[38;5;28m'   # soft green
LEVEL_3=$'\033[38;5;34m'   # medium green
LEVEL_4=$'\033[38;5;100m'  # green-yellowish dark
LEVEL_5=$'\033[38;5;142m'  # olive/yellow-green dark
LEVEL_6=$'\033[38;5;178m'  # muted yellow
LEVEL_7=$'\033[38;5;172m'  # muted yellow-orange
LEVEL_8=$'\033[38;5;166m'  # darker orange
LEVEL_9=$'\033[38;5;160m'  # dark red
LEVEL_10=$'\033[38;5;124m' # deep red

separator="${GRAY} │ ${RESET}"

# Build components (without separators)
account_text=""
if [ "$show_account" = "1" ] && [ -f "$HOME/.claude-switch-backup/sequence.json" ]; then
  active_account=$(jq -r '.activeAccountNumber' "$HOME/.claude-switch-backup/sequence.json" 2>/dev/null)
  if [ -n "$active_account" ] && [ "$active_account" != "null" ]; then
    email=$(jq -r --arg acc "$active_account" '.accounts[$acc].email' "$HOME/.claude-switch-backup/sequence.json" 2>/dev/null)
    if [ -n "$email" ] && [ "$email" != "null" ]; then
      domain=$(echo "$email" | awk -F'[@.]' '{print $2}')
      account_text="${BLUE}${active_account}-${domain}${RESET}"
    fi
  fi
fi

dir_text=""
if [ "$show_dir" = "1" ]; then
  dir_text="${YELLOW}${current_dir}${RESET}"
fi

model_text=""
if [ "$show_model" = "1" ] && [ -n "$model_name" ] && [ "$model_name" != "null" ]; then
  model_text="${PURPLE}${model_name}${RESET}"
fi

branch_text=""
if [ "$show_branch" = "1" ]; then
  if git rev-parse --git-dir >/dev/null 2>&1; then
    branch=$(git branch --show-current 2>/dev/null)
    [ -n "$branch" ] && branch_text="${GREEN}⎇ ${branch}${RESET}"
  fi
fi

line1=""
[ -n "$account_text" ] && line1="${account_text}"

if [ -n "$dir_text" ]; then
  [ -n "$line1" ] && line1="${line1}${separator}"
  line1="${line1}${dir_text}"
fi

if [ -n "$model_text" ]; then
  [ -n "$line1" ] && line1="${line1}${separator}"
  line1="${line1}${model_text}"
fi

if [ -n "$branch_text" ]; then
  [ -n "$line1" ] && line1="${line1}${separator}"
  line1="${line1}${branch_text}"
fi

format_usage_str() {
  local util=$1
  local resets_at=$2
  local is_weekly=$3
  local acc_prefix=$4
  local acc_color=$5
  local connector=$6

  local label=""
  local bar_flag=""
  local reset_flag=""

  if [ "$is_weekly" = "1" ]; then
    label="w"
    bar_flag="$show_weekly_bar"
    reset_flag="$show_weekly_reset"
  else
    label="s"
    bar_flag="$show_bar"
    reset_flag="$show_reset"
  fi

  local prefix_part=""
  if [ -n "$acc_prefix" ]; then
    prefix_part="${GRAY}${connector:-⎿} ${RESET}${acc_color}${acc_prefix}${RESET} "
  fi

  if [ -n "$util" ] && [ "$util" != "ERROR" ] && [[ "$util" =~ ^[0-9]+$ ]]; then
    # color selection
    local usage_color=""
    if [ "$colorful_usage" = "1" ]; then
      if [ "$util" -le 10 ]; then
        usage_color="$LEVEL_1"
      elif [ "$util" -le 20 ]; then
        usage_color="$LEVEL_2"
      elif [ "$util" -le 30 ]; then
        usage_color="$LEVEL_3"
      elif [ "$util" -le 40 ]; then
        usage_color="$LEVEL_4"
      elif [ "$util" -le 50 ]; then
        usage_color="$LEVEL_5"
      elif [ "$util" -le 60 ]; then
        usage_color="$LEVEL_6"
      elif [ "$util" -le 70 ]; then
        usage_color="$LEVEL_7"
      elif [ "$util" -le 80 ]; then
        usage_color="$LEVEL_8"
      elif [ "$util" -le 90 ]; then
        usage_color="$LEVEL_9"
      else usage_color="$LEVEL_10"; fi
    else
      if [ "$util" -le 60 ]; then
        usage_color="$GRAY"
      elif [ "$util" -le 70 ]; then
        usage_color="$LEVEL_7"
      elif [ "$util" -le 80 ]; then
        usage_color="$LEVEL_8"
      elif [ "$util" -le 90 ]; then
        usage_color="$LEVEL_9"
      else usage_color="$LEVEL_10"; fi
    fi

    # progress bar
    local progress_bar=""
    if [ "$bar_flag" = "1" ]; then
      local filled_blocks=0
      if [ "$util" -eq 0 ]; then
        filled_blocks=0
      elif [ "$util" -eq 100 ]; then
        filled_blocks=10
      else filled_blocks=$(((util * 10 + 50) / 100)); fi
      [ "$filled_blocks" -lt 0 ] && filled_blocks=0
      [ "$filled_blocks" -gt 10 ] && filled_blocks=10
      local empty_blocks=$((10 - filled_blocks))

      progress_bar=" "
      local i=0
      while [ $i -lt $filled_blocks ]; do
        progress_bar="${progress_bar}▓"
        i=$((i + 1))
      done
      i=0
      while [ $i -lt $empty_blocks ]; do
        progress_bar="${progress_bar}░"
        i=$((i + 1))
      done
      progress_bar="${progress_bar} "
    fi

    # reset time
    local reset_time_display=""
    if [ "$reset_flag" = "1" ] && [ -n "$resets_at" ] && [ "$resets_at" != "null" ]; then
      local iso_time
      iso_time=$(echo "$resets_at" | sed 's/\.[0-9]*Z$//')

      local epoch
      epoch=$(date -ju -f "%Y-%m-%dT%H:%M:%S" "$iso_time" "+%s" 2>/dev/null)

      if [ -n "$epoch" ]; then
        local time_format=$(defaults read -g AppleICUForce24HourTime 2>/dev/null)
        local reset_time=""
        if [ "$is_weekly" = "1" ]; then
          if [ "$time_format" = "1" ]; then
            reset_time=$(date -r "$epoch" "+%a %H:%M" 2>/dev/null)
          else reset_time=$(date -r "$epoch" "+%a %I:%M %p" 2>/dev/null); fi
        else
          if [ "$time_format" = "1" ]; then
            reset_time=$(date -r "$epoch" "+%H:%M" 2>/dev/null)
          else reset_time=$(date -r "$epoch" "+%I:%M %p" 2>/dev/null); fi
        fi
        [ -n "$reset_time" ] && reset_time_display=$(printf "→ %s" "$reset_time")
      fi
    fi

    local formatted_util=$(printf "%-4s" "${util}%")
    echo "${prefix_part}${usage_color}${label} ${formatted_util}${progress_bar}${reset_time_display}${RESET}"
  else
    echo "${prefix_part}${YELLOW}${label} ~   ${RESET}"
  fi
}

usage_lines=()

process_result() {
  local swift_result=$1
  local prefix=$2
  local p_color=$3
  local connector=$4

  local utilization=""
  local resets_at=""
  local sd_utilization=""
  local sd_resets_at=""

  if [ -n "$swift_result" ]; then
    utilization=$(echo "$swift_result" | cut -d'|' -f1)
    resets_at=$(echo "$swift_result" | cut -d'|' -f2)
    sd_utilization=$(echo "$swift_result" | cut -d'|' -f3)
    sd_resets_at=$(echo "$swift_result" | cut -d'|' -f4)
  else
    utilization="ERROR"
    sd_utilization="ERROR"
  fi

  local acc_line=""
  if [ "$show_usage" = "1" ]; then
    local u_text
    u_text=$(format_usage_str "$utilization" "$resets_at" "0" "$prefix" "$p_color" "$connector")

    acc_line="${u_text}"
  fi

  if [ "$show_weekly_usage" = "1" ]; then
    local w_text
    w_text=$(format_usage_str "$sd_utilization" "$sd_resets_at" "1" "" "")

    if [ -n "$acc_line" ]; then
      acc_line="${acc_line}${separator}${w_text}"
    else
      # If session is hidden, still show prefix on weekly
      w_text=$(format_usage_str "$sd_utilization" "$sd_resets_at" "1" "$prefix" "$p_color" "$connector")
      acc_line="${w_text}"
    fi
  fi

  if [ -n "$acc_line" ]; then
    usage_lines+=("$acc_line")
  fi
}

if [ "$show_usage" = "1" ] || [ "$show_weekly_usage" = "1" ]; then
  if [ -f "$HOME/.claude-switch-backup/sequence.json" ]; then
    active_account=$(jq -r '.activeAccountNumber' "$HOME/.claude-switch-backup/sequence.json" 2>/dev/null)
    sequence=$(jq -r '.sequence[]' "$HOME/.claude-switch-backup/sequence.json" 2>/dev/null)

    if [ -z "$sequence" ]; then
      swift_result=$(swift "$HOME/.claude/fetch-claude-usage.swift" 2>/dev/null)
      process_result "$swift_result" ""
    else
      # Reorder sequence so active_account is first
      ordered_accounts=("$active_account")
      for acc in $sequence; do
        if [ "$acc" != "$active_account" ]; then
          ordered_accounts+=("$acc")
        fi
      done

      # Calculate max prefix length for alignment
      max_len=0
      for acc in "${ordered_accounts[@]}"; do
        email=$(jq -r --arg acc "$acc" '.accounts[$acc].email' "$HOME/.claude-switch-backup/sequence.json" 2>/dev/null)
        domain=""
        if [ -n "$email" ] && [ "$email" != "null" ]; then
          domain=$(echo "$email" | awk -F'[@.]' '{print $2}')
        fi
        raw_prefix="${acc}-${domain}"
        if [ ${#raw_prefix} -gt $max_len ]; then
          max_len=${#raw_prefix}
        fi
      done

      colors=("$BLUE" "$GREEN" "$YELLOW" "$PURPLE")
      color_idx=0
      num_accounts=${#ordered_accounts[@]}
      count=0

      for acc in "${ordered_accounts[@]}"; do
        count=$((count + 1))
        connector="├─"
        [ "$count" -eq "$num_accounts" ] && connector="└─"

        email=$(jq -r --arg acc "$acc" '.accounts[$acc].email' "$HOME/.claude-switch-backup/sequence.json" 2>/dev/null)
        domain=""
        if [ -n "$email" ] && [ "$email" != "null" ]; then
          domain=$(echo "$email" | awk -F'[@.]' '{print $2}')
        fi
        raw_prefix="${acc}-${domain}"

        pad_len=$((max_len - ${#raw_prefix}))
        if [ "$pad_len" -gt 0 ]; then
          pad_spaces=$(printf "%*s" $pad_len "")
          acc_prefix="${raw_prefix}${pad_spaces}"
        else
          acc_prefix="${raw_prefix}"
        fi

        acc_color="${colors[$color_idx]}"
        color_idx=$(((color_idx + 1) % 4))

        if [ "$acc" = "$active_account" ]; then
          script_path="$HOME/.claude/fetch-claude-usage.swift"
        else
          script_path="$HOME/.claude-switch-backup/scripts/.fetch-claude-usage-${acc}-${email}.swift"
        fi

        if [ -f "$script_path" ]; then
          swift_result=$(swift "$script_path" 2>/dev/null)
          process_result "$swift_result" "$acc_prefix" "$acc_color" "$connector"
        else
          process_result "ERROR" "$acc_prefix" "$acc_color" "$connector"
        fi
      done
    fi
  else
    swift_result=$(swift "$HOME/.claude/fetch-claude-usage.swift" 2>/dev/null)
    process_result "$swift_result" ""
  fi
fi

printf "%s\n" "$line1"

for line in "${usage_lines[@]}"; do
  printf "%s\n" "$line"
done
