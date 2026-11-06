// Helpers shared by bar.html and the popup widgets (tray.html, volume.html).
// Popups are full-monitor transparent layers; the panel inside is placed under
// the bar button that opened it, using an anchor stored in localStorage
// (all widgets of this pack share one origin).
import * as zebar from 'https://esm.sh/zebar@3.3.1';

export const BAR_HEIGHT = 44;
const EDGE_MARGIN = 8;

async function currentMonitorSelection() {
  try {
    const mon = await zebar.currentWidget().tauriWindow.currentMonitor();
    if (mon?.name) return { type: 'name', match: mon.name };
  } catch (err) {
    console.error('currentMonitor failed', err);
  }
  return { type: 'primary' };
}

// Opens popup widget `name` as a full-monitor layer, anchoring its panel's
// right edge to the right edge of `anchorEl`.
export async function openPopup(name, anchorEl) {
  const rect = anchorEl.getBoundingClientRect();
  try {
    localStorage.setItem(`${name}Anchor`, JSON.stringify({ right: Math.round(rect.right), top: BAR_HEIGHT }));
  } catch (err) {
    console.error(`cannot store ${name}Anchor`, err);
  }
  await zebar.startWidget(name, {
    anchor: 'top_left',
    offsetX: '0px',
    offsetY: '0px',
    width: '100%',
    height: '100%',
    monitorSelection: await currentMonitorSelection(),
    dockToEdge: { enabled: false, edge: null, windowMargin: '0px' },
  });
}

// Inside a popup: CSS position for the panel, from the stored anchor.
export function panelPosition(name) {
  let anchor = null;
  try {
    anchor = JSON.parse(localStorage.getItem(`${name}Anchor`) || 'null');
  } catch (err) {
    console.error(`bad ${name}Anchor`, err);
  }
  const right = Number.isFinite(anchor?.right) ? anchor.right : window.innerWidth - EDGE_MARGIN;
  const top = Number.isFinite(anchor?.top) ? anchor.top : BAR_HEIGHT;
  return { top: `${top}px`, right: `${Math.max(EDGE_MARGIN, window.innerWidth - right)}px` };
}

// Inside a popup: close it on Esc, once only.
export function popupCloser() {
  const widget = zebar.currentWidget();
  let closing = false;
  const close = () => {
    if (closing) return;
    closing = true;
    widget.close().catch((err) => console.error('popup close failed', err));
  };
  window.addEventListener('keydown', (e) => e.key === 'Escape' && close());
  widget.tauriWindow.setFocus().catch(() => {});
  return close;
}

// The Windows volume tray icon is replaced by the bar's volume control.
// Its tooltip is "<device name>: <n>%" (or muted), so match on the device name
// and fall back to that shape.
const VOLUME_TOOLTIP = /:\s*(\d{1,3}\s*%|muted|tắt tiếng)\s*$/i;

export function isVolumeIcon(icon, audio) {
  const tip = (icon?.tooltip || '').trim();
  if (!tip) return false;
  const names = (audio?.playbackDevices || [audio?.defaultPlaybackDevice])
    .filter(Boolean)
    .map((d) => d.name);
  if (names.some((n) => n && tip.startsWith(n))) return true;
  return VOLUME_TOOLTIP.test(tip);
}

export function visibleTrayIcons(systray, audio) {
  return (systray?.icons ?? []).filter((icon) => !isVolumeIcon(icon, audio));
}

// ---------- audio ----------

export const VOLUME_STEP = 5;

export function volumeIcon(device) {
  if (device.isMuted || device.volume === 0) return 'nf-md-volume_off';
  if (device.volume < 35) return 'nf-md-volume_low';
  if (device.volume < 70) return 'nf-md-volume_medium';
  return 'nf-md-volume_high';
}

export function clampVolume(value) {
  return Math.max(0, Math.min(100, Math.round(value)));
}

// Volume after one mouse-wheel notch.
export function wheelVolume(device, deltaY) {
  return clampVolume(device.volume + (deltaY < 0 ? VOLUME_STEP : -VOLUME_STEP));
}

// Opens a ms-settings:/ms-*: URI (needs the explorer shell privilege).
export function openUri(uri) {
  zebar.shellExec('explorer', uri).catch((err) => console.error('openUri failed', uri, err));
}
