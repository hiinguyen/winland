; Entry point for the Hyprland-style helpers (started from the Startup folder).
;  - workspace-alttab.ahk: Alt+Tab limited to the focused monitor's workspace
;  - taskbar.ahk: hides the native taskbar (Zebar replaces it), Win+Shift+T toggles
;  - winkey.ahk: a lone Win key press no longer opens the Start menu
;  - notify-position.ahk: app notification popups (Zalo) go to the bottom-right
;  - nominimize.ahk: minimized app windows are restored at once
#Requires AutoHotkey v2.0
#SingleInstance Force
#NoTrayIcon

#Include workspace-alttab.ahk
#Include taskbar.ahk
#Include winkey.ahk
#Include notify-position.ahk
#Include nominimize.ahk
