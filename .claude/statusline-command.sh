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

usage_text=""
weekly_usage_text=""
if [ "$show_usage" = "1" ] || [ "$show_weekly_usage" = "1" ]; then
  swift_result=$(swift "$HOME/.claude/fetch-claude-usage.swift" 2>/dev/null)

  if [ $? -eq 0 ] && [ -n "$swift_result" ]; then
    utilization=$(echo "$swift_result" | cut -d'|' -f1)
    resets_at=$(echo "$swift_result" | cut -d'|' -f2)
    sd_utilization=$(echo "$swift_result" | cut -d'|' -f3)
    sd_resets_at=$(echo "$swift_result" | cut -d'|' -f4)

    if [ "$show_usage" = "1" ]; then
      if [ -n "$utilization" ] && [ "$utilization" != "ERROR" ]; then
        if [ "$colorful_usage" = "1" ]; then
          if [ "$utilization" -le 10 ]; then
            usage_color="$LEVEL_1"
          elif [ "$utilization" -le 20 ]; then
            usage_color="$LEVEL_2"
          elif [ "$utilization" -le 30 ]; then
            usage_color="$LEVEL_3"
          elif [ "$utilization" -le 40 ]; then
            usage_color="$LEVEL_4"
          elif [ "$utilization" -le 50 ]; then
            usage_color="$LEVEL_5"
          elif [ "$utilization" -le 60 ]; then
            usage_color="$LEVEL_6"
          elif [ "$utilization" -le 70 ]; then
            usage_color="$LEVEL_7"
          elif [ "$utilization" -le 80 ]; then
            usage_color="$LEVEL_8"
          elif [ "$utilization" -le 90 ]; then
            usage_color="$LEVEL_9"
          else usage_color="$LEVEL_10"; fi
        else
          if [ "$utilization" -le 60 ]; then
            usage_color="$GRAY"
          elif [ "$utilization" -le 70 ]; then
            usage_color="$LEVEL_7"
          elif [ "$utilization" -le 80 ]; then
            usage_color="$LEVEL_8"
          elif [ "$utilization" -le 90 ]; then
            usage_color="$LEVEL_9"
          else usage_color="$LEVEL_10"; fi
        fi

        if [ "$show_bar" = "1" ]; then
          if [ "$utilization" -eq 0 ]; then
            filled_blocks=0
          elif [ "$utilization" -eq 100 ]; then
            filled_blocks=10
          else filled_blocks=$(((utilization * 10 + 50) / 100)); fi
          [ "$filled_blocks" -lt 0 ] && filled_blocks=0
          [ "$filled_blocks" -gt 10 ] && filled_blocks=10
          empty_blocks=$((10 - filled_blocks))

          progress_bar=" "
          i=0
          while [ $i -lt $filled_blocks ]; do
            progress_bar="${progress_bar}▓"
            i=$((i + 1))
          done
          i=0
          while [ $i -lt $empty_blocks ]; do
            progress_bar="${progress_bar}░"
            i=$((i + 1))
          done
        else
          progress_bar=""
        fi

        reset_time_display=""
        if [ "$show_reset" = "1" ] && [ -n "$resets_at" ] && [ "$resets_at" != "null" ]; then
          iso_time=$(echo "$resets_at" | sed 's/\.[0-9]*Z$//')
          epoch=$(date -ju -f "%Y-%m-%dT%H:%M:%S" "$iso_time" "+%s" 2>/dev/null)

          if [ -n "$epoch" ]; then
            time_format=$(defaults read -g AppleICUForce24HourTime 2>/dev/null)
            if [ "$time_format" = "1" ]; then
              reset_time=$(date -r "$epoch" "+%H:%M" 2>/dev/null)
            else reset_time=$(date -r "$epoch" "+%I:%M %p" 2>/dev/null); fi
            [ -n "$reset_time" ] && reset_time_display=$(printf " → Reset: %s" "$reset_time")
          fi
        fi

        usage_text="${usage_color}Session: ${utilization}%${progress_bar}${reset_time_display}${RESET}"
      else
        usage_text="${YELLOW}Session: ~${RESET}"
      fi
    fi

    if [ "$show_weekly_usage" = "1" ]; then
      if [ -n "$sd_utilization" ] && [ "$sd_utilization" != "ERROR" ]; then
        if [ "$colorful_usage" = "1" ]; then
          if [ "$sd_utilization" -le 10 ]; then
            sd_usage_color="$LEVEL_1"
          elif [ "$sd_utilization" -le 20 ]; then
            sd_usage_color="$LEVEL_2"
          elif [ "$sd_utilization" -le 30 ]; then
            sd_usage_color="$LEVEL_3"
          elif [ "$sd_utilization" -le 40 ]; then
            sd_usage_color="$LEVEL_4"
          elif [ "$sd_utilization" -le 50 ]; then
            sd_usage_color="$LEVEL_5"
          elif [ "$sd_utilization" -le 60 ]; then
            sd_usage_color="$LEVEL_6"
          elif [ "$sd_utilization" -le 70 ]; then
            sd_usage_color="$LEVEL_7"
          elif [ "$sd_utilization" -le 80 ]; then
            sd_usage_color="$LEVEL_8"
          elif [ "$sd_utilization" -le 90 ]; then
            sd_usage_color="$LEVEL_9"
          else sd_usage_color="$LEVEL_10"; fi
        else
          if [ "$sd_utilization" -le 60 ]; then
            sd_usage_color="$GRAY"
          elif [ "$sd_utilization" -le 70 ]; then
            sd_usage_color="$LEVEL_7"
          elif [ "$sd_utilization" -le 80 ]; then
            sd_usage_color="$LEVEL_8"
          elif [ "$sd_utilization" -le 90 ]; then
            sd_usage_color="$LEVEL_9"
          else sd_usage_color="$LEVEL_10"; fi
        fi

        if [ "$show_weekly_bar" = "1" ]; then
          if [ "$sd_utilization" -eq 0 ]; then
            sd_filled_blocks=0
          elif [ "$sd_utilization" -eq 100 ]; then
            sd_filled_blocks=10
          else sd_filled_blocks=$(((sd_utilization * 10 + 50) / 100)); fi
          [ "$sd_filled_blocks" -lt 0 ] && sd_filled_blocks=0
          [ "$sd_filled_blocks" -gt 10 ] && sd_filled_blocks=10
          sd_empty_blocks=$((10 - sd_filled_blocks))

          sd_progress_bar=" "
          j=0
          while [ $j -lt $sd_filled_blocks ]; do
            sd_progress_bar="${sd_progress_bar}▓"
            j=$((j + 1))
          done
          j=0
          while [ $j -lt $sd_empty_blocks ]; do
            sd_progress_bar="${sd_progress_bar}░"
            j=$((j + 1))
          done
        else
          sd_progress_bar=""
        fi

        sd_reset_time_display=""
        if [ "$show_weekly_reset" = "1" ] && [ -n "$sd_resets_at" ] && [ "$sd_resets_at" != "null" ]; then
          sd_iso_time=$(echo "$sd_resets_at" | sed 's/\.[0-9]*Z$//')
          sd_epoch=$(date -ju -f "%Y-%m-%dT%H:%M:%S" "$sd_iso_time" "+%s" 2>/dev/null)

          if [ -n "$sd_epoch" ]; then
            time_format=$(defaults read -g AppleICUForce24HourTime 2>/dev/null)
            if [ "$time_format" = "1" ]; then
              sd_reset_time=$(date -r "$sd_epoch" "+%a %H:%M" 2>/dev/null)
            else sd_reset_time=$(date -r "$sd_epoch" "+%a %I:%M %p" 2>/dev/null); fi
            [ -n "$sd_reset_time" ] && sd_reset_time_display=$(printf " → Reset: %s" "$sd_reset_time")
          fi
        fi

        weekly_usage_text="${sd_usage_color}Weekly:  ${sd_utilization}%${sd_progress_bar}${sd_reset_time_display}${RESET}"
      else
        weekly_usage_text="${YELLOW}Weekly:  ~${RESET}"
      fi
    fi
  else
    if [ "$show_usage" = "1" ]; then usage_text="${YELLOW}Session: ~${RESET}"; fi
    if [ "$show_weekly_usage" = "1" ]; then weekly_usage_text="${YELLOW}Weekly:  ~${RESET}"; fi
  fi
fi

line1=""
line2=""
line3=""
separator="${GRAY} │ ${RESET}"

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

if [ -n "$usage_text" ]; then
  [ -n "$line2" ] && line2="${line2}${separator}"
  line2="${line2}${usage_text}"
fi

if [ -n "$weekly_usage_text" ]; then
  [ -n "$line3" ] && line3="${line3}${separator}"
  line3="${line3}${weekly_usage_text}"
fi

printf "%s\n" "$line1"
printf "%s\n" "$line2"
if [ -n "$line3" ]; then
  printf "%s\n" "$line3"
fi
