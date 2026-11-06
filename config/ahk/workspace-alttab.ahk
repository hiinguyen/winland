; Alt+Tab replacement: only lists windows on the focused monitor.
; GlazeWM cloaks windows on hidden workspaces (hide_method 'cloak') and
; IsSwitchable() skips cloaked windows - the result is "current workspace only".
#Requires AutoHotkey v2.0

; Render crisply on monitors with different scaling (per-monitor DPI aware v2).
DllCall("SetThreadDpiAwarenessContext", "ptr", -4, "ptr")

; Catppuccin Mocha, matching the Zebar bar.
BASE := "1E1E2E"
SURFACE := "313244"
TEXT := "CDD6F4"
SUBTEXT := "A6ADC8"
OVERLAY := "6C7086"
ACCENT := "CBA6F7"
BORDER_BGR := 0x00F7A6CB ; mauve as COLORREF (0x00BBGGRR)

SHOW_DELAY_MS := 120 ; a quick Alt+Tab tap switches without flashing the panel
POLL_MS := 15
MAX_ROWS := 12
; Sizes in 96-DPI pixels, scaled per monitor.
PANEL_W := 560
PAD := 12
HEADER_H := 26
ROW_H := 40
ROW_GAP := 4
ICON_SIZE := 22
FONT_PT := 10

EXCLUDED_PROCS := Map("zebar.exe", 1, "glazewm.exe", 1, "glazewm-watcher.exe", 1)
EXCLUDED_CLASSES := Map("Progman", 1, "WorkerW", 1, "Shell_TrayWnd", 1
    , "Shell_SecondaryTrayWnd", 1, "Windows.UI.Core.CoreWindow", 1)

state := { active: false, list: [], index: 1, monitor: 0, gui: 0, rows: [], shown: false, startTick: 0 }

!Tab:: Step(1)
!+Tab:: Step(-1)

#HotIf state.active
!Esc:: Finish()
#HotIf

Step(dir) {
    global state
    if !state.active && !Begin()
        return
    n := state.list.Length
    state.index := Mod(state.index - 1 + dir + n, n) + 1
    if state.shown
        Highlight()
}

Begin() {
    global state
    monitor := FocusedMonitor()
    list := CollectWindows(monitor)
    if list.Length = 0
        return false
    state.active := true
    state.list := list
    state.monitor := monitor
    state.shown := false
    state.startTick := A_TickCount
    ; Start "before" the first entry when the active window is not listed
    ; (desktop, bar), so the first Tab selects the top window.
    state.index := list[1].hwnd = WinExist("A") ? 1 : 0
    SetTimer(Poll, POLL_MS)
    return true
}

Poll() {
    global state
    if !state.active {
        SetTimer(Poll, 0)
        return
    }
    if !GetKeyState("Alt") {
        hwnd := state.list[state.index].hwnd
        Finish()
        Activate(hwnd)
        return
    }
    if !state.shown && A_TickCount - state.startTick >= SHOW_DELAY_MS
        ShowPanel()
}

Finish() {
    global state
    SetTimer(Poll, 0)
    state.active := false
    state.shown := false
    if state.gui {
        state.gui.Destroy()
        state.gui := 0
    }
    state.rows := []
}

Activate(hwnd) {
    try {
        if WinGetMinMax(hwnd) = -1
            WinRestore(hwnd)
        WinActivate(hwnd)
        WarpCursorInto(hwnd)
    } catch as err {
        OutputDebug("alttab: activate failed: " err.Message)
    }
}

; GlazeWM focus follows the cursor, so after a keyboard switch the cursor must
; sit on the chosen window - otherwise the next mouse move refocuses whatever
; window was under it. Like Hyprland, warp it to the window's center.
WarpCursorInto(hwnd) {
    WinGetPos(&x, &y, &w, &h, hwnd)
    pt := Buffer(8)
    DllCall("GetCursorPos", "ptr", pt)
    cx := NumGet(pt, 0, "int"), cy := NumGet(pt, 4, "int")
    if cx >= x && cx < x + w && cy >= y && cy < y + h && DllCall("WindowFromPoint", "int64", NumGet(pt, "int64"), "ptr") {
        root := DllCall("GetAncestor", "ptr", DllCall("WindowFromPoint", "int64", NumGet(pt, "int64"), "ptr"), "uint", 2, "ptr")
        if root = hwnd
            return ; already over the window and nothing covers it
    }
    DllCall("SetCursorPos", "int", x + w // 2, "int", y + h // 2)
}

; ---------- window discovery ----------

FocusedMonitor() {
    fg := WinExist("A")
    if fg && IsSwitchable(fg)
        return MonitorOf(fg)
    pt := Buffer(8)
    DllCall("GetCursorPos", "ptr", pt)
    return DllCall("MonitorFromPoint", "int64", NumGet(pt, "int64"), "uint", 2, "ptr")
}

MonitorOf(hwnd) => DllCall("MonitorFromWindow", "ptr", hwnd, "uint", 2, "ptr")

CollectWindows(monitor) {
    result := []
    for hwnd in WinGetList() {
        if result.Length >= MAX_ROWS
            break
        if IsSwitchable(hwnd) && MonitorOf(hwnd) = monitor
            result.Push({ hwnd: hwnd, title: WinGetTitle(hwnd), icon: WindowIcon(hwnd) })
    }
    return result
}

IsSwitchable(hwnd) {
    static WS_EX_TOOLWINDOW := 0x80, WS_EX_APPWINDOW := 0x40000, WS_EX_NOACTIVATE := 0x08000000
    try {
        if !DllCall("IsWindowVisible", "ptr", hwnd)
            return false
        ex := WinGetExStyle(hwnd)
        isAppWindow := ex & WS_EX_APPWINDOW
        if !isAppWindow && (ex & (WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE))
            return false
        if !isAppWindow && DllCall("GetWindow", "ptr", hwnd, "uint", 4, "ptr") ; GW_OWNER
            return false
        if WinGetTitle(hwnd) = ""
            return false
        if EXCLUDED_CLASSES.Has(WinGetClass(hwnd))
            return false
        if EXCLUDED_PROCS.Has(StrLower(WinGetProcessName(hwnd)))
            return false
        return !IsCloaked(hwnd)
    } catch {
        return false ; window vanished while inspecting it
    }
}

IsCloaked(hwnd) {
    cloaked := 0
    DllCall("dwmapi\DwmGetWindowAttribute", "ptr", hwnd, "uint", 14, "uint*", &cloaked, "uint", 4)
    return cloaked != 0
}

WindowIcon(hwnd) {
    static WM_GETICON := 0x7F
    for wParam in [1, 2, 0] { ; ICON_BIG, ICON_SMALL2, ICON_SMALL
        try {
            h := SendMessage(WM_GETICON, wParam, 0, , hwnd, , , , 50)
            if h
                return "HICON:*" h
        }
    }
    for index in [-14, -34] { ; GCLP_HICON, GCLP_HICONSM
        h := DllCall("GetClassLongPtrW", "ptr", hwnd, "int", index, "ptr")
        if h
            return "HICON:*" h
    }
    try return WinGetProcessPath(hwnd)
    return ""
}

; ---------- panel ----------

ShowPanel() {
    global state
    dpi := 96, dpiY := 96
    DllCall("shcore\GetDpiForMonitor", "ptr", state.monitor, "int", 0, "uint*", &dpi, "uint*", &dpiY)
    s := dpi / 96
    px := (v) => Round(v * s)
    fontPt := Round(FONT_PT * dpi / A_ScreenDPI)

    g := Gui("+AlwaysOnTop -Caption +ToolWindow -DPIScale +E0x08000000") ; WS_EX_NOACTIVATE
    g.BackColor := BASE
    g.MarginX := 0, g.MarginY := 0

    g.SetFont("s" Round(fontPt * 0.85) " c" OVERLAY, "Segoe UI Semibold")
    count := state.list.Length
    g.Add("Text", Format("x{} y{} w{} h{} 0x200 Background{}", px(PAD + 4), px(PAD), px(PANEL_W - PAD * 2), px(HEADER_H), BASE)
        , Format("{} {} ON THIS SCREEN", count, count = 1 ? "WINDOW" : "WINDOWS"))

    g.SetFont("s" fontPt " c" SUBTEXT " norm", "Segoe UI")
    rows := []
    for i, item in state.list {
        y := PAD + HEADER_H + (i - 1) * (ROW_H + ROW_GAP)
        bg := g.Add("Text", Format("x{} y{} w{} h{} Background{}", px(PAD), px(y), px(PANEL_W - PAD * 2), px(ROW_H), BASE))
        bar := g.Add("Text", Format("x{} y{} w{} h{} Background{} Hidden", px(PAD), px(y + 8), px(3), px(ROW_H - 16), ACCENT))
        pic := 0
        if item.icon
            try pic := g.Add("Picture", Format("x{} y{} w{} h{}", px(PAD + 14), px(y + (ROW_H - ICON_SIZE) / 2), px(ICON_SIZE), px(ICON_SIZE)) " Background" BASE, item.icon)
        ; 0x200 = vertically centered, 0x80 = no & mnemonics, 0x4000 = end ellipsis
        title := g.Add("Text", Format("x{} y{} w{} h{} 0x200 0x80 0x4000 Background{}", px(PAD + 50), px(y), px(PANEL_W - PAD * 2 - 62), px(ROW_H), BASE), item.title)
        rows.Push({ bg: bg, bar: bar, pic: pic, title: title })
    }
    panelH := PAD * 2 + HEADER_H + count * ROW_H + (count - 1) * ROW_GAP

    state.gui := g
    state.rows := rows
    g.Show(Format("Hide w{} h{}", px(PANEL_W), px(panelH)))
    DllCall("dwmapi\DwmSetWindowAttribute", "ptr", g.Hwnd, "uint", 33, "int*", 2, "uint", 4) ; rounded corners
    DllCall("dwmapi\DwmSetWindowAttribute", "ptr", g.Hwnd, "uint", 34, "uint*", BORDER_BGR, "uint", 4) ; border color

    work := MonitorWorkArea(state.monitor)
    WinGetPos(, , &w, &h, g.Hwnd)
    WinMove(work.left + (work.right - work.left - w) // 2, work.top + (work.bottom - work.top - h) // 2, , , g.Hwnd)
    Highlight()
    g.Show("NA")
    state.shown := true
}

Highlight() {
    global state
    for i, row in state.rows {
        selected := i = state.index
        color := selected ? SURFACE : BASE
        row.bg.Opt("+Background" color)
        row.bg.Redraw()
        row.bar.Visible := selected
        row.title.Opt("+Background" color)
        row.title.SetFont(selected ? "c" TEXT " bold" : "c" SUBTEXT " norm")
        row.title.Redraw()
        if row.pic {
            row.pic.Opt("+Background" color)
            row.pic.Redraw()
        }
    }
}

MonitorWorkArea(hMon) {
    info := Buffer(40, 0)
    NumPut("uint", 40, info, 0)
    DllCall("GetMonitorInfoW", "ptr", hMon, "ptr", info)
    return { left: NumGet(info, 20, "int"), top: NumGet(info, 24, "int")
        , right: NumGet(info, 28, "int"), bottom: NumGet(info, 32, "int") }
}
