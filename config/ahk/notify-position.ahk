; Moves app-drawn notification popups to the bottom-right corner.
; Apps like Zalo place their own popups next to the native taskbar; with the
; taskbar hidden (taskbar.ahk) they fall back to the middle of the screen.
; Uses MonitorWorkArea() from workspace-alttab.ahk.

; A popup matches when its process is listed and it is small (physical px,
; so the limits allow for 150% scaling).
NOTIFY_PROCS := Map("zalo.exe", 1)
NOTIFY_MAX_W := 700
NOTIFY_MAX_H := 300
NOTIFY_MARGIN := 12          ; 96-DPI px from the work-area edge
NOTIFY_RECHECKS := 10        ; re-place a few times in case the app moves it back
NOTIFY_RECHECK_MS := 100

Notify_Init()

Notify_Init() {
    static EVENT_OBJECT_SHOW := 0x8002
    callback := CallbackCreate(Notify_OnShow, "F", 7)
    DllCall("SetWinEventHook", "uint", EVENT_OBJECT_SHOW, "uint", EVENT_OBJECT_SHOW
        , "ptr", 0, "ptr", callback, "uint", 0, "uint", 0, "uint", 0, "ptr")
}

Notify_OnShow(hook, event, hwnd, idObject, idChild, thread, time) {
    if idObject != 0 || !Notify_IsPopup(hwnd)
        return
    Notify_Place(hwnd)
    state := { left: NOTIFY_RECHECKS }
    recheck := () => Notify_Recheck(hwnd, state, recheck)
    SetTimer(recheck, NOTIFY_RECHECK_MS)
}

Notify_Recheck(hwnd, state, timer) {
    state.left -= 1
    if state.left <= 0 || !DllCall("IsWindowVisible", "ptr", hwnd) {
        SetTimer(timer, 0)
        return
    }
    Notify_Place(hwnd)
}

Notify_IsPopup(hwnd) {
    try {
        if !NOTIFY_PROCS.Has(StrLower(WinGetProcessName(hwnd)))
            return false
        WinGetPos(, , &w, &h, hwnd)
        return w > 0 && h > 0 && w <= NOTIFY_MAX_W && h <= NOTIFY_MAX_H
    } catch {
        return false ; window vanished
    }
}

Notify_Place(hwnd) {
    try {
        WinGetPos(&x, &y, &w, &h, hwnd)
        hMon := DllCall("MonitorFromWindow", "ptr", hwnd, "uint", 2, "ptr")
        dpi := 96, dpiY := 96
        DllCall("shcore\GetDpiForMonitor", "ptr", hMon, "int", 0, "uint*", &dpi, "uint*", &dpiY)
        margin := Round(NOTIFY_MARGIN * dpi / 96)
        work := MonitorWorkArea(hMon)
        tx := work.right - w - margin
        ty := work.bottom - h - margin
        if x != tx || y != ty
            DllCall("SetWindowPos", "ptr", hwnd, "ptr", 0, "int", tx, "int", ty, "int", 0, "int", 0
                , "uint", 0x0001 | 0x0004 | 0x0010) ; NOSIZE | NOZORDER | NOACTIVATE
    } catch as err {
        OutputDebug("notify: place failed: " err.Message)
    }
}
