import WebSocket from 'ws';
import fs from 'fs';

// const LOG_FILE = 'C:/Users/ronen/dotfiles/.glzr/glazewm/scripts/join.log';
const LOG_FILE = ''

const GLAZE_PORT = 6123;

function log(msg) {
  try {
    fs.appendFileSync(LOG_FILE, new Date().toISOString() + ' - ' + msg + '\n');
  } catch (e) { }
}

const VALID_DIRECTIONS = new Set(['left', 'right', 'up', 'down']);
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

function axisForJoin(direction) {
  return direction === 'left' || direction === 'right' ? 'vertical' : 'horizontal';
}

function openSocket(timeoutMs = 3000) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(`ws://localhost:${GLAZE_PORT}`);
    const timer = setTimeout(() => {
      ws.terminate();
      reject(new Error(`Connection to ws://localhost:${GLAZE_PORT} timed out after ${timeoutMs}ms`));
    }, timeoutMs);

    ws.once('open', () => {
      clearTimeout(timer);
      log('WebSocket open');
      resolve(ws);
    });

    ws.once('error', (err) => {
      clearTimeout(timer);
      reject(new Error(`WebSocket error: ${err.message}`));
    });
  });
}

function sendAndWait(ws, message, timeoutMs = 4000) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      ws.off('message', handler);
      reject(new Error(`Response timed out for: "${message}"`));
    }, timeoutMs);

    function handler(raw) {
      let msg;
      try {
        msg = JSON.parse(raw.toString());
      } catch {
        return;
      }

      if (msg.messageType === 'client_response' && msg.clientMessage === message) {
        clearTimeout(timer);
        ws.off('message', handler);

        if (msg.error) {
          reject(new Error(`GlazeWM error for "${message}": ${msg.error}`));
        } else {
          resolve(msg.data);
        }
      }
    }

    ws.on('message', handler);
    ws.send(message, (err) => {
      if (err) {
        clearTimeout(timer);
        ws.off('message', handler);
        reject(new Error(`Send failed: ${err.message}`));
      }
    });
  });
}

async function waitForFocusChange(ws, previousId, timeoutMs = 800, pollMs = 25) {
  log(`Polling for focus change away from ${previousId}...`);
  const started = Date.now();

  while (Date.now() - started < timeoutMs) {
    const data = await sendAndWait(ws, 'query focused');
    const focused = data?.focused;

    if (focused && focused.id !== previousId) {
      log(`Focus changed to ${focused.id}`);
      return focused;
    }

    await sleep(pollMs);
  }

  log('Timed out waiting for focus change');
  return null;
}

async function join({ direction, tilingDirection, settleMs, focusTimeoutMs }) {
  log(`join: direction=${direction}, tilingDirection=${tilingDirection}`);

  const ws = await openSocket();

  try {
    const original = (await sendAndWait(ws, 'query focused'))?.focused;
    if (!original) throw new Error('No focused container');
    log(`Original: ${original.id}`);

    await sendAndWait(ws, `command focus --direction ${direction}`);

    const target = await waitForFocusChange(ws, original.id, focusTimeoutMs);
    if (!target) throw new Error(`No join target in direction "${direction}"`);
    log(`Target: ${target.id}`);

    await sendAndWait(ws, `command --id ${target.id} set-tiling-direction ${tilingDirection}`);
    await sleep(settleMs);
    await sendAndWait(ws, `command --id ${original.id} move --direction ${direction}`);

    log('Done.');
  } finally {
    ws.close();
  }
}

async function main() {
  const [direction, tilingDirectionArg, settleMsArg, focusTimeoutMsArg] = process.argv.slice(2);
  log(`Args: ${process.argv.slice(2).join(', ')}`);

  if (!VALID_DIRECTIONS.has(direction)) {
    log('ERROR: invalid direction');
    console.error('Usage: node join.mjs <left|right|up|down> [vertical|horizontal] [settleMs] [focusTimeoutMs]');
    process.exit(2);
  }

  const tilingDirection =
    tilingDirectionArg && ['vertical', 'horizontal'].includes(tilingDirectionArg)
      ? tilingDirectionArg
      : axisForJoin(direction);

  const settleMs = Number.isFinite(Number(settleMsArg)) ? Number(settleMsArg) : 40;
  const focusTimeoutMs = Number.isFinite(Number(focusTimeoutMsArg)) ? Number(focusTimeoutMsArg) : 800;

  await join({ direction, tilingDirection, settleMs, focusTimeoutMs });
}

main().catch((err) => {
  log(`ERROR: ${err.message}`);
  console.error(err.message);
  process.exit(1);
});
