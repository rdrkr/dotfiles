#!/usr/bin/env node

/**
 * Universal multi-account Claude Usage Fetcher (hardened for the Topcon corporate
 * proxy + Cloudflare). This single script is deployed unchanged to every account
 * location; it figures out which account it represents at runtime:
 *
 *   - When run as a per-account backup script
 *     (~/.claude-switch-backup/scripts/.fetch-claude-usage-<num>-<email>.js) it
 *     parses the account number out of its own filename.
 *   - When run as the active script (~/.claude/fetch-claude-usage.js) it reads the
 *     active account number from ~/.claude-switch-backup/sequence.json.
 *
 * It then looks up that account's credentials in ~/.claude/usage-secrets.json
 * (gitignored) and fetches usage. Output on success: `fhUtil|fhReset|sdUtil|sdReset`.
 * Output on failure: `ERROR:<message>` (after attempting a cached fallback).
 *
 * Why it shells out to the system `curl` instead of Node's `https`:
 *   - claude.ai is MITM-intercepted by the Topcon proxy, so the chain must be
 *     verified against the Windows trust store (`--ca-native`), and Schannel's
 *     revocation check skipped because the CRL is unreachable behind the proxy
 *     (`--ssl-no-revoke`, otherwise CRYPT_E_NO_REVOCATION_CHECK).
 *   - The /usage endpoint sits behind a Cloudflare managed challenge. Node's
 *     OpenSSL TLS fingerprint is challenged (403, cf-mitigated: challenge); curl's
 *     Schannel fingerprint plus a browser User-Agent and the authenticated
 *     `sessionKey` cookie clears it and returns 200. (No cf_clearance required.)
 *
 * Results are cached per account so the status line can show last-known usage when
 * a request is transiently challenged, and a short freshness window throttles how
 * often the network is actually hit (the status line may render very frequently).
 */

const { execFileSync } = require("child_process");
const fs = require("fs");
const path = require("path");

const HOME = process.env.HOME || process.env.USERPROFILE;
const CLAUDE_DIR = path.join(HOME, ".claude");
const SECRETS_PATH = path.join(CLAUDE_DIR, "usage-secrets.json");
const SEQUENCE_PATH = path.join(HOME, ".claude-switch-backup", "sequence.json");

const CACHE_FRESH_MS = 60 * 1000; // within this window, serve cache without hitting the network
const CACHE_MAX_AGE_MS = 6 * 60 * 60 * 1000; // on failure, serve cache up to this age

/**
 * Determine which account number this invocation represents. Prefers the number
 * embedded in the script's own filename (per-account backup copies); otherwise
 * falls back to the active account recorded in sequence.json.
 * @returns {?string} the account number as a string, or null if undeterminable
 */
function resolveAccountNumber() {
  const m = path.basename(__filename).match(/fetch-claude-usage-(\d+)-/);
  if (m) return m[1];
  try {
    const seq = JSON.parse(fs.readFileSync(SEQUENCE_PATH, "utf8"));
    if (seq && seq.activeAccountNumber != null) return String(seq.activeAccountNumber);
  } catch {
    // no sequence file
  }
  return null;
}

/**
 * Per-account cache file path (kept centrally under ~/.claude regardless of where
 * the script copy lives).
 * @param {string} accountNum
 * @returns {string}
 */
function cachePathFor(accountNum) {
  return path.join(CLAUDE_DIR, `.usage-cache-${accountNum}.json`);
}

/**
 * Read the cached tuple for an account if present and younger than maxAgeMs.
 * @param {string} accountNum
 * @param {number} maxAgeMs
 * @returns {?{fhUtil:(number|string), fhReset:string, sdUtil:(number|string), sdReset:string}}
 */
function readCache(accountNum, maxAgeMs) {
  try {
    const c = JSON.parse(fs.readFileSync(cachePathFor(accountNum), "utf8"));
    if (typeof c.ts === "number" && Date.now() - c.ts <= maxAgeMs) return c;
  } catch {
    // no/invalid cache
  }
  return null;
}

/**
 * Persist a successful tuple for an account.
 * @param {string} accountNum
 * @param {{fhUtil:(number|string), fhReset:string, sdUtil:(number|string), sdReset:string}} data
 * @returns {void}
 */
function writeCache(accountNum, data) {
  try {
    fs.writeFileSync(cachePathFor(accountNum), JSON.stringify({ ...data, ts: Date.now() }));
  } catch {
    // best-effort
  }
}

/**
 * Load the full secrets document.
 * @returns {object}
 * @throws {Error} when missing or unparseable
 */
function readSecretsDoc() {
  let raw;
  try {
    raw = fs.readFileSync(SECRETS_PATH, "utf8");
  } catch {
    throw new Error("NO_SECRETS_FILE");
  }
  try {
    return JSON.parse(raw);
  } catch {
    throw new Error("BAD_SECRETS_JSON");
  }
}

/**
 * Resolve the effective credentials for an account from the secrets document.
 * @param {object} doc parsed usage-secrets.json
 * @param {string} accountNum
 * @returns {{sessionKey:string, orgId:string, userAgent:string}}
 * @throws {Error} when the account is unconfigured or still a placeholder
 */
function credentialsFor(doc, accountNum) {
  const acct = (doc.accounts && doc.accounts[accountNum]) || {};
  const sessionKey = (acct.sessionKey || "").trim();
  const orgId = (acct.orgId || "").trim();
  const userAgent =
    (acct.userAgent || doc.userAgent || "").trim() ||
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/149.0.0.0 Safari/537.36";

  if (!sessionKey || sessionKey.startsWith("<")) throw new Error("NO_SESSION_KEY");
  if (orgId.includes("..") || orgId.includes("/")) throw new Error("Invalid organization ID");
  return { sessionKey, orgId, userAgent };
}

/**
 * Persist a discovered orgId back into the secrets document for an account so it is
 * only looked up once. Best-effort and atomic.
 * @param {string} accountNum
 * @param {string} orgId
 * @returns {void}
 */
function persistOrgId(accountNum, orgId) {
  try {
    const doc = readSecretsDoc();
    if (!doc.accounts || !doc.accounts[accountNum]) return;
    doc.accounts[accountNum].orgId = orgId;
    const tmp = `${SECRETS_PATH}.tmp_${process.pid}`;
    fs.writeFileSync(tmp, JSON.stringify(doc, null, 2) + "\n");
    fs.renameSync(tmp, SECRETS_PATH);
  } catch {
    // best-effort
  }
}

/**
 * Resolve a usable curl executable. Prefers the Windows system curl (Schannel
 * build) so TLS behaviour matches what was validated; falls back to PATH curl.
 * @returns {string}
 */
function resolveCurl() {
  const sysRoot = process.env.SystemRoot || process.env.windir || "C:\\Windows";
  const sysCurl = path.join(sysRoot, "System32", "curl.exe");
  try {
    if (fs.existsSync(sysCurl)) return sysCurl;
  } catch {
    // ignore
  }
  return "curl";
}

/**
 * Perform an authenticated GET against claude.ai via system curl and return the
 * parsed JSON body.
 * @param {string} urlPath e.g. "/api/organizations" or "/api/organizations/<id>/usage"
 * @param {{sessionKey:string, userAgent:string, jar:string}} creds
 * @returns {*} parsed JSON
 * @throws {Error} on transport failure, Cloudflare challenge, non-200, or bad JSON
 */
function apiGet(urlPath, creds) {
  const MARKER = "\n__HTTP_STATUS__:";
  const args = ["-s"];
  // Windows/Schannel behind the Topcon proxy needs to trust the OS store and skip
  // the unreachable CRL check. These flags are unnecessary (and `--ca-native` may
  // be unsupported) on macOS/Linux, so only add them on Windows.
  if (process.platform === "win32") {
    args.push("--ssl-no-revoke", "--ca-native");
  }
  // Persist Cloudflare's __cf_bm bot-management cookie across invocations (read and
  // write the same jar) so repeated calls look like one continuing browser session
  // rather than fresh unknown clients. The secret sessionKey is sent via the header
  // below, not stored in the jar.
  if (creds.jar) args.push("-b", creds.jar, "-c", creds.jar);
  args.push(
    "--max-time",
    "15",
    "-H",
    `Cookie: sessionKey=${creds.sessionKey}`,
    "-H",
    `User-Agent: ${creds.userAgent}`,
    "-H",
    "Accept: application/json",
    "-w",
    `${MARKER}%{http_code}`,
    `https://claude.ai${urlPath}`
  );

  let out;
  try {
    out = execFileSync(resolveCurl(), args, {
      encoding: "utf8",
      maxBuffer: 1024 * 1024,
      windowsHide: true,
    });
  } catch {
    throw new Error("CURL_FAILED");
  }

  const idx = out.lastIndexOf(MARKER);
  const status = idx >= 0 ? out.slice(idx + MARKER.length).trim() : "000";
  const body = idx >= 0 ? out.slice(0, idx) : out;

  // A 403 can mean two very different things, so disambiguate by body:
  //   - An expired/invalid sessionKey returns a JSON permission_error with
  //     "account_session_invalid" (the API itself rejecting auth) -> SESSION_EXPIRED.
  //   - A Cloudflare managed challenge returns an HTML interstitial ("Just a
  //     moment...") with no such marker -> CLOUDFLARE_CHALLENGE.
  // Reporting these as the same thing previously masked an expired key as a
  // Cloudflare problem.
  if (status === "403") {
    if (/account_session_invalid|Invalid authorization|permission_error/.test(body)) {
      throw new Error("SESSION_EXPIRED");
    }
    throw new Error("CLOUDFLARE_CHALLENGE");
  }
  if (status === "401") throw new Error("UNAUTHORIZED");
  if (status !== "200") throw new Error(`HTTP_${status}`);

  try {
    return JSON.parse(body);
  } catch {
    throw new Error("Invalid response format");
  }
}

/**
 * Look up the organization UUID for the account (first organization on the
 * session), used when orgId is not yet configured.
 * @param {{sessionKey:string, userAgent:string}} creds
 * @returns {string}
 * @throws {Error} when no organization can be found
 */
function discoverOrgId(creds) {
  const orgs = apiGet("/api/organizations", creds);
  if (Array.isArray(orgs) && orgs.length > 0 && orgs[0].uuid) return orgs[0].uuid;
  throw new Error("NO_ORG_FOUND");
}

/**
 * Fetch and normalize usage for the resolved org.
 * @param {string} orgId
 * @param {{sessionKey:string, userAgent:string}} creds
 * @returns {{fhUtil:number, fhReset:string, sdUtil:number, sdReset:string}}
 */
function fetchUsage(orgId, creds) {
  const json = apiGet(`/api/organizations/${orgId}/usage`, creds);
  const fh = json.five_hour || {};
  const sd = json.seven_day || {};
  return {
    fhUtil: fh.utilization ?? 0,
    fhReset: fh.resets_at ?? "",
    sdUtil: sd.utilization ?? 0,
    sdReset: sd.resets_at ?? "",
  };
}

/**
 * Print a usage tuple in the status line's expected pipe-delimited form.
 * @param {{fhUtil:(number|string), fhReset:string, sdUtil:(number|string), sdReset:string}} d
 * @returns {void}
 */
function emit(d) {
  console.log(`${d.fhUtil}|${d.fhReset}|${d.sdUtil}|${d.sdReset}`);
}

/**
 * Entry point. Resolves the account, throttles via a fresh cache, fetches usage
 * (discovering/persisting orgId if needed), caches the result, and falls back to a
 * still-valid cache on any error.
 * @returns {void}
 */
(function main() {
  const accountNum = resolveAccountNumber();
  if (!accountNum) {
    console.log("ERROR:NO_ACCOUNT");
    process.exit(1);
  }

  // Throttle: very recent cache is served without touching the network.
  const fresh = readCache(accountNum, CACHE_FRESH_MS);
  if (fresh) {
    emit(fresh);
    process.exit(0);
  }

  try {
    const doc = readSecretsDoc();
    const creds = credentialsFor(doc, accountNum);
    creds.jar = path.join(CLAUDE_DIR, `.usage-cookies-${accountNum}.txt`);

    let orgId = creds.orgId;
    if (!orgId) {
      orgId = discoverOrgId(creds);
      persistOrgId(accountNum, orgId);
    }

    const data = fetchUsage(orgId, creds);
    writeCache(accountNum, data);
    emit(data);
    process.exit(0);
  } catch (err) {
    const cache = readCache(accountNum, CACHE_MAX_AGE_MS);
    if (cache) {
      emit(cache);
      process.exit(0);
    }
    console.log(`ERROR:${err.message}`);
    process.exit(1);
  }
})();
