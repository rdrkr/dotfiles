#!/usr/bin/env node

/**
 * Claude Code Status Line Command
 *
 * This script generates a formatted status line for the Claude CLI.
 * It displays account info, working directory, active model, git branch,
 * and usage statistics (session and weekly).
 *
 * Configuration:
 *   Settings are read from ~/.claude/statusline-config.txt
 */

/*
Test Snippet (Copy-Pasteable):

cat << 'EOF' | node ~/.claude/statusline-command.js
{
  "cwd": "/current/working/directory",
  "session_id": "abc123...",
  "transcript_path": "/path/to/transcript.jsonl",
  "model": {
    "id": "claude-opus-4-6",
    "display_name": "Opus"
  },
  "workspace": {
    "current_dir": "/current/working/directory",
    "project_dir": "/original/project/directory"
  },
  "version": "1.0.80",
  "output_style": {
    "name": "default"
  },
  "cost": {
    "total_cost_usd": 0.01234,
    "total_duration_ms": 45000,
    "total_api_duration_ms": 2300,
    "total_lines_added": 156,
    "total_lines_removed": 23
  },
  "context_window": {
    "total_input_tokens": 15234,
    "total_output_tokens": 4521,
    "context_window_size": 200000,
    "used_percentage": 8,
    "remaining_percentage": 92,
    "current_usage": {
      "input_tokens": 8500,
      "output_tokens": 1200,
      "cache_creation_input_tokens": 5000,
      "cache_read_input_tokens": 2000
    }
  },
  "exceeds_200k_tokens": false,
  "vim": {
    "mode": "NORMAL"
  },
  "agent": {
    "name": "security-reviewer"
  },
  "worktree": {
    "name": "my-feature",
    "path": "/path/to/.claude/worktrees/my-feature",
    "branch": "worktree-my-feature",
    "original_cwd": "/path/to/project",
    "original_branch": "main"
  }
}
EOF
*/

import { existsSync, readFileSync } from 'fs';
import { join, basename } from 'path';
import { execSync } from 'child_process';

const configPath = join(process.env.HOME, '.claude/statusline-config.txt');
const config = {
  SHOW_ACCOUNT: 1,
  SHOW_DIRECTORY: 1,
  SHOW_MODEL: 1,
  SHOW_BRANCH: 1,
  SHOW_USAGE: 1,
  SHOW_PROGRESS_BAR: 1,
  SHOW_RESET_TIME: 1,
  SHOW_WEEKLY_USAGE: 1,
  SHOW_WEEKLY_PROGRESS_BAR: 1,
  SHOW_WEEKLY_RESET_TIME: 1,
  COLORFUL_USAGE: 0
};

if (existsSync(configPath)) {
  const content = readFileSync(configPath, 'utf8');
  content.split('\n').forEach(line => {
    const match = line.match(/^([A-Z_]+)=(.*)$/);
    if (match) {
      config[match[1]] = parseInt(match[2], 10);
    }
  });
}

const show_account = config.SHOW_ACCOUNT;
const show_dir = config.SHOW_DIRECTORY;
const show_model = config.SHOW_MODEL;
const show_branch = config.SHOW_BRANCH;
const show_usage = config.SHOW_USAGE;
const show_bar = config.SHOW_PROGRESS_BAR;
const show_reset = config.SHOW_RESET_TIME;
const show_weekly_usage = config.SHOW_WEEKLY_USAGE;
const show_weekly_bar = config.SHOW_WEEKLY_PROGRESS_BAR;
const show_weekly_reset = config.SHOW_WEEKLY_RESET_TIME;
const colorful_usage = config.COLORFUL_USAGE;

let inputStr = '';
try {
  inputStr = readFileSync(0, 'utf8');
} catch (e) {
  // ignoring errors
}

let current_dir = '';
const dirMatch = inputStr.match(/"current_dir":"([^"]*)"/);
if (dirMatch) {
  current_dir = basename(dirMatch[1]);
}

let model_name = '';
try {
  const parsed = JSON.parse(inputStr);
  if (parsed && parsed.model && parsed.model.display_name) {
    model_name = parsed.model.display_name;
  }
} catch (e) {
  // Not valid JSON or field missing
}

const BLUE = '\x1b[0;34m';
const GREEN = '\x1b[0;32m';
const GRAY = '\x1b[0;90m';
const YELLOW = '\x1b[0;33m';
const PURPLE = '\x1b[0;35m';
const RESET = '\x1b[0m';

const LEVEL_1 = '\x1b[38;5;22m';
const LEVEL_2 = '\x1b[38;5;28m';
const LEVEL_3 = '\x1b[38;5;34m';
const LEVEL_4 = '\x1b[38;5;100m';
const LEVEL_5 = '\x1b[38;5;142m';
const LEVEL_6 = '\x1b[38;5;178m';
const LEVEL_7 = '\x1b[38;5;172m';
const LEVEL_8 = '\x1b[38;5;166m';
const LEVEL_9 = '\x1b[38;5;160m';
const LEVEL_10 = '\x1b[38;5;124m';

const separator = `${GRAY} │ ${RESET}`;

const seqPath = join(process.env.HOME, '.claude-switch-backup/sequence.json');
let sequenceData = null;
if (existsSync(seqPath)) {
  try {
    sequenceData = JSON.parse(readFileSync(seqPath, 'utf8'));
  } catch (e) { }
}

let account_text = '';
if (show_account === 1 && sequenceData) {
  const active_account = sequenceData.activeAccountNumber;
  if (active_account && sequenceData.accounts && sequenceData.accounts[active_account]) {
    const email = sequenceData.accounts[active_account].email;
    if (email && email !== 'null') {
      const parts = email.split(/[@.]/);
      if (parts.length > 1) {
        const domain = parts[1];
        account_text = `${BLUE}${active_account}-${domain}${RESET}`;
      }
    }
  }
}

let dir_text = '';
if (show_dir === 1 && current_dir) {
  dir_text = `${YELLOW}${current_dir}${RESET}`;
}

let model_text = '';
if (show_model === 1 && model_name) {
  model_text = `${PURPLE}${model_name}${RESET}`;
}

let branch_text = '';
if (show_branch === 1) {
  try {
    execSync('git rev-parse --git-dir', { stdio: 'ignore' });
    const branch = execSync('git branch --show-current 2>/dev/null').toString().trim();
    if (branch) {
      branch_text = `${GREEN}⎇ ${branch}${RESET}`;
    }
  } catch (e) { }
}

let line1_parts = [];
if (account_text) line1_parts.push(account_text);
if (dir_text) line1_parts.push(dir_text);
if (model_text) line1_parts.push(model_text);
if (branch_text) line1_parts.push(branch_text);
let line1_str = line1_parts.join(separator);

function format_usage_str(util, resets_at, is_weekly, acc_prefix, acc_color, connector) {
  let label = is_weekly ? 'w' : 's';
  let bar_flag = is_weekly ? show_weekly_bar : show_bar;
  let reset_flag = is_weekly ? show_weekly_reset : show_reset;

  let prefix_part = '';
  if (acc_prefix) {
    prefix_part = `${GRAY}${connector || '⎿'} ${RESET}${acc_color}${acc_prefix}${RESET} `;
  }

  if (util !== null && util !== undefined && util !== 'ERROR' && /^\d+$/.test(util.trim())) {
    let utilNum = parseInt(util.trim(), 10);
    let usage_color = '';

    if (colorful_usage === 1) {
      if (utilNum <= 10) usage_color = LEVEL_1;
      else if (utilNum <= 20) usage_color = LEVEL_2;
      else if (utilNum <= 30) usage_color = LEVEL_3;
      else if (utilNum <= 40) usage_color = LEVEL_4;
      else if (utilNum <= 50) usage_color = LEVEL_5;
      else if (utilNum <= 60) usage_color = LEVEL_6;
      else if (utilNum <= 70) usage_color = LEVEL_7;
      else if (utilNum <= 80) usage_color = LEVEL_8;
      else if (utilNum <= 90) usage_color = LEVEL_9;
      else usage_color = LEVEL_10;
    } else {
      if (utilNum <= 60) usage_color = GRAY;
      else if (utilNum <= 70) usage_color = LEVEL_7;
      else if (utilNum <= 80) usage_color = LEVEL_8;
      else if (utilNum <= 90) usage_color = LEVEL_9;
      else usage_color = LEVEL_10;
    }

    let progress_bar = '';
    if (bar_flag === 1) {
      let filled_blocks = 0;
      if (utilNum === 0) filled_blocks = 0;
      else if (utilNum === 100) filled_blocks = 10;
      else filled_blocks = Math.floor((utilNum * 10 + 50) / 100);

      if (filled_blocks < 0) filled_blocks = 0;
      if (filled_blocks > 10) filled_blocks = 10;
      let empty_blocks = 10 - filled_blocks;

      progress_bar = ' ' + '▓'.repeat(filled_blocks) + '░'.repeat(empty_blocks) + ' ';
    }

    let reset_time_display = '';
    if (reset_flag === 1 && resets_at && resets_at !== 'null' && resets_at.trim() !== '') {
      let time_format = '0';
      try {
        time_format = execSync('defaults read -g AppleICUForce24HourTime 2>/dev/null').toString().trim();
      } catch (e) { }

      let dateObj = new Date(resets_at.trim());
      if (!isNaN(dateObj.getTime())) {
        let is24 = time_format === '1';

        let reset_time = '';
        const dayNames = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
        const pad = n => n.toString().padStart(2, '0');
        const h24 = dateObj.getHours();
        const m = pad(dateObj.getMinutes());
        const h12 = h24 % 12 || 12;
        const ampm = h24 >= 12 ? 'PM' : 'AM';

        if (is_weekly) {
          if (is24) {
            reset_time = `${dayNames[dateObj.getDay()]} ${pad(h24)}:${m}`;
          } else {
            reset_time = `${dayNames[dateObj.getDay()]} ${pad(h12)}:${m} ${ampm}`;
          }
        } else {
          if (is24) {
            reset_time = `${pad(h24)}:${m}`;
          } else {
            reset_time = `${pad(h12)}:${m} ${ampm}`;
          }
        }

        reset_time_display = `→ ${reset_time}`;
      }
    }

    let formatted_util = `${utilNum}%`.padEnd(4, ' ');
    let res = `${prefix_part}${usage_color}${label} ${formatted_util}${progress_bar}`;
    if (reset_time_display) {
      if (!res.endsWith(' ')) res += ' ';
      res += reset_time_display;
    }
    return res + RESET;
  } else {
    return `${prefix_part}${YELLOW}${label} ~   ${RESET}`;
  }
}

let usage_lines = [];

function process_result(swift_result, prefix, p_color, connector) {
  let utilization = 'ERROR';
  let resets_at = '';
  let sd_utilization = 'ERROR';
  let sd_resets_at = '';

  if (swift_result) {
    let parts = swift_result.trim().split('|');
    if (parts.length >= 4) {
      utilization = parts[0];
      resets_at = parts[1];
      sd_utilization = parts[2];
      sd_resets_at = parts[3];
    } else if (parts.length > 0) {
      utilization = parts[0];
      resets_at = parts[1] || '';
      sd_utilization = parts[2] || 'ERROR';
      sd_resets_at = parts[3] || '';
    }
  }

  let acc_line = '';
  if (show_usage === 1) {
    acc_line = format_usage_str(utilization, resets_at, 0, prefix, p_color, connector);
  }

  if (show_weekly_usage === 1) {
    let w_text = format_usage_str(sd_utilization, sd_resets_at, 1, '', '', '');
    if (acc_line) {
      acc_line = `${acc_line}${separator}${w_text}`;
    } else {
      w_text = format_usage_str(sd_utilization, sd_resets_at, 1, prefix, p_color, connector);
      acc_line = w_text;
    }
  }

  if (acc_line) {
    usage_lines.push(acc_line);
  }
}

if (show_usage === 1 || show_weekly_usage === 1) {
  if (sequenceData && sequenceData.activeAccountNumber && sequenceData.sequence) {
    let active_account = sequenceData.activeAccountNumber;
    let sequence = sequenceData.sequence;

    let ordered_accounts = [active_account];
    for (let acc of sequence) {
      if (acc != active_account) {
        ordered_accounts.push(acc);
      }
    }

    let max_len = 0;
    for (let acc of ordered_accounts) {
      let email = sequenceData.accounts[acc] ? sequenceData.accounts[acc].email : '';
      let domain = '';
      if (email && email !== 'null') {
        let parts = email.split(/[@.]/);
        if (parts.length > 1) {
          domain = parts[1];
        }
      }
      let raw_prefix = `${acc}-${domain}`;
      if (raw_prefix.length > max_len) {
        max_len = raw_prefix.length;
      }
    }

    let colors = [BLUE, GREEN, YELLOW, PURPLE];
    let color_idx = 0;
    let num_accounts = ordered_accounts.length;
    let count = 0;

    for (let acc of ordered_accounts) {
      count++;
      let connector = count === num_accounts ? '└─' : '├─';

      let email = sequenceData.accounts[acc] ? sequenceData.accounts[acc].email : '';
      let domain = '';
      if (email && email !== 'null') {
        let parts = email.split(/[@.]/);
        if (parts.length > 1) {
          domain = parts[1];
        }
      }
      let raw_prefix = `${acc}-${domain}`;

      let pad_len = max_len - raw_prefix.length;
      let acc_prefix = pad_len > 0 ? raw_prefix + ' '.repeat(pad_len) : raw_prefix;

      let acc_color = colors[color_idx];
      color_idx = (color_idx + 1) % 4;

      let script_path = acc == active_account
        ? join(process.env.HOME, '.claude/fetch-claude-usage.swift')
        : join(process.env.HOME, `.claude-switch-backup/scripts/.fetch-claude-usage-${acc}-${email}.swift`);

      let swift_result = '';
      if (existsSync(script_path)) {
        try {
          swift_result = execSync(`swift "${script_path}" 2>/dev/null`).toString();
        } catch (e) { }
      } else {
        swift_result = 'ERROR';
      }
      process_result(swift_result, acc_prefix, acc_color, connector);
    }
  } else {
    try {
      let swift_result = execSync(`swift "${join(process.env.HOME, '.claude/fetch-claude-usage.swift')}" 2>/dev/null`).toString();
      process_result(swift_result, '', '', '');
    } catch (e) {
      process_result('', '', '', '');
    }
  }
}

if (line1_str) process.stdout.write(line1_str + RESET + '\n');
for (let line of usage_lines) {
  process.stdout.write(line + RESET + '\n');
}
