/**
 * @file Tab Group Nav service worker.
 *
 * Chrome's own Ctrl+Tab / Ctrl+Shift+Tab skip over collapsed tab groups. The
 * `previous-tab` / `next-tab` commands here step through every tab in strip
 * order instead, expanding a collapsed group when stepping into it. Whenever
 * the active tab changes (keyboard or mouse), every group in that window that
 * does not contain the active tab is collapsed, so leaving a group folds it
 * back up. `new-tab-in-group` opens a new tab inside the active tab's group.
 *
 * The commands are browser-level accelerators (chrome.commands), so unlike
 * content-script based shortcut extensions they work on every page, including
 * chrome:// pages, the New Tab page, PDFs and while the omnibox has focus.
 * Triggered from komorebic-hotkeys.ahk (Win+Alt+Left/Right, Win+Shift+[/],
 * Win+T).
 */

/** Delay between retries while Chrome refuses tab edits (ms). */
const RETRY_DELAY_MS = 100;

/** Maximum attempts for a tab/group edit that Chrome refuses transiently. */
const RETRY_ATTEMPTS = 20;

/**
 * Promise chain that serializes all work, so rapid key presses and activation
 * events never interleave and each step sees the result of the previous one.
 * @type {Promise<void>}
 */
let queue = Promise.resolve();

/**
 * Appends a task to the serial work queue, logging (not propagating) failures
 * so one failed step does not wedge the chain.
 * @param {() => Promise<void>} task Work to run once all earlier tasks settle.
 */
function enqueue(task) {
  queue = queue.then(task).catch((err) => console.error("[tab-group-nav]", err));
}

/**
 * Runs a tab/group edit, retrying while Chrome reports that tabs "cannot be
 * edited right now" (it does so briefly during tab switches and drags).
 * @template T
 * @param {() => Promise<T>} fn The edit to perform.
 * @returns {Promise<T>} The edit's result.
 */
async function withRetry(fn) {
  for (let attempt = 1; ; attempt++) {
    try {
      return await fn();
    } catch (err) {
      const transient = /cannot be edited right now/i.test(String(err?.message));
      if (!transient || attempt >= RETRY_ATTEMPTS) throw err;
      await new Promise((resolve) => setTimeout(resolve, RETRY_DELAY_MS));
    }
  }
}

/**
 * Activates the tab `dir` positions away from the active tab in the focused
 * window (wrapping around), expanding its group first if it is collapsed.
 * @param {1 | -1} dir 1 for the next tab, -1 for the previous one.
 * @returns {Promise<void>}
 */
async function step(dir) {
  const [active] = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
  if (!active) return;

  const tabs = await chrome.tabs.query({ windowId: active.windowId });
  tabs.sort((a, b) => a.index - b.index);
  const pos = tabs.findIndex((t) => t.id === active.id);
  const target = tabs[(pos + dir + tabs.length) % tabs.length];
  if (!target || target.id === active.id) return;

  if (target.groupId !== chrome.tabGroups.TAB_GROUP_ID_NONE) {
    const group = await chrome.tabGroups.get(target.groupId);
    if (group.collapsed) {
      await withRetry(() => chrome.tabGroups.update(group.id, { collapsed: false }));
    }
  }

  await withRetry(() => chrome.tabs.update(target.id, { active: true }));
}

/**
 * Collapses every expanded group in `windowId` that does not contain the
 * window's active tab. Re-reads the active tab rather than trusting an event
 * payload, since queued events may be stale after rapid presses.
 * @param {number} windowId The window whose groups to collapse.
 * @returns {Promise<void>}
 */
async function collapseInactiveGroups(windowId) {
  const [active] = await chrome.tabs.query({ active: true, windowId });
  if (!active) return;

  const groups = await chrome.tabGroups.query({ windowId, collapsed: false });
  for (const group of groups) {
    if (group.id === active.groupId) continue;
    await withRetry(() => chrome.tabGroups.update(group.id, { collapsed: true }));
  }
}

/**
 * Collapses inactive groups in every open window; used on install/startup so
 * the strip starts out consistent.
 * @returns {Promise<void>}
 */
async function collapseAllWindows() {
  const windows = await chrome.windows.getAll({ windowTypes: ["normal"] });
  for (const win of windows) await collapseInactiveGroups(win.id);
}

/**
 * Opens a New Tab page in the focused window. When the active tab is in a
 * group, the new tab is placed at the end of that group and joined to it;
 * otherwise it is appended to the end of the strip, like Chrome's Ctrl+T.
 * Runs inside the serial queue, so the onActivated collapse pass only sees the
 * new tab once it already belongs to the group.
 * @returns {Promise<void>}
 */
async function newTabInGroup() {
  const [active] = await chrome.tabs.query({ active: true, lastFocusedWindow: true });
  if (!active) {
    await chrome.tabs.create({});
    return;
  }

  const { windowId, groupId } = active;
  if (groupId === chrome.tabGroups.TAB_GROUP_ID_NONE) {
    await chrome.tabs.create({ windowId });
    return;
  }

  const groupTabs = await chrome.tabs.query({ windowId, groupId });
  const lastIndex = Math.max(...groupTabs.map((t) => t.index));
  const tab = await chrome.tabs.create({ windowId, index: lastIndex + 1 });
  await withRetry(() => chrome.tabs.group({ groupId, tabIds: [tab.id] }));
}

chrome.commands.onCommand.addListener((command) => {
  if (command === "next-tab") enqueue(() => step(1));
  else if (command === "previous-tab") enqueue(() => step(-1));
  else if (command === "new-tab-in-group") enqueue(newTabInGroup);
});

chrome.tabs.onActivated.addListener(({ windowId }) => {
  enqueue(() => collapseInactiveGroups(windowId));
});

chrome.runtime.onInstalled.addListener(() => enqueue(collapseAllWindows));
chrome.runtime.onStartup.addListener(() => enqueue(collapseAllWindows));
