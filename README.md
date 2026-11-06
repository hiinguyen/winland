# winland

A Hyprland-style desktop for Windows 11.
Workspaces and keyboard-driven tiling with [GlazeWM](https://github.com/glzr-io/glazewm), a Waybar-like top bar built with [Zebar](https://github.com/glzr-io/zebar), a rofi-like launcher with [Flow Launcher](https://www.flowlauncher.com/), and a few [AutoHotkey v2](https://www.autohotkey.com/) helpers that fill the gaps.
Everything uses the Catppuccin Mocha palette.

## Features

- 10 workspaces per machine, switched with `Win+1..0`, shown as pills on the bar with the icons of their apps.
- Windows open maximized by default; `Win+Ctrl+F` toggles the workspace into a side-by-side overview and back.
- Focus follows the mouse, and there are no outer gaps for the cursor to fall into.
- A top bar that reserves its own screen space: workspaces, focused window title, clock, media, CPU, RAM, network, battery and volume.
- A tray dropdown instead of a row of tray icons, and a volume popup with a slider and mute button.
- The native Windows taskbar is hidden (it comes back when the helpers exit, or with `Win+Shift+T`).
- `Alt+Tab` lists only the windows of the workspace on the focused monitor and moves the cursor onto the chosen window.
- A lone `Win` key press no longer opens the Start menu, so `Win+<key>` shortcuts never pop it up by accident.
- Minimizing is disabled: minimized windows are restored at once.
- App-drawn notification popups (Zalo) are moved to the bottom-right corner.

## Install

Requirements: Windows 11 with `winget` (App Installer from the Microsoft Store).

```powershell
git clone https://github.com/hiinguyen/winland.git
cd winland
powershell -ExecutionPolicy Bypass -File .\setup.ps1
```

`setup.ps1` installs GlazeWM, Zebar, AutoHotkey v2 and Flow Launcher with winget.
It backs up any existing config to `%USERPROFILE%\.glzr\backups\<timestamp>` before replacing it.
It turns on taskbar auto-hide, which restarts Explorer once if it was off.
It sets the wallpaper fit to Fill, adds GlazeWM and the helpers to the Startup folder, and starts everything.
Run it again at any time to re-apply the configs from the repo.

| Option | Effect |
|---|---|
| `-SkipInstall` | Do not run winget (the apps must already be installed). |
| `-SkipWallpaper` | Keep the current wallpaper fit mode. |
| `-NoStart` | Install files only; do not restart GlazeWM, Zebar and the helpers. |

To turn winland off, run `uninstall.ps1`.
It stops everything, removes the startup shortcuts and brings the native taskbar back.
Apps and config files stay in place.

## Keys

`Win` is the modifier, like `SUPER` on Hyprland.

| Keys | Action |
|---|---|
| `Win+Enter` | Windows Terminal |
| `Win+D` | Launcher (apps, files, settings, calculator, web search) |
| `Win+B` | Browser (Chrome) |
| `Win+E` | File Explorer |
| `Win+I` | Settings |
| `Win+Shift+A` / `N` / `B` | Sound / network / Bluetooth settings |
| `Win+Shift+Esc` | Task Manager |
| `Win+Q` | Close window |
| `Win+F` | Toggle fullscreen for one window |
| `Win+T` | Toggle tiling for one window |
| `Win+V` | Toggle floating |
| `Win+Ctrl+F` | Toggle the workspace between maximized windows and the side-by-side overview |
| `Win+Arrows` | Move focus |
| `Win+Shift+Arrows` | Move window |
| `Win+Alt+Arrows` | Resize window |
| `Win+R` | Resize mode (`H/J/K/L` or arrows, `Esc` to leave) |
| `Win+J` | Toggle tiling direction |
| `Win+C` | Cycle focus between tiling and floating windows |
| `Win+1..0` | Go to workspace |
| `Win+Shift+1..0` | Move window to workspace and follow it |
| `Win+Alt+1..0` | Move window to workspace silently |
| `Win+Ctrl+Left/Right` | Previous / next workspace |
| `Win+Tab` | Last used workspace |
| `Win+Ctrl+Shift+Left/Right` | Move workspace to the other monitor |
| `Alt+Tab` | Switch window within the current workspace |
| `Win+Shift+T` | Show / hide the native taskbar |
| `Win+Shift+R` | Reload GlazeWM config |
| `Win+Shift+P` | Pause GlazeWM |
| `Win+Shift+E` | Quit GlazeWM |

On the bar, click the Windows logo for the Start menu and the clock for notifications.
Scroll over the workspaces to switch, and scroll over the volume to change it.
Right-click the volume to mute.

## Layout

```
config/
  glazewm/config.yaml         GlazeWM config ({{FLOW_LAUNCHER}} is filled in by setup.ps1)
  zebar/settings.json         starts the hyprbar widget
  zebar/hyprbar/              the bar widget pack
    bar.html, bar.css         the bar
    tray.html, tray.css       tray dropdown
    volume.html, volume.css   volume popup
    popup.css, shared.js      shared popup layer and helpers
    layout.js                 maximize-by-default and the Win+Ctrl+F overview
  ahk/                        AutoHotkey v2 helpers, entry point main.ahk
    workspace-alttab.ahk      Alt+Tab per workspace and monitor
    taskbar.ahk               hides the native taskbar
    winkey.ahk                lone Win key does not open Start
    nominimize.ahk            undoes minimize
    notify-position.ahk       moves app notification popups to the bottom-right
  flowlauncher/               Catppuccin Mocha theme for Flow Launcher
setup.ps1                     installer
uninstall.ps1                 turns winland off
```

Files are installed to `%USERPROFILE%\.glzr\glazewm`, `%USERPROFILE%\.glzr\zebar\hyprbar` and `%USERPROFILE%\.glzr\winland`.

## Known limitations

- Zebar forwards tray icon clicks without the icon position, so some app menus (for example Bluetooth) open in the top-left corner.
- The order of tray icons changes each time Zebar restarts.
- `Win+Ctrl+F` and maximize-by-default are run by the bar, so they need Zebar to be running.
- To make other apps' notification popups go to the bottom-right, add their exe names to `NOTIFY_PROCS` in `notify-position.ahk`.
