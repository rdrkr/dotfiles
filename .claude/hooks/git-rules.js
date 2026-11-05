#!/usr/bin/env node
/**
 * @file Claude Code PreToolUse hook (Bash and PowerShell) that enforces the
 * non-negotiable git rules in ~/.claude/CLAUDE.md before a command runs:
 *
 *   1. A commit message is a single subject line: no body, no trailer.
 *   2. A pull request's title is exactly its branch name, and its body is empty.
 *
 * It also refuses the ways around the global commit-msg hook in
 * ~/.claude/hooks/git (`--no-verify`, overriding `core.hooksPath`).
 *
 * The command is tokenized the way bash or PowerShell would split it, so
 * quoting, `&&` chains, `$(...)`, heredocs and nested `bash -c` /
 * `pwsh -Command` are all seen. Anything it cannot read as a literal value
 * (a variable, a command substitution) is refused rather than guessed at.
 *
 * Reads the hook payload as JSON on stdin; prints a `deny` decision on stdout
 * when a rule is broken, and nothing otherwise.
 */
'use strict';

const { execFileSync } = require('child_process');
const os = require('os');
const path = require('path');

/**
 * One shell word after quote removal.
 * @typedef {object} Token
 * @property {string} value The word's text with quotes and escapes resolved.
 * @property {boolean} dynamic True when the shell would expand part of it at
 *   run time (variables, `$(...)`, backticks), so `value` is not what runs.
 * @property {boolean} quoted True when any part of the word was quoted.
 * @property {boolean} [op] True for an operator token such as `<<` or `&`.
 */

/**
 * One simple command: the words between two command separators.
 * @typedef {object} Segment
 * @property {Token[]} tokens The command's words, in order.
 */

/**
 * The result of tokenizing a command string.
 * @typedef {object} Parsed
 * @property {Segment[]} segments The simple commands, in order.
 * @property {{text: string, dialect: string}[]} nested Command strings found
 *   inside `$(...)`, `@(...)` or backticks, to be checked in turn.
 */

/**
 * Mutable state carried across the commands of one tool call.
 * @typedef {object} Context
 * @property {string} cwd The working directory the next command runs in,
 *   updated by `cd` / `Set-Location`.
 * @property {string[]} violations Human-readable reasons the call is refused.
 * @property {number} depth Nesting depth of `bash -c` style re-parsing.
 */

/** Maximum depth of nested shells (`bash -c "pwsh -c ..."`) that are re-parsed. */
const MAX_DEPTH = 6;

/** Words that may precede the real command name and are skipped over. */
const PREFIX_WORDS = new Set([
  'command', 'builtin', 'exec', 'env', 'sudo', 'time', 'nohup', 'then', 'do',
  'else', 'if', 'elif', 'while', 'until', '!', '{', '}', '(', ')',
]);

/** Shells whose `-c` argument is itself a command string. */
const POSIX_SHELLS = new Set(['bash', 'sh', 'zsh', 'dash', 'ksh']);

/** PowerShell executables whose `-Command` argument is a command string. */
const POWERSHELLS = new Set(['pwsh', 'powershell']);

/** `git commit` long options that take a separate value when not given `=`. */
const COMMIT_LONG_WITH_VALUE = new Set([
  '--message', '--file', '--template', '--reuse-message', '--reedit-message',
  '--fixup', '--squash', '--trailer', '--author', '--date', '--cleanup',
  '--pathspec-from-file',
]);

/** `git commit` short options that take a value (attached or the next word). */
const COMMIT_SHORT_WITH_VALUE = 'mFcCt';

/** `git` options before the subcommand that take a separate value. */
const GIT_GLOBAL_WITH_VALUE = new Set([
  '-C', '-c', '--git-dir', '--work-tree', '--namespace', '--super-prefix',
  '--config-env', '--exec-path', '--list-cmds', '--attr-source',
]);

/** `gh pr create` / `gh pr edit` flags that take a value. */
const GH_PR_WITH_VALUE = new Set([
  '-t', '--title', '-b', '--body', '-F', '--body-file', '-H', '--head',
  '-B', '--base', '-a', '--assignee', '-l', '--label', '-m', '--milestone',
  '-p', '--project', '-r', '--reviewer', '-R', '--repo', '-T', '--template',
  '--add-assignee', '--remove-assignee', '--add-label', '--remove-label',
  '--add-project', '--remove-project', '--add-reviewer', '--remove-reviewer',
]);

/** `gh pr` flags that fill or edit the title or body some other way. */
const GH_PR_FORBIDDEN = new Map([
  ['-F', 'the body must be empty: use --body "" instead of --body-file'],
  ['--body-file', 'the body must be empty: use --body "" instead of --body-file'],
  ['-f', '--fill writes a title and body from the commits'],
  ['--fill', '--fill writes a title and body from the commits'],
  ['--fill-first', '--fill-first writes a title and body from the first commit'],
  ['--fill-verbose', '--fill-verbose writes a title and body from the commits'],
  ['-T', '--template fills the body from a template'],
  ['--template', '--template fills the body from a template'],
  ['-w', '--web opens a form where the title and body can be anything'],
  ['--web', '--web opens a form where the title and body can be anything'],
  ['-e', '--editor opens an editor for the title and body'],
  ['--editor', '--editor opens an editor for the title and body'],
  ['--recover', '--recover restores a previously typed title and body'],
]);

/**
 * Splits a command string into simple commands and words, following the
 * quoting rules of the given shell.
 * @param {string} text The command string.
 * @param {'bash'|'powershell'} dialect Which shell's quoting rules apply.
 * @returns {Parsed} The commands found and any nested command strings.
 */
function tokenize(text, dialect) {
  const ps = dialect === 'powershell';
  const esc = ps ? '`' : '\\';
  const n = text.length;
  /** @type {Segment[]} */
  const segments = [];
  const nested = [];
  /** @type {Token[]} */
  let tokens = [];
  /** @type {Token|null} */
  let cur = null;
  /** @type {{delim: string, dash: boolean}[]} */
  let heredocs = [];
  let i = 0;

  /** Starts a new word if none is in progress. */
  const startTok = () => {
    if (!cur) cur = { value: '', dynamic: false, quoted: false };
  };
  /** Ends the word in progress, if any. */
  const endTok = () => {
    if (cur) tokens.push(cur);
    cur = null;
  };
  /** Ends the simple command in progress, if it has any words. */
  const endSeg = () => {
    endTok();
    if (tokens.length) segments.push({ tokens });
    tokens = [];
  };

  /**
   * Finds the parenthesis matching the one at `start`, skipping quoted text.
   * @param {number} start Index of an opening `(`.
   * @returns {number} Index of the matching `)`, or the end of the text.
   */
  const matchParen = (start) => {
    let depth = 0;
    for (let j = start; j < n; j++) {
      const ch = text[j];
      if (ch === "'" || ch === '"') {
        const close = text.indexOf(ch, j + 1);
        if (close < 0) return n;
        j = close;
      } else if (ch === '(') {
        depth++;
      } else if (ch === ')' && --depth === 0) {
        return j;
      }
    }
    return n;
  };

  /**
   * Reads a `$` expansion at `i` into the current word.
   * @param {number} at Index of the `$`.
   * @param {boolean} inDouble True inside double quotes.
   * @returns {number} Index just after the expansion.
   */
  const readDollar = (at, inDouble) => {
    startTok();
    const next = text[at + 1];
    if (next === '(') {
      const close = matchParen(at + 1);
      nested.push({ text: text.slice(at + 2, close), dialect });
      cur.dynamic = true;
      cur.value += '$(...)';
      return close + 1;
    }
    if (next === '{') {
      const close = text.indexOf('}', at);
      cur.dynamic = true;
      cur.value += '${...}';
      return close < 0 ? n : close + 1;
    }
    if (!ps && !inDouble && next === "'") {
      cur.quoted = true;
      let j = at + 2;
      const map = { n: '\n', r: '\r', t: '\t', '\\': '\\', "'": "'", '"': '"' };
      while (j < n && text[j] !== "'") {
        if (text[j] === '\\' && j + 1 < n) {
          cur.value += map[text[j + 1]] ?? text[j + 1];
          j += 2;
        } else {
          cur.value += text[j++];
        }
      }
      return j + 1;
    }
    if (next !== undefined && /[A-Za-z0-9_?@#!*$-]/.test(next)) {
      let j = at + 1;
      if (/[?@#!*$-]/.test(next)) j++;
      else while (j < n && /[A-Za-z0-9_:]/.test(text[j])) j++;
      cur.dynamic = true;
      cur.value += text.slice(at, j);
      return j;
    }
    cur.value += '$';
    return at + 1;
  };

  /**
   * Reads a bash backtick command substitution at `at` into the current word.
   * @param {number} at Index of the opening backtick.
   * @returns {number} Index just after the closing backtick.
   */
  const readBacktick = (at) => {
    startTok();
    let j = at + 1;
    while (j < n && text[j] !== '`') j += text[j] === '\\' ? 2 : 1;
    nested.push({ text: text.slice(at + 1, j), dialect });
    cur.dynamic = true;
    cur.value += '`...`';
    return j + 1;
  };

  /**
   * Skips the bodies of the heredocs opened on the line that just ended.
   * @param {number} at Index of the first character of the next line.
   * @returns {number} Index of the first line after the last heredoc body.
   */
  const skipHeredocs = (at) => {
    let j = at;
    for (const { delim, dash } of heredocs) {
      while (j < n) {
        let end = text.indexOf('\n', j);
        if (end < 0) end = n;
        let line = text.slice(j, end).replace(/\r$/, '');
        if (dash) line = line.replace(/^\t+/, '');
        j = end + 1;
        if (line === delim) break;
      }
    }
    heredocs = [];
    return Math.min(j, n);
  };

  while (i < n) {
    const c = text[i];

    if (c === esc && text[i + 1] === '\n') { i += 2; continue; }
    if (c === esc && text[i + 1] === '\r' && text[i + 2] === '\n') { i += 3; continue; }

    if (c === '\n' || c === '\r') {
      endSeg();
      i += c === '\r' && text[i + 1] === '\n' ? 2 : 1;
      if (heredocs.length) i = skipHeredocs(i);
      continue;
    }
    if (!cur && c === '#') {
      while (i < n && text[i] !== '\n') i++;
      continue;
    }
    if (c === ' ' || c === '\t') { endTok(); i++; continue; }
    if (c === ';') { endSeg(); i++; continue; }
    if (c === '|') { endSeg(); i += text[i + 1] === '|' ? 2 : 1; continue; }
    if (c === '&') {
      const prev = text[i - 1];
      if (prev === '>' || prev === '<' || text[i + 1] === '>') {
        startTok(); cur.value += c; i++; continue;
      }
      if (text[i + 1] === '&') { endSeg(); i += 2; continue; }
      if (ps) {
        endTok();
        tokens.push({ value: '&', dynamic: false, quoted: false, op: true });
      } else {
        endSeg();
      }
      i++;
      continue;
    }
    if (c === '(' || c === ')' || ((c === '{' || c === '}') && !cur)) {
      endSeg(); i++; continue;
    }

    if (!ps && c === '<' && text[i + 1] === '<') {
      endTok();
      if (text[i + 2] === '<') {
        tokens.push({ value: '<<<', dynamic: false, quoted: false, op: true });
        i += 3;
        continue;
      }
      i += 2;
      const dash = text[i] === '-';
      if (dash) i++;
      while (text[i] === ' ' || text[i] === '\t') i++;
      let delim = '';
      while (i < n && !/[\s;&|<>()]/.test(text[i])) {
        if (text[i] !== "'" && text[i] !== '"' && text[i] !== '\\') delim += text[i];
        i++;
      }
      heredocs.push({ delim, dash });
      tokens.push({ value: '<<', dynamic: true, quoted: false, op: true });
      continue;
    }

    if (ps && !cur && c === '@' && (text[i + 1] === "'" || text[i + 1] === '"')
        && /^[ \t]*\r?\n/.test(text.slice(i + 2))) {
      const q = text[i + 1];
      const bodyStart = text.indexOf('\n', i) + 1;
      const closeRe = new RegExp('\\r?\\n' + q + '@');
      const m = closeRe.exec(text.slice(bodyStart - 1));
      const bodyEnd = m ? bodyStart - 1 + m.index : n;
      startTok();
      cur.quoted = true;
      cur.value += text.slice(bodyStart, bodyEnd).replace(/\r/g, '');
      if (q === '"' && /[$`]/.test(cur.value)) cur.dynamic = true;
      i = m ? bodyEnd + m[0].length : n;
      continue;
    }
    if (ps && c === '@' && text[i + 1] === '(') {
      startTok();
      const close = matchParen(i + 1);
      nested.push({ text: text.slice(i + 2, close), dialect });
      cur.dynamic = true;
      cur.value += '@(...)';
      i = close + 1;
      continue;
    }

    if (c === "'") {
      startTok();
      cur.quoted = true;
      i++;
      while (i < n) {
        if (text[i] === "'") {
          if (ps && text[i + 1] === "'") { cur.value += "'"; i += 2; continue; }
          break;
        }
        cur.value += text[i++];
      }
      i++;
      continue;
    }
    if (c === '"') {
      startTok();
      cur.quoted = true;
      i++;
      while (i < n) {
        const d = text[i];
        if (d === '"') {
          if (ps && text[i + 1] === '"') { cur.value += '"'; i += 2; continue; }
          break;
        }
        if (d === esc && i + 1 < n) {
          const e = text[i + 1];
          if (ps) {
            cur.value += { n: '\n', r: '\r', t: '\t', 0: '\0' }[e] ?? e;
          } else if ('"\\$`'.includes(e)) {
            cur.value += e;
          } else if (e !== '\n') {
            cur.value += d + e;
          }
          i += 2;
          continue;
        }
        if (d === '$') { i = readDollar(i, true); continue; }
        if (!ps && d === '`') { i = readBacktick(i); continue; }
        cur.value += d;
        i++;
      }
      i++;
      continue;
    }

    if (c === '$') { i = readDollar(i, false); continue; }
    if (!ps && c === '`') { i = readBacktick(i); continue; }
    if (c === esc && i + 1 < n) {
      startTok();
      cur.value += text[i + 1];
      i += 2;
      continue;
    }

    startTok();
    cur.value += c;
    i++;
  }
  endSeg();
  return { segments, nested };
}

/**
 * Normalizes a command word to a bare program name: no directory, no
 * extension, lowercase (`C:\Program Files\Git\cmd\git.EXE` → `git`).
 * @param {string} word The command word.
 * @returns {string} The program name.
 */
function programName(word) {
  return path.basename(word.replace(/\\/g, '/')).toLowerCase().replace(/\.(exe|cmd|bat|ps1)$/, '');
}

/**
 * Drops the words in front of the real command: environment assignments,
 * `sudo`, `env`, PowerShell's `&` call operator and the like.
 * @param {Token[]} tokens The simple command's words.
 * @returns {Token[]} The words starting at the command name.
 */
function commandWords(tokens) {
  let k = 0;
  while (k < tokens.length) {
    const t = tokens[k];
    if (t.op && t.value === '&') { k++; continue; }
    if (!t.quoted && /^[A-Za-z_][A-Za-z0-9_]*=/.test(t.value)) { k++; continue; }
    if (PREFIX_WORDS.has(t.value)) { k++; continue; }
    break;
  }
  return tokens.slice(k);
}

/**
 * Splits `--name=value` into its name and value.
 * @param {Token} tok A word starting with `--`.
 * @returns {{name: string, value: (Token|undefined)}} The option name, and its
 *   attached value as a token when `=` was present.
 */
function splitLong(tok) {
  const eq = tok.value.indexOf('=');
  if (eq < 0) return { name: tok.value, value: undefined };
  return {
    name: tok.value.slice(0, eq),
    value: { value: tok.value.slice(eq + 1), dynamic: tok.dynamic, quoted: tok.quoted },
  };
}

/**
 * Returns the branch checked out in a directory.
 * @param {string} cwd The working directory.
 * @returns {string|null} The branch name, or null when it cannot be read
 *   (not a repository, detached HEAD).
 */
function currentBranch(cwd) {
  try {
    return execFileSync('git', ['symbolic-ref', '--short', 'HEAD'], {
      cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], timeout: 10000,
    }).trim() || null;
  } catch {
    return null;
  }
}

/**
 * Returns the head branch of an existing pull request.
 * @param {string} cwd The working directory, for gh's repository detection.
 * @param {string|undefined} pr The PR number, URL or branch, as `gh pr edit` takes it.
 * @param {string|undefined} repo The `--repo` value, if one was given.
 * @returns {string|null} The PR's head branch, or null when gh cannot say.
 */
function prHeadBranch(cwd, pr, repo) {
  const args = ['pr', 'view'];
  if (pr) args.push(pr);
  if (repo) args.push('--repo', repo);
  args.push('--json', 'headRefName', '--jq', '.headRefName');
  try {
    return execFileSync('gh', args, {
      cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'], timeout: 20000,
    }).trim() || null;
  } catch {
    return null;
  }
}

/**
 * Checks the arguments of `git commit` against rule 1.
 * @param {Token[]} args The words after `commit`.
 * @param {Context} ctx Where violations are recorded.
 */
function checkCommit(args, ctx) {
  const v = (msg) => ctx.violations.push(`git commit: ${msg}`);
  /** @type {(Token|undefined)[]} */
  const messages = [];
  let amend = false;
  let noEdit = false;
  let fixup = false;

  for (let k = 0; k < args.length; k++) {
    const t = args[k];
    if (t.op) continue;
    if (t.value === '--') break;

    if (t.value.startsWith('--')) {
      const split = splitLong(t);
      const name = split.name;
      let value = split.value;
      if (!value && COMMIT_LONG_WITH_VALUE.has(name)) value = args[++k];
      switch (name) {
        case '--message': messages.push(value); break;
        case '--no-verify': v('--no-verify skips the commit-msg hook that enforces the subject-only rule'); break;
        case '--file':
        case '--template': v(`${name} is not allowed; pass the subject with one -m "<subject>"`); break;
        case '--reuse-message':
        case '--reedit-message': v(`${name} copies another commit's message, which can carry a body`); break;
        case '--edit': v('--edit opens an editor; pass the subject with one -m "<subject>"'); break;
        case '--trailer': v('--trailer adds a trailer; trailers are not allowed'); break;
        case '--signoff': v('--signoff adds a Signed-off-by trailer; trailers are not allowed'); break;
        case '--squash': v('--squash builds a message with a body from the squashed commit'); break;
        case '--fixup':
          fixup = true;
          if (value && /^(amend|reword):/.test(value.value)) v(`--fixup=${value.value} opens an editor for a new message`);
          break;
        case '--amend': amend = true; break;
        case '--no-edit': noEdit = true; break;
        default: break;
      }
      continue;
    }

    if (t.value.startsWith('-') && t.value.length > 1) {
      for (let p = 1; p < t.value.length; p++) {
        const ch = t.value[p];
        if (COMMIT_SHORT_WITH_VALUE.includes(ch)) {
          const rest = t.value.slice(p + 1);
          const value = rest ? { value: rest, dynamic: t.dynamic, quoted: t.quoted } : args[++k];
          if (ch === 'm') messages.push(value);
          else if (ch === 'F') v('-F reads the message from a file; pass the subject with one -m "<subject>"');
          else if (ch === 't') v('-t uses a message template; pass the subject with one -m "<subject>"');
          else v(`-${ch} copies another commit's message, which can carry a body`);
          break;
        }
        if (ch === 'S' || ch === 'u') break;
        if (ch === 'n') v('-n (--no-verify) skips the commit-msg hook that enforces the subject-only rule');
        if (ch === 's') v('-s (--signoff) adds a Signed-off-by trailer; trailers are not allowed');
        if (ch === 'e') v('-e (--edit) opens an editor; pass the subject with one -m "<subject>"');
      }
    }
  }

  if (messages.length === 0) {
    if (!(amend && noEdit) && !fixup) {
      v('pass the subject with exactly one -m "<subject>" (without -m, git opens an editor)');
    }
    return;
  }
  if (messages.length > 1) {
    v(`${messages.length} -m options; every -m after the first becomes a body paragraph. Use exactly one`);
    return;
  }
  const msg = messages[0];
  if (!msg) {
    v('-m has no value');
  } else if (msg.dynamic) {
    v('the message must be a literal string. $(...), variables, backticks and heredocs are not allowed, as they can carry a body or trailers');
  } else if (/[\r\n]/.test(msg.value)) {
    v('the message has more than one line; it must be a subject line only, with no body and no trailer');
  } else if (!msg.value.trim()) {
    v('the message is empty');
  } else if (/^\s*[A-Za-z][A-Za-z-]*-by\s*:/i.test(msg.value) || /^\s*Claude-Session\s*:/i.test(msg.value)) {
    v('the subject is a trailer line; trailers are not allowed');
  }
}

/**
 * Checks `git` commands: rule 1 for `git commit`, and refuses anything that
 * would stop the global commit-msg hook from running.
 * @param {Token[]} words The command's words, starting with `git`.
 * @param {Context} ctx Working directory and violation list.
 */
function checkGit(words, ctx) {
  let k = 1;
  while (k < words.length) {
    const t = words[k];
    const { name, value } = t.value.startsWith('--') ? splitLong(t) : { name: t.value, value: undefined };
    if (name === '-c' || name === '--config-env') {
      const kv = value ? value.value : (words[k + 1] || { value: '' }).value;
      if (/^core\.hookspath\b/i.test(kv)) {
        ctx.violations.push('git -c core.hooksPath=... would skip the global commit-msg hook');
      }
    }
    if (GIT_GLOBAL_WITH_VALUE.has(name) && !value) { k += 2; continue; }
    if (t.value.startsWith('-')) { k++; continue; }
    break;
  }
  const sub = words[k] ? words[k].value : '';
  const args = words.slice(k + 1);

  if (sub === 'commit') {
    checkCommit(args, ctx);
  } else if (['merge', 'pull', 'cherry-pick', 'revert', 'am', 'rebase'].includes(sub)) {
    if (args.some((a) => a.value === '--no-verify')) {
      ctx.violations.push(`git ${sub}: --no-verify skips the commit-msg hook that enforces the subject-only rule`);
    }
  } else if (sub === 'config') {
    const values = args.map((a) => a.value);
    const touchesHooksPath = values.some((x) => /^core\.hookspath$/i.test(x));
    const readOnly = values.some((x) => ['--get', '--get-all', '--get-regexp', 'get', '--list', '-l', 'list'].includes(x));
    if (touchesHooksPath && !readOnly) {
      ctx.violations.push('git config core.hooksPath: changing it would skip the global commit-msg hook');
    }
  }
}

/**
 * Checks `gh pr create` and `gh pr edit` against rule 2.
 * @param {Token[]} args The words after `create` / `edit`.
 * @param {Context} ctx Working directory and violation list.
 * @param {boolean} isEdit True for `gh pr edit`, where title and body are optional.
 */
function checkPr(args, ctx, isEdit) {
  const cmd = isEdit ? 'gh pr edit' : 'gh pr create';
  const v = (msg) => ctx.violations.push(`${cmd}: ${msg}`);
  /** @type {Object<string, Token|undefined>} */
  const found = {};
  let positional;

  for (let k = 0; k < args.length; k++) {
    const t = args[k];
    if (t.op) continue;
    let name;
    let value;
    if (t.value.startsWith('--')) {
      ({ name, value } = splitLong(t));
    } else if (/^-[A-Za-z]/.test(t.value)) {
      name = t.value.slice(0, 2);
      if (t.value.length > 2) {
        value = { value: t.value.slice(2).replace(/^=/, ''), dynamic: t.dynamic, quoted: t.quoted };
      }
    } else {
      if (positional === undefined) positional = t.value;
      continue;
    }
    if (GH_PR_FORBIDDEN.has(name)) v(GH_PR_FORBIDDEN.get(name));
    if (!value && GH_PR_WITH_VALUE.has(name)) value = args[++k];
    if (name === '-t' || name === '--title') found.title = value;
    if (name === '-b' || name === '--body') found.body = value;
    if (name === '-H' || name === '--head') found.head = value;
    if (name === '-R' || name === '--repo') found.repo = value;
  }

  const hasTitle = 'title' in found;
  const hasBody = 'body' in found;
  if (!isEdit && !hasTitle) v('pass --title "<branch name>"; the title must be exactly the branch name');
  if (!isEdit && !hasBody) v('pass --body ""; the body must be empty');

  if (hasBody) {
    const body = found.body;
    if (!body || body.dynamic || body.value !== '') v('the body must be empty: --body ""');
  }

  if (hasTitle) {
    const title = found.title;
    if (!title) {
      v('--title has no value');
    } else if (title.dynamic) {
      v('the title must be the branch name as a literal string, not a variable or $(...)');
    } else {
      let branch;
      if (isEdit) branch = prHeadBranch(ctx.cwd, positional, found.repo && found.repo.value);
      else if (found.head && !found.head.dynamic) branch = found.head.value.replace(/^[^:]+:/, '');
      else branch = currentBranch(ctx.cwd);
      if (!branch) {
        v(isEdit
          ? 'could not read the pull request\'s head branch to check the title against'
          : 'could not read the current branch to check the title against; pass --head <branch>');
      } else if (title.value !== branch) {
        v(`the title must be exactly the branch name "${branch}", not "${title.value}"`);
      }
    }
  }
}

/**
 * Checks `gh api` calls that would create or change a pull request directly,
 * which would bypass the `gh pr create` checks.
 * @param {Token[]} args The words after `api`.
 * @param {Context} ctx Where violations are recorded.
 */
function checkGhApi(args, ctx) {
  const values = args.map((a) => a.value);
  const prEndpoint = values.some((x) => /(^|\/)pulls(\/\d+)?\/?$/.test(x));
  const sendsData = values.some((x) => /^(-f|-F|--field|--raw-field|--input)/.test(x))
    || values.some((x, k) => /^(-X|--method)$/.test(x) && /^(POST|PATCH|PUT)$/i.test(values[k + 1] || ''))
    || values.some((x) => /^(-X|--method=)(POST|PATCH|PUT)$/i.test(x));
  if (prEndpoint && sendsData) {
    ctx.violations.push('gh api: create or edit pull requests with gh pr create / gh pr edit, so the title and body rules can be checked');
  }
  if (values.includes('graphql') && values.some((x) => /(create|update)PullRequest/.test(x))) {
    ctx.violations.push('gh api graphql: create or edit pull requests with gh pr create / gh pr edit, so the title and body rules can be checked');
  }
}

/**
 * Returns the command string a nested shell invocation runs, if any:
 * `bash -c '...'`, `pwsh -Command ...`, `pwsh -EncodedCommand ...`,
 * `cmd /c ...`, `eval ...`, `Invoke-Expression ...`.
 * @param {Token[]} words The command's words, starting with the program.
 * @returns {{text: string, dialect: string}|null} The inner command, or null.
 */
function innerCommand(words) {
  const prog = programName(words[0].value);
  const rest = words.slice(1);
  if (POSIX_SHELLS.has(prog)) {
    const k = rest.findIndex((t) => /^-[a-z]*c[a-z]*$/.test(t.value));
    if (k >= 0 && rest[k + 1]) return { text: rest[k + 1].value, dialect: 'bash' };
    return null;
  }
  if (POWERSHELLS.has(prog)) {
    for (let k = 0; k < rest.length; k++) {
      const f = rest[k].value.toLowerCase();
      if (/^-e(c|n|nc|nco|ncod|ncode|ncoded|ncodedc|ncodedco|ncodedcom|ncodedcomm|ncodedcomma|ncodedcomman|ncodedcommand)?$/.test(f) && rest[k + 1]) {
        try {
          return { text: Buffer.from(rest[k + 1].value, 'base64').toString('utf16le'), dialect: 'powershell' };
        } catch {
          return null;
        }
      }
      if (/^-c(o|om|omm|omma|omman|ommand)?$/.test(f)) {
        return { text: rest.slice(k + 1).map((t) => t.value).join(' '), dialect: 'powershell' };
      }
    }
    return null;
  }
  if (prog === 'cmd') {
    const k = rest.findIndex((t) => /^\/[ck]$/i.test(t.value));
    if (k >= 0) return { text: rest.slice(k + 1).map((t) => t.value).join(' '), dialect: 'bash' };
    return null;
  }
  if (prog === 'eval') return { text: rest.map((t) => t.value).join(' '), dialect: 'bash' };
  if (prog === 'invoke-expression' || prog === 'iex') {
    const parts = rest.filter((t) => !/^-command$/i.test(t.value));
    return { text: parts.map((t) => t.value).join(' '), dialect: 'powershell' };
  }
  return null;
}

/**
 * Applies a `cd` / `Set-Location` / `pushd` to the tracked working directory,
 * so a later `gh pr create` reads the branch of the right repository.
 * @param {Token[]} words The command's words, starting with the program.
 * @param {Context} ctx The context whose `cwd` is updated.
 * @returns {boolean} True when the command was a directory change.
 */
function trackCd(words, ctx) {
  const prog = programName(words[0].value);
  if (!['cd', 'chdir', 'pushd', 'set-location', 'sl', 'push-location'].includes(prog)) return false;
  const target = words.slice(1).find((t) => !t.value.startsWith('-'));
  if (!target || target.dynamic) return true;
  const dir = target.value.replace(/^~(?=$|[\\/])/, os.homedir());
  ctx.cwd = path.resolve(ctx.cwd, dir);
  return true;
}

/**
 * Checks every command in a command string.
 * @param {string} text The command string.
 * @param {'bash'|'powershell'} dialect Which shell runs it.
 * @param {Context} ctx Working directory, violation list and nesting depth.
 */
function analyze(text, dialect, ctx) {
  if (ctx.depth > MAX_DEPTH) return;
  if (/GIT_CONFIG/i.test(text) && /hookspath/i.test(text)) {
    ctx.violations.push('setting core.hooksPath through GIT_CONFIG_* would skip the global commit-msg hook');
  }
  const { segments, nested } = tokenize(text, dialect);
  for (const seg of segments) {
    const words = commandWords(seg.tokens);
    if (!words.length) continue;
    if (trackCd(words, ctx)) continue;
    const prog = programName(words[0].value);
    if (prog === 'git') {
      checkGit(words, ctx);
    } else if (prog === 'gh') {
      const sub = words.slice(1).map((t) => t.value);
      if (sub[0] === 'pr' && (sub[1] === 'create' || sub[1] === 'new')) checkPr(words.slice(3), ctx, false);
      else if (sub[0] === 'pr' && sub[1] === 'edit') checkPr(words.slice(3), ctx, true);
      else if (sub[0] === 'api') checkGhApi(words.slice(2), ctx);
    } else {
      const inner = innerCommand(words);
      if (inner) analyze(inner.text, inner.dialect, { ...ctx, depth: ctx.depth + 1, violations: ctx.violations });
    }
  }
  for (const inner of nested) {
    analyze(inner.text, inner.dialect, { ...ctx, depth: ctx.depth + 1, violations: ctx.violations });
  }
}

/**
 * Prints a PreToolUse `deny` decision carrying the given reasons.
 * @param {string[]} reasons Why the command is refused.
 */
function deny(reasons) {
  const unique = [...new Set(reasons)];
  process.stdout.write(JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      permissionDecision: 'deny',
      permissionDecisionReason:
        'Blocked by ~/.claude/hooks/git-rules.js (the non-negotiable git rules in ~/.claude/CLAUDE.md):\n- '
        + unique.join('\n- '),
    },
  }));
}

/**
 * Entry point: reads the hook payload from stdin and checks the command.
 */
function main() {
  let raw = '';
  process.stdin.setEncoding('utf8');
  process.stdin.on('data', (chunk) => { raw += chunk; });
  process.stdin.on('end', () => {
    let input;
    try {
      input = JSON.parse(raw);
    } catch {
      return;
    }
    const tool = input.tool_name;
    const command = input.tool_input && input.tool_input.command;
    if ((tool !== 'Bash' && tool !== 'PowerShell') || typeof command !== 'string') return;
    if (!/git|gh|hookspath|pwsh|powershell/i.test(command)) return;

    const ctx = { cwd: input.cwd || process.cwd(), violations: [], depth: 0 };
    try {
      analyze(command, tool === 'PowerShell' ? 'powershell' : 'bash', ctx);
    } catch (err) {
      if (/\b(commit|pr|api|hookspath)\b/i.test(command)) {
        ctx.violations.push(`the git rules hook could not parse this command (${err.message}); rewrite it as a plain git or gh command`);
      }
    }
    if (ctx.violations.length) deny(ctx.violations);
  });
}

if (require.main === module) main();

module.exports = { tokenize, analyze };
