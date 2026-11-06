; Disables minimizing: any app window that gets minimized (title-bar button,
; Win+Down, etc.) is restored right away, back to its GlazeWM state.
; Uses IsSwitchable() from workspace-alttab.ahk to skip tool/owned windows.

NOMIN_RESTORE_DELAY_MS := 60 ; let the minimize finish before undoing it

NoMin_Init()

NoMin_Init() {
    static EVENT_SYSTEM_MINIMIZESTART := 0x0016
    callback := CallbackCreate(NoMin_OnMinimize, "F", 7)
    DllCall("SetWinEventHook", "uint", EVENT_SYSTEM_MINIMIZESTART, "uint", EVENT_SYSTEM_MINIMIZESTART
        , "ptr", 0, "ptr", callback, "uint", 0, "uint", 0, "uint", 0, "ptr")
}

NoMin_OnMinimize(hook, event, hwnd, idObject, idChild, thread, time) {
    if idObject != 0 || !IsSwitchable(hwnd)
        return
    SetTimer(() => NoMin_Restore(hwnd), -NOMIN_RESTORE_DELAY_MS)
}

NoMin_Restore(hwnd) {
    static WM_SYSCOMMAND := 0x0112, SC_RESTORE := 0xF120
    try {
        if WinGetMinMax(hwnd) = -1
            PostMessage(WM_SYSCOMMAND, SC_RESTORE, 0, , hwnd)
    } catch as err {
        OutputDebug("nominimize: restore failed: " err.Message)
    }
}
