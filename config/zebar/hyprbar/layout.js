// Hyprland-like layout policy, run by the bar because it sees all GlazeWM state.
//  - "big" mode (default): windows are maximized; new windows open maximized.
//  - "tiled" mode: all windows of the workspace side by side. Win+Ctrl+F
//    switches the focused workspace between the two.
// (Minimizing is blocked by ~/.glzr/alttab/nominimize.ahk; the GlazeWM
// provider does not reliably report minimize changes.)
// Win+Ctrl+F enables the GlazeWM binding mode OVERVIEW_MODE; the bar on the
// focused monitor performs the toggle and disables the mode again.
// Each bar only manages the workspaces of its own monitor.

export const OVERVIEW_MODE = 'overview-toggle';
const MAXIMIZE = 'set-fullscreen --maximized';
const TILE = 'set-tiling';
// Ignore repeat commands for a window while GlazeWM applies the last one.
const COMMAND_COOLDOWN_MS = 500;

// A command sent while GlazeWM is still setting up a new window can be lost,
// so new windows stay pending (retried) until they leave the tiling state.
const MAX_MAXIMIZE_TRIES = 5;
const RESYNC_MS = 250;

const seenWindows = new Set();
const pendingMaximize = new Map(); // window id -> tries so far
const lastCommandAt = new Map();
let toggling = false;
let latestGlazewm = null;
let resyncTimer = null;

const modeKey = (ws) => `wsMode:${ws.name}`;

/** @returns {'big' | 'tiled'} */
export function workspaceMode(ws) {
  try {
    return localStorage.getItem(modeKey(ws)) === 'tiled' ? 'tiled' : 'big';
  } catch {
    return 'big';
  }
}

function setWorkspaceMode(ws, mode) {
  try {
    localStorage.setItem(modeKey(ws), mode);
  } catch (err) {
    console.error('cannot store workspace mode', err);
  }
}

function windowsOf(container) {
  if (container.type === 'window') return [container];
  return (container.children ?? []).flatMap(windowsOf);
}

function run(glazewm, command, windowId) {
  if (windowId) {
    const last = lastCommandAt.get(windowId) ?? 0;
    if (Date.now() - last < COMMAND_COOLDOWN_MS) return Promise.resolve();
    lastCommandAt.set(windowId, Date.now());
  }
  return glazewm
    .runCommand(command, windowId)
    .catch((err) => console.error('glazewm command failed', command, err));
}

async function toggleOverview(glazewm) {
  const ws = glazewm.focusedWorkspace;
  const focusedId = glazewm.focusedContainer?.id;
  const wins = windowsOf(ws).filter((w) => ['tiling', 'fullscreen'].includes(w.state.type));
  if (workspaceMode(ws) === 'big') {
    setWorkspaceMode(ws, 'tiled');
    for (const w of wins) if (w.state.type === 'fullscreen') await run(glazewm, TILE, w.id);
    return;
  }
  setWorkspaceMode(ws, 'big');
  // Maximize the focused window last so it ends up in front.
  const ordered = [...wins.filter((w) => w.id !== focusedId), ...wins.filter((w) => w.id === focusedId)];
  for (const w of ordered) if (w.state.type === 'tiling') await run(glazewm, MAXIMIZE, w.id);
}

async function handleToggleSignal(glazewm) {
  const onFocusedMonitor = glazewm.currentWorkspaces.some((ws) => ws.hasFocus);
  if (toggling || !onFocusedMonitor) return;
  toggling = true;
  try {
    await toggleOverview(glazewm);
  } finally {
    await run(glazewm, `wm-disable-binding-mode --name ${OVERVIEW_MODE}`);
    toggling = false;
  }
}

/** Call on every glazewm provider output. */
export function syncLayout(glazewm) {
  if (!glazewm) return;
  latestGlazewm = glazewm;
  resyncTimer ??= setInterval(() => latestGlazewm && applyPolicy(latestGlazewm), RESYNC_MS);
  applyPolicy(glazewm);
}

function applyPolicy(glazewm) {
  if (glazewm.isPaused) return;
  if (glazewm.bindingModes.some((m) => m.name === OVERVIEW_MODE)) handleToggleSignal(glazewm);
  if (toggling) return;

  for (const ws of glazewm.currentWorkspaces) {
    const big = workspaceMode(ws) === 'big';
    for (const win of windowsOf(ws)) {
      if (!seenWindows.has(win.id)) {
        seenWindows.add(win.id);
        if (big && win.state.type === 'tiling') pendingMaximize.set(win.id, 0);
      }
      if (!pendingMaximize.has(win.id)) continue;
      const tries = pendingMaximize.get(win.id);
      if (!big || win.state.type !== 'tiling' || tries >= MAX_MAXIMIZE_TRIES) {
        pendingMaximize.delete(win.id);
        continue;
      }
      const last = lastCommandAt.get(win.id) ?? 0;
      if (Date.now() - last < COMMAND_COOLDOWN_MS) continue;
      pendingMaximize.set(win.id, tries + 1);
      run(glazewm, MAXIMIZE, win.id);
    }
  }
}
