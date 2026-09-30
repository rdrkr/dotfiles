#!/usr/bin/env node

/**
 * dotfiles-sync-secrets - the encrypted side channel of dotfiles-sync.
 *
 * Some files the two machines both need can never be committed, e.g.
 * .claude/usage-secrets.json (the claude.ai session keys the status line's
 * usage fetcher reads). They are listed, one repo-relative path per line, in
 * .syncsecrets at the repo root, and must be ignored by git. This helper packs
 * the ones that changed into a bundle encrypted with AES-256-GCM under a key
 * that both clones keep in .git/dotfiles-sync/secrets.key (never committed, never
 * sent), and applies bundles the peer sent. Both scripts/dotfiles-sync.sh and
 * scripts/dotfiles-sync.ps1 call it, so the format has a single implementation;
 * they only move the bundles over Taildrop like any other sync file.
 *
 * Guarantees:
 *   - A bundle only decrypts, and only applies, when it was made with the same
 *     key; a tampered or foreign bundle is rejected as a whole (GCM tag, with
 *     the header, sender and creation time as associated data).
 *   - Only paths listed in the receiving repo's own .syncsecrets are written,
 *     only inside the repo, never through a symlink, and only when git ignores
 *     them. The sender applies the same checks, so a listed file that git
 *     tracks is never packed.
 *   - Per file, the newest modification time wins (the content hash breaks a
 *     tie), so edits on either machine converge and a replayed old bundle
 *     changes nothing.
 *   - The key, bundles and state files are written with mode 0600.
 *
 * Usage (all paths absolute):
 *   dotfiles-sync-secrets.js init    --repo R --state S
 *   dotfiles-sync-secrets.js show-key --repo R --state S
 *   dotfiles-sync-secrets.js set-key --repo R --state S        (key on stdin)
 *   dotfiles-sync-secrets.js status  --repo R --state S
 *   dotfiles-sync-secrets.js pack    --repo R --state S --label L --out FILE [--all]
 *   dotfiles-sync-secrets.js unpack  --repo R --state S --label L FILE
 *
 * Exit codes: 0 done, 1 error, 2 bundle rejected (wrong key or tampered),
 * 3 nothing to send, 4 not configured (no key or no .syncsecrets).
 */

"use strict";

const crypto = require("crypto");
const fs = require("fs");
const path = require("path");
const { spawnSync } = require("child_process");

/** First line of every bundle; also part of the authenticated data. */
const HEADER = "# dotfiles-sync secrets v1";
/** File listing the secret paths, at the repo root. */
const LIST_FILE = ".syncsecrets";
/** Key file name inside the state directory. */
const KEY_FILE = "secrets.key";
/** File recording, per path, the hash of the content last sent or received. */
const STATE_FILE = "secrets-state.json";
/** Largest secret file packed, so a mistaken entry never ships something huge. */
const MAX_FILE_BYTES = 1024 * 1024;

/** Exit codes shared with the calling scripts. */
const EXIT = { OK: 0, ERROR: 1, REJECTED: 2, NOTHING: 3, UNCONFIGURED: 4 };

/**
 * An error carrying the exit code the process should end with.
 */
class SyncError extends Error {
  /**
   * @param {string} message what went wrong
   * @param {number} [code] exit code (default EXIT.ERROR)
   */
  constructor(message, code = EXIT.ERROR) {
    super(message);
    /** @type {number} exit code */
    this.code = code;
  }
}

/**
 * Parses "--name value" options and positional arguments.
 * @param {string[]} argv arguments after the command
 * @returns {{opts: Object<string, (string|boolean)>, rest: string[]}}
 */
function parseArgs(argv) {
  const opts = {};
  const rest = [];
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--all") opts.all = true;
    else if (a.startsWith("--")) {
      if (i + 1 >= argv.length) throw new SyncError(`${a} needs a value`);
      opts[a.slice(2)] = argv[++i];
    } else rest.push(a);
  }
  return { opts, rest };
}

/**
 * Writes a file with mode 0600 via a temporary file and a rename, so readers
 * never see it half written.
 * @param {string} file destination
 * @param {(string|Buffer)} data content
 * @returns {void}
 */
function writePrivate(file, data) {
  const tmp = `${file}.tmp-${process.pid}`;
  fs.writeFileSync(tmp, data, { mode: 0o600 });
  fs.chmodSync(tmp, 0o600);
  fs.renameSync(tmp, file);
}

/**
 * Returns the SHA-256 of a buffer as hex.
 * @param {Buffer} buf
 * @returns {string}
 */
function sha256(buf) {
  return crypto.createHash("sha256").update(buf).digest("hex");
}

/**
 * Parses a base64 key and checks it is 32 bytes.
 * @param {string} text base64 text (surrounding whitespace allowed)
 * @returns {Buffer}
 * @throws {SyncError} when it is not a 32-byte base64 key
 */
function decodeKey(text) {
  const t = text.trim();
  const key = Buffer.from(t, "base64");
  if (!/^[A-Za-z0-9+/]+={0,2}$/.test(t) || key.length !== 32) {
    throw new SyncError("not a dotfiles-sync secrets key (expected 32 bytes of base64)");
  }
  return key;
}

/**
 * Reads this clone's key.
 * @param {string} state state directory
 * @returns {Buffer}
 * @throws {SyncError} (UNCONFIGURED) when there is no key yet
 */
function readKey(state) {
  let text;
  try {
    text = fs.readFileSync(path.join(state, KEY_FILE), "utf8");
  } catch {
    throw new SyncError(
      "no secrets key in this clone: run 'dotfiles-sync secrets init' on one machine and 'dotfiles-sync secrets set-key' on the other",
      EXIT.UNCONFIGURED
    );
  }
  return decodeKey(text);
}

/**
 * Reads the paths listed in .syncsecrets: one per line, "#" comments, blank
 * lines, CRLF line endings and a UTF-8 BOM allowed, a leading "/" dropped.
 * @param {string} repo repo root
 * @returns {string[]} repo-relative paths with forward slashes
 */
function readList(repo) {
  let text;
  try {
    text = fs.readFileSync(path.join(repo, LIST_FILE), "utf8");
  } catch {
    return [];
  }
  const seen = new Set();
  for (let line of text.replace(/^﻿/, "").split(/\r?\n/)) {
    line = line.replace(/#.*/, "").trim().replace(/\\/g, "/").replace(/^\/+/, "");
    if (line) seen.add(line);
  }
  return [...seen];
}

/**
 * Loads the per-path record of what was last sent or received.
 * @param {string} state state directory
 * @returns {Object<string, {sha256: string}>}
 */
function readState(state) {
  try {
    const doc = JSON.parse(fs.readFileSync(path.join(state, STATE_FILE), "utf8"));
    return doc && typeof doc === "object" ? doc : {};
  } catch {
    return {};
  }
}

/**
 * Saves the per-path record.
 * @param {string} state state directory
 * @param {Object<string, {sha256: string}>} doc
 * @returns {void}
 */
function writeState(state, doc) {
  writePrivate(path.join(state, STATE_FILE), JSON.stringify(doc, null, 2) + "\n");
}

/**
 * Checks that a listed path may be read or written as a secret: relative,
 * inside the repo once symlinks are resolved, not itself a symlink, and
 * ignored (therefore untracked) by git.
 * @param {string} repo repo root
 * @param {string} rel repo-relative path
 * @returns {?string} why it may not be used, or null when it may
 */
function unsafeReason(repo, rel) {
  if (path.isAbsolute(rel) || /^[A-Za-z]:/.test(rel) || rel.split("/").some((s) => s === ".." || s === "." || s === "")) {
    return "not a plain repo-relative path";
  }
  if (rel === ".git" || rel.startsWith(".git/")) return "inside .git";
  const full = path.join(repo, rel);
  let realRepo;
  try {
    realRepo = fs.realpathSync(repo);
  } catch {
    return "repo not found";
  }
  // the closest existing ancestor must resolve to somewhere inside the repo
  let dir = path.dirname(full);
  while (!fs.existsSync(dir)) dir = path.dirname(dir);
  const realDir = fs.realpathSync(dir);
  if (realDir !== realRepo && !realDir.startsWith(realRepo + path.sep)) return "outside the repo (symlinked folder)";
  try {
    if (fs.lstatSync(full).isSymbolicLink()) return "a symlink";
  } catch {
    // missing is fine
  }
  const r = spawnSync("git", ["-C", repo, "check-ignore", "-q", "--", rel], { stdio: "ignore", windowsHide: true });
  if (r.status !== 0) return "not ignored by git (it would be committed; add it to .gitignore)";
  return null;
}

/**
 * Encrypts a bundle.
 * @param {Buffer} key 32-byte key
 * @param {string} from sender label
 * @param {object} payload plaintext object
 * @returns {string} bundle file content
 */
function seal(key, from, payload) {
  const created = new Date().toISOString();
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv("aes-256-gcm", key, iv);
  cipher.setAAD(Buffer.from(`${HEADER}\n${from}\n${created}`, "utf8"));
  const data = Buffer.concat([cipher.update(JSON.stringify(payload), "utf8"), cipher.final()]);
  const envelope = {
    from,
    created,
    iv: iv.toString("base64"),
    tag: cipher.getAuthTag().toString("base64"),
    data: data.toString("base64"),
  };
  return `${HEADER}\n${JSON.stringify(envelope)}\n`;
}

/**
 * Decrypts and authenticates a bundle.
 * @param {Buffer} key 32-byte key
 * @param {string} text bundle file content
 * @returns {{from: string, created: string, payload: {files: Array<{path: string, mtime: number, data: string}>}}}
 * @throws {SyncError} (REJECTED) when it is malformed, tampered or made with another key
 */
function open(key, text) {
  const lines = text.replace(/^﻿/, "").split(/\r?\n/);
  if (lines[0] !== HEADER) throw new SyncError("not a dotfiles-sync secrets bundle", EXIT.REJECTED);
  let env;
  try {
    env = JSON.parse(lines[1]);
  } catch {
    throw new SyncError("malformed secrets bundle", EXIT.REJECTED);
  }
  let plain;
  try {
    const decipher = crypto.createDecipheriv("aes-256-gcm", key, Buffer.from(env.iv, "base64"));
    decipher.setAAD(Buffer.from(`${HEADER}\n${env.from}\n${env.created}`, "utf8"));
    decipher.setAuthTag(Buffer.from(env.tag, "base64"));
    plain = Buffer.concat([decipher.update(Buffer.from(env.data, "base64")), decipher.final()]);
  } catch {
    throw new SyncError(
      "secrets bundle failed authentication: it was made with a different key or altered on the way",
      EXIT.REJECTED
    );
  }
  const payload = JSON.parse(plain.toString("utf8"));
  if (!payload || !Array.isArray(payload.files)) throw new SyncError("malformed secrets bundle", EXIT.REJECTED);
  return { from: String(env.from), created: String(env.created), payload };
}

/**
 * Creates a new random key, refusing to replace an existing one.
 * @param {string} state state directory
 * @returns {void}
 */
function cmdInit(state) {
  const file = path.join(state, KEY_FILE);
  if (fs.existsSync(file)) throw new SyncError(`a secrets key already exists (${file})`);
  writePrivate(file, crypto.randomBytes(32).toString("base64") + "\n");
  console.error(`created ${file}`);
}

/**
 * Prints the key, for copying to the other machine.
 * @param {string} state state directory
 * @returns {void}
 */
function cmdShowKey(state) {
  console.log(readKey(state).toString("base64"));
}

/**
 * Stores the key read from stdin (so it never appears in argv or history).
 * @param {string} state state directory
 * @returns {void}
 */
function cmdSetKey(state) {
  const key = decodeKey(fs.readFileSync(0, "utf8"));
  writePrivate(path.join(state, KEY_FILE), key.toString("base64") + "\n");
  // content from before the key existed may never have reached the peer
  writeState(state, {});
  console.error(`stored ${path.join(state, KEY_FILE)}`);
}

/**
 * Prints the key state and, per listed path, whether it is in sync.
 * @param {string} repo repo root
 * @param {string} state state directory
 * @returns {void}
 */
function cmdStatus(repo, state) {
  let keyLine = "set";
  try {
    readKey(state);
  } catch (e) {
    keyLine = e.code === EXIT.UNCONFIGURED ? "none (dotfiles-sync secrets init / set-key)" : e.message;
  }
  console.log(`key:       ${keyLine}`);
  const list = readList(repo);
  if (list.length === 0) console.log(`files:     none listed in ${LIST_FILE}`);
  const record = readState(state);
  for (const rel of list) {
    const why = unsafeReason(repo, rel);
    let s;
    if (why) s = `refused: ${why}`;
    else if (!fs.existsSync(path.join(repo, rel))) s = "missing here";
    else {
      const h = sha256(fs.readFileSync(path.join(repo, rel)));
      s = record[rel] && record[rel].sha256 === h ? "in sync" : "changed, sent on the next cycle";
    }
    console.log(`  ${rel}: ${s}`);
  }
}

/**
 * Packs every listed file that changed since it was last sent or received
 * (every listed file with --all) into an encrypted bundle, and records them
 * as sent. Prints the packed paths.
 * @param {string} repo repo root
 * @param {string} state state directory
 * @param {string} label this side's label
 * @param {string} out bundle to write
 * @param {boolean} all pack unchanged files too
 * @returns {number} exit code
 */
function cmdPack(repo, state, label, out, all) {
  const list = readList(repo);
  if (list.length === 0) throw new SyncError(`no secret files listed in ${LIST_FILE}`, EXIT.UNCONFIGURED);
  const key = readKey(state);
  const record = readState(state);
  const files = [];
  for (const rel of list) {
    const full = path.join(repo, rel);
    if (!fs.existsSync(full)) continue;
    const why = unsafeReason(repo, rel);
    if (why) {
      console.error(`not sending ${rel}: ${why}`);
      continue;
    }
    const st = fs.statSync(full);
    if (!st.isFile()) continue;
    if (st.size > MAX_FILE_BYTES) {
      console.error(`not sending ${rel}: larger than ${MAX_FILE_BYTES} bytes`);
      continue;
    }
    const buf = fs.readFileSync(full);
    const h = sha256(buf);
    if (!all && record[rel] && record[rel].sha256 === h) continue;
    files.push({ path: rel, mtime: st.mtimeMs, sha256: h, data: buf.toString("base64") });
  }
  if (files.length === 0) return EXIT.NOTHING;
  writePrivate(out, seal(key, label, { files }));
  for (const f of files) record[f.path] = { sha256: f.sha256 };
  writeState(state, record);
  for (const f of files) console.log(f.path);
  return EXIT.OK;
}

/**
 * Applies a bundle from the peer: per file, the newest modification time wins
 * (the higher content hash on a tie); the local copy is kept otherwise and
 * goes out with the next cycle. Prints what happened to each file.
 * @param {string} repo repo root
 * @param {string} state state directory
 * @param {string} label this side's label
 * @param {string} file bundle to apply
 * @returns {number} exit code
 */
function cmdUnpack(repo, state, label, file) {
  const key = readKey(state);
  const { from, payload } = open(key, fs.readFileSync(file, "utf8"));
  if (from === label) {
    console.log(`skipped: the bundle came from this side (${label})`);
    return EXIT.OK;
  }
  const allowed = new Set(readList(repo));
  const record = readState(state);
  for (const f of payload.files) {
    const rel = String(f.path);
    if (!allowed.has(rel)) {
      console.log(`refused ${rel}: not listed in this repo's ${LIST_FILE}`);
      continue;
    }
    const why = unsafeReason(repo, rel);
    if (why) {
      console.log(`refused ${rel}: ${why}`);
      continue;
    }
    const incoming = Buffer.from(String(f.data), "base64");
    const inHash = sha256(incoming);
    const inTime = Number(f.mtime) || 0;
    const full = path.join(repo, rel);
    if (fs.existsSync(full)) {
      const local = fs.readFileSync(full);
      const localHash = sha256(local);
      if (localHash === inHash) {
        record[rel] = { sha256: inHash };
        console.log(`unchanged ${rel}`);
        continue;
      }
      const localTime = fs.statSync(full).mtimeMs;
      if (localTime > inTime || (localTime === inTime && localHash > inHash)) {
        console.log(`kept ${rel}: the copy here is newer and goes to ${from} on the next cycle`);
        continue;
      }
    }
    fs.mkdirSync(path.dirname(full), { recursive: true });
    writePrivate(full, incoming);
    if (inTime > 0) fs.utimesSync(full, new Date(), new Date(inTime));
    record[rel] = { sha256: inHash };
    console.log(`updated ${rel}`);
  }
  writeState(state, record);
  return EXIT.OK;
}

/**
 * Entry point: dispatches the command and maps errors to exit codes.
 * @returns {void}
 */
function main() {
  const [cmd, ...argv] = process.argv.slice(2);
  let code = EXIT.OK;
  try {
    const { opts, rest } = parseArgs(argv);
    const repo = opts.repo;
    const state = opts.state;
    if (!repo || !state) throw new SyncError("--repo and --state are required");
    fs.mkdirSync(state, { recursive: true });
    const needLabel = () => {
      if (!opts.label) throw new SyncError("--label is required");
      return String(opts.label);
    };
    switch (cmd) {
      case "init":
        cmdInit(state);
        break;
      case "show-key":
        cmdShowKey(state);
        break;
      case "set-key":
        cmdSetKey(state);
        break;
      case "status":
        cmdStatus(repo, state);
        break;
      case "pack":
        if (!opts.out) throw new SyncError("pack needs --out FILE");
        code = cmdPack(repo, state, needLabel(), String(opts.out), Boolean(opts.all));
        break;
      case "unpack":
        if (rest.length !== 1) throw new SyncError("unpack needs one bundle file");
        code = cmdUnpack(repo, state, needLabel(), rest[0]);
        break;
      default:
        throw new SyncError(`unknown command: ${cmd || "(none)"}`);
    }
  } catch (e) {
    console.error(`dotfiles-sync-secrets: ${e.message}`);
    code = e instanceof SyncError ? e.code : EXIT.ERROR;
  }
  process.exitCode = code;
}

main();
