; Hides the native Windows taskbar on every monitor while this script runs
; (Zebar's hyprbar replaces it). Re-hides it whenever Explorer shows it again
; or restarts, and restores it when the script exits. Win+Shift+T toggles.
; Taskbar auto-hide stays on in Windows settings so no screen space is reserved.

TASKBAR_CLASSES := Map("Shell_TrayWnd", 1, "Shell_SecondaryTrayWnd", 1)
TASKBAR_SAFETY_POLL_MS := 2000
taskbarHidden := true

Taskbar_Init()

#+t:: Taskbar_Toggle()

Taskbar_Init() {
    ; Explorer broadcasts TaskbarCreated after it (re)creates the taskbar.
    msg := DllCall("RegisterWindowMessage", "str", "TaskbarCreated", "uint")
    OnMessage(msg, (*) => SetTimer(Taskbar_Apply, -500))
    ; React instantly when Explorer re-shows a taskbar window.
    static EVENT_OBJECT_SHOW := 0x8002
    callback := CallbackCreate(Taskbar_OnShow, "F", 7)
    DllCall("SetWinEventHook", "uint", EVENT_OBJECT_SHOW, "uint", EVENT_OBJECT_SHOW
        , "ptr", 0, "ptr", callback, "uint", 0, "uint", 0, "uint", 0, "ptr")
    SetTimer(Taskbar_Apply, TASKBAR_SAFETY_POLL_MS)
    OnExit(Taskbar_Restore)
    Taskbar_Apply()
}

Taskbar_OnShow(hook, event, hwnd, idObject, idChild, thread, time) {
    if taskbarHidden && idObject = 0 && Taskbar_IsTaskbar(hwnd)
        DllCall("ShowWindow", "ptr", hwnd, "int", 0) ; SW_HIDE
}

Taskbar_IsTaskbar(hwnd) {
    try return TASKBAR_CLASSES.Has(WinGetClass(hwnd))
    return false
}

Taskbar_Apply() {
    DetectHiddenWindows(true)
    for cls in TASKBAR_CLASSES {
        for hwnd in WinGetList("ahk_class " cls) {
            visible := DllCall("IsWindowVisible", "ptr", hwnd)
            if taskbarHidden && visible
                DllCall("ShowWindow", "ptr", hwnd, "int", 0) ; SW_HIDE
            else if !taskbarHidden && !visible
                DllCall("ShowWindow", "ptr", hwnd, "int", 8) ; SW_SHOWNA
        }
    }
}

Taskbar_Toggle() {
    global taskbarHidden := !taskbarHidden
    Taskbar_Apply()
}

Taskbar_Restore(*) {
    global taskbarHidden := false
    Taskbar_Apply()
}
