import { WmClient } from 'glazewm';
import fs from 'fs';

const LOG_FILE = 'C:/Users/ronen/dotfiles/.glzr/glazewm/scripts/join.log';

function log(msg) {
  try {
    fs.appendFileSync(LOG_FILE, new Date().toISOString() + ' - ' + msg + '\n');
  } catch (e) {}
}

const VALID_DIRECTIONS = new Set(['left', 'right', 'up', 'down']);

const sleep = (ms) => new Promise((resolve) => setTimeout(resolve, ms));

function axisForJoin(direction) {
  return direction === 'left' || direction === 'right'
    ? 'vertical'
    : 'horizontal';
}

async function waitForFocusedChange(client, previousId, timeoutMs = 800, pollMs = 25) {
  const started = Date.now();
  log(`Waiting for focus change from ${previousId} for ${timeoutMs}ms...`);
  while (Date.now() - started < timeoutMs) {
    const { focused } = await client.queryFocused();
    if (focused && focused.id !== previousId) {
      log(`Focus changed to ${focused.id}`);
      return focused;
    }
    await sleep(pollMs);
  }
  log(`Timed out waiting for focus change from ${previousId}`);
  return null;
}

async function join({
  direction,
  tilingDirection = axisForJoin(direction),
  settleMs = 40,
  focusTimeoutMs = 800,
}) {
  log(`Starting join operation: direction=${direction}, tilingDirection=${tilingDirection}`);
  
  if (!VALID_DIRECTIONS.has(direction)) {
    throw new Error(`Invalid direction "${direction}". Use left|right|up|down.`);
  }

  const client = new WmClient();
  log(`Connecting to GlazeWM...`);

  const { focused: original } = await client.queryFocused();
  if (!original) {
    throw new Error('No focused container.');
  }
  log(`Original focused container: ${original.id}`);

  log(`Running command: focus --direction ${direction}`);
  await client.runCommand(`focus --direction ${direction}`);

  const target = await waitForFocusedChange(client, original.id, focusTimeoutMs);
  if (!target) {
    throw new Error(`No join target found in direction "${direction}".`);
  }

  log(`Running command: set-tiling-direction ${tilingDirection} on target ${target.id}`);
  await client.runCommand(`set-tiling-direction ${tilingDirection}`, target.id);
  
  log(`Sleeping for ${settleMs}ms`);
  await sleep(settleMs);
  
  log(`Running command: move --direction ${direction} on original ${original.id}`);
  await client.runCommand(`move --direction ${direction}`, original.id);
  
  log(`Join operation completed successfully.`);
}

async function main() {
  const [
    direction,
    tilingDirectionArg,
    settleMsArg,
    focusTimeoutMsArg,
  ] = process.argv.slice(2);

  log(`Script called with args: ${process.argv.slice(2).join(', ')}`);

  if (!VALID_DIRECTIONS.has(direction)) {
    console.error('Usage: node join.mjs <left|right|up|down> [vertical|horizontal] [settleMs] [focusTimeoutMs]');
    process.exit(2);
  }

  const tilingDirection =
    tilingDirectionArg && ['vertical', 'horizontal'].includes(tilingDirectionArg)
      ? tilingDirectionArg
      : axisForJoin(direction);

  const settleMs = Number.isFinite(Number(settleMsArg)) ? Number(settleMsArg) : 40;
  const focusTimeoutMs = Number.isFinite(Number(focusTimeoutMsArg)) ? Number(focusTimeoutMsArg) : 800;

  await join({
    direction,
    tilingDirection,
    settleMs,
    focusTimeoutMs,
  });
}

main().catch((err) => {
  log(`ERROR: ${err.message || err}`);
  console.error(err.message || err);
  process.exit(1);
});
